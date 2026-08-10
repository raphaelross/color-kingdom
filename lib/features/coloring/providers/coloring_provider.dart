import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../categories/models/category.dart';
import '../models/coloring_page.dart';
import '../models/coloring_session.dart';
import '../models/coloring_state.dart';
import '../repositories/coloring_page_repository.dart';
import '../repositories/local_coloring_page_repository.dart';
import '../repositories/coloring_session_repository.dart';
import '../repositories/local_coloring_session_repository.dart';

final coloringPageRepositoryProvider = Provider<ColoringPageRepository>(
  (ref) => LocalColoringPageRepository(),
);

final coloringSessionRepositoryProvider = Provider<ColoringSessionRepository>(
  (ref) => LocalColoringSessionRepository(),
);

final coloringInitialPageIdProvider = Provider<String>(
  (ref) => 'happy-cat',
);

final availableColoringPagesProvider = FutureProvider<List<ColoringPage>>(
  (ref) => ref.watch(coloringPageRepositoryProvider).getPages(),
);

final availableCategoriesProvider = FutureProvider<List<Category>>(
  (ref) => ref.watch(coloringPageRepositoryProvider).getCategories(),
);

final categoryPagesProvider = FutureProvider.family<List<ColoringPage>, String>(
  (ref, categoryId) => ref
      .watch(coloringPageRepositoryProvider)
      .getPagesByCategory(categoryId),
);

final coloringControllerProvider =
    StateNotifierProvider<ColoringController, ColoringState>(
  (ref) {
    final pageRepository = ref.watch(coloringPageRepositoryProvider);
    final sessionRepository = ref.watch(coloringSessionRepositoryProvider);
    final initialPageId = ref.watch(coloringInitialPageIdProvider);
    final controller = ColoringController(
      pageRepository,
      sessionRepository,
      initialPageId: initialPageId,
    );
    unawaited(controller.loadInitialPage());
    return controller;
  },
  dependencies: [
    coloringPageRepositoryProvider,
    coloringSessionRepositoryProvider,
    coloringInitialPageIdProvider,
  ],
);

class ColoringController extends StateNotifier<ColoringState> {
  ColoringController(
    this._pageRepository,
    this._sessionRepository, {
    this.initialPageId = 'happy-cat',
  }) : super(ColoringState.loading());

  final ColoringPageRepository _pageRepository;
  final ColoringSessionRepository _sessionRepository;
  final String initialPageId;

  Future<void> _persistenceQueue = Future<void>.value();
  int _latestSaveSequence = 0;

  Future<void> loadInitialPage() async {
    await loadPageById(initialPageId);
  }

  Future<void> loadPageById(String pageId) async {
    final selectedColor = state.selectedColor;
    state = ColoringState.loading(selectedColor: selectedColor);

    try {
      final page = await _pageRepository.getPageById(pageId);
      var regionColors = _initialRegionColors(page);

      try {
        final session = await _sessionRepository.getSession(page.id);
        if (session != null) {
          regionColors = _mergeRestoredRegionColors(
            baseColors: regionColors,
            restoredColors: session.regionColors,
          );
        }
      } catch (error) {
        debugPrint('Coloring session restore failed for ${page.id}: $error');
      }

      state = ColoringState.ready(
        page: page,
        regionColors: regionColors,
        selectedColor: selectedColor,
      );
    } on StateError catch (error) {
      state = ColoringState.error(
        message: error.message,
        selectedColor: selectedColor,
      );
    } catch (error) {
      state = ColoringState.error(
        message: 'Failed to load coloring page: $error',
        selectedColor: selectedColor,
      );
    }
  }

  void selectColor(Color color) {
    state = state.copyWith(selectedColor: color);
  }

  void fillRegion(String regionId) {
    if (!state.isReady || state.page == null) {
      return;
    }

    final previousColor = state.regionColors[regionId];
    if (previousColor == null) {
      return;
    }

    final nextColor = state.selectedColor;
    if (previousColor == nextColor) {
      return;
    }

    final action = ColoringHistoryAction(
      regionId: regionId,
      previousColor: previousColor,
      nextColor: nextColor,
    );

    final currentColors = Map<String, Color>.from(state.regionColors);
    currentColors[regionId] = nextColor;

    state = state.copyWith(
      regionColors: currentColors,
      undoStack: [...state.undoStack, action],
      redoStack: const [],
    );

    _schedulePersistCurrentPageState();
  }

  void undo() {
    if (!state.isReady || state.undoStack.isEmpty) {
      return;
    }

    final lastAction = state.undoStack.last;
    final remainingUndo = [...state.undoStack]..removeLast();
    final nextColors = Map<String, Color>.from(state.regionColors);
    nextColors[lastAction.regionId] = lastAction.previousColor;

    state = state.copyWith(
      regionColors: nextColors,
      undoStack: remainingUndo,
      redoStack: [lastAction, ...state.redoStack],
    );

    _schedulePersistCurrentPageState();
  }

  void redo() {
    if (!state.isReady || state.redoStack.isEmpty) {
      return;
    }

    final action = state.redoStack.first;
    final nextColors = Map<String, Color>.from(state.regionColors);
    nextColors[action.regionId] = action.nextColor;

    state = state.copyWith(
      regionColors: nextColors,
      undoStack: [...state.undoStack, action],
      redoStack: state.redoStack.sublist(1),
    );

    _schedulePersistCurrentPageState();
  }

  void clear() {
    if (!state.isReady || state.page == null) {
      return;
    }

    state = ColoringState.ready(
      page: state.page!,
      regionColors: _initialRegionColors(state.page!),
      selectedColor: state.selectedColor,
    );

    _scheduleDeleteCurrentPageSession();
  }

  Future<void> setPage(ColoringPage page) async {
    await loadPageById(page.id);
  }

  Map<String, Color> _initialRegionColors(ColoringPage page) {
    return {
      for (final region in page.regions) region.id: region.defaultColor,
    };
  }

  Map<String, Color> _mergeRestoredRegionColors({
    required Map<String, Color> baseColors,
    required Map<String, int> restoredColors,
  }) {
    final merged = Map<String, Color>.from(baseColors);
    for (final entry in restoredColors.entries) {
      if (!merged.containsKey(entry.key)) {
        continue;
      }
      merged[entry.key] = Color(entry.value);
    }
    return merged;
  }

  void _schedulePersistCurrentPageState() {
    if (!state.isReady || state.page == null) {
      return;
    }

    final readyState = state;
    final page = readyState.page!;
    final capturedColors = Map<String, Color>.from(readyState.regionColors);
    final saveSequence = ++_latestSaveSequence;

    _enqueuePersistenceTask(() async {
      if (saveSequence != _latestSaveSequence) {
        return;
      }

      final session = ColoringSession(
        pageId: page.id,
        regionColors: {
          for (final entry in capturedColors.entries) entry.key: entry.value.toARGB32(),
        },
        schemaVersion: ColoringSession.currentSchemaVersion,
        lastUpdatedAtEpochMs: DateTime.now().millisecondsSinceEpoch,
      );

      try {
        await _sessionRepository.saveSession(session);
      } catch (error) {
        debugPrint('Coloring session save failed for ${page.id}: $error');
      }
    });
  }

  void _scheduleDeleteCurrentPageSession() {
    if (!state.isReady || state.page == null) {
      return;
    }

    final pageId = state.page!.id;
    final saveSequence = ++_latestSaveSequence;

    _enqueuePersistenceTask(() async {
      if (saveSequence != _latestSaveSequence) {
        return;
      }

      try {
        await _sessionRepository.deleteSession(pageId);
      } catch (error) {
        debugPrint('Coloring session delete failed for $pageId: $error');
      }
    });
  }

  void _enqueuePersistenceTask(Future<void> Function() task) {
    _persistenceQueue = _persistenceQueue.then((_) => task());
    _persistenceQueue = _persistenceQueue.catchError((error) {
      debugPrint('Coloring persistence queue error: $error');
    });
  }
}
