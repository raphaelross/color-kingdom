import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/coloring_page.dart';
import '../models/coloring_state.dart';
import '../repositories/coloring_page_repository.dart';
import '../repositories/local_coloring_page_repository.dart';

final coloringPageRepositoryProvider = Provider<ColoringPageRepository>(
  (ref) => LocalColoringPageRepository(),
);

final coloringInitialPageIdProvider = Provider<String>(
  (ref) => 'happy-cat',
);

final availableColoringPagesProvider = FutureProvider<List<ColoringPage>>(
  (ref) => ref.watch(coloringPageRepositoryProvider).getPages(),
);

final coloringControllerProvider =
    StateNotifierProvider<ColoringController, ColoringState>(
  (ref) {
    final repository = ref.watch(coloringPageRepositoryProvider);
    final initialPageId = ref.watch(coloringInitialPageIdProvider);
    final controller = ColoringController(
      repository,
      initialPageId: initialPageId,
    );
    unawaited(controller.loadInitialPage());
    return controller;
  },
  dependencies: [
    coloringPageRepositoryProvider,
    coloringInitialPageIdProvider,
  ],
);

class ColoringController extends StateNotifier<ColoringState> {
  ColoringController(
    this._repository, {
    this.initialPageId = 'happy-cat',
  }) : super(ColoringState.loading());

  final ColoringPageRepository _repository;
  final String initialPageId;

  Future<void> loadInitialPage() async {
    await loadPageById(initialPageId);
  }

  Future<void> loadPageById(String pageId) async {
    final selectedColor = state.selectedColor;
    state = ColoringState.loading(selectedColor: selectedColor);

    try {
      final page = await _repository.getPageById(pageId);
      state = ColoringState.ready(
        page: page,
        regionColors: _initialRegionColors(page),
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
  }

  Future<void> setPage(ColoringPage page) async {
    await loadPageById(page.id);
  }

  Map<String, Color> _initialRegionColors(ColoringPage page) {
    return {
      for (final region in page.regions) region.id: region.defaultColor,
    };
  }
}
