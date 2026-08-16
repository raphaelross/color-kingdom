
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:color_kingdom/features/categories/models/category.dart';
import 'package:color_kingdom/features/coloring/data/sample_coloring_pages.dart';
import 'package:color_kingdom/features/coloring/models/coloring_page.dart';
import 'package:color_kingdom/features/coloring/models/coloring_session.dart';
import 'package:color_kingdom/features/coloring/models/coloring_state.dart';
import 'package:color_kingdom/features/coloring/providers/coloring_provider.dart';
import 'package:color_kingdom/features/coloring/repositories/coloring_page_repository.dart';
import 'package:color_kingdom/features/coloring/repositories/coloring_session_repository.dart';

class _FakeRepository implements ColoringPageRepository {
  _FakeRepository(this.pages);

  final List<ColoringPage> pages;

  @override
  Future<List<Category>> getCategories() async => const [
        Category(categoryId: 'animals', title: 'Animals', sortOrder: 0),
      ];

  @override
  Future<ColoringPage> getPageById(String id) async {
    return pages.firstWhere((page) => page.id == id);
  }

  @override
  Future<List<ColoringPage>> getPages() async => pages;

  @override
  Future<List<ColoringPage>> getPagesByCategory(String categoryId) async {
    return pages.where((page) => page.categoryId == categoryId).toList(growable: false);
  }
}

class _MemorySessionRepository implements ColoringSessionRepository {
  final Map<String, ColoringSession> sessions = <String, ColoringSession>{};

  @override
  Future<void> clearAllSessions() async {
    sessions.clear();
  }

  @override
  Future<void> deleteSession(String pageId) async {
    sessions.remove(pageId);
  }

  @override
  Future<List<ColoringSession>> getAllSessions() async {
    return sessions.values.toList(growable: false);
  }

  @override
  Future<ColoringSession?> getSession(String pageId) async {
    return sessions[pageId];
  }

  @override
  Future<void> saveSession(ColoringSession session) async {
    sessions[session.pageId] = session;
  }
}

Future<ColoringState> _waitForReady(ProviderContainer container) async {
  for (var i = 0; i < 40; i++) {
    final state = container.read(coloringControllerProvider);
    if (state.status == ColoringLoadStatus.ready) {
      return state;
    }
    await Future<void>.delayed(const Duration(milliseconds: 10));
  }
  return container.read(coloringControllerProvider);
}

ProviderContainer _buildContainer({
  required String initialPageId,
  required ColoringPageRepository pageRepository,
  required ColoringSessionRepository sessionRepository,
}) {
  return ProviderContainer(
    overrides: [
      coloringInitialPageIdProvider.overrideWithValue(initialPageId),
      coloringPageRepositoryProvider.overrideWithValue(pageRepository),
      coloringSessionRepositoryProvider.overrideWithValue(sessionRepository),
    ],
  );
}

void main() {
  test('raster page uses normal controller persistence and restores colors', () async {
    final sessionRepository = _MemorySessionRepository();
    final pageRepository = _FakeRepository([
      sampleHappyCatPage,
      sampleLovelyKittenPage,
    ]);

    final container = _buildContainer(
      initialPageId: 'lovely-kitten-raster-poc',
      pageRepository: pageRepository,
      sessionRepository: sessionRepository,
    );
    addTearDown(container.dispose);

    await _waitForReady(container);
    final controller = container.read(coloringControllerProvider.notifier);

    controller.selectColor(Colors.green);
    controller.fillRegion('region-002');
    await controller.waitForPendingPersistence();

    final saved = sessionRepository.sessions['lovely-kitten-raster-poc'];
    expect(saved, isNotNull);
    expect(saved!.regionColors['region-002'], Colors.green.toARGB32());

    final secondContainer = _buildContainer(
      initialPageId: 'lovely-kitten-raster-poc',
      pageRepository: pageRepository,
      sessionRepository: sessionRepository,
    );
    addTearDown(secondContainer.dispose);

    final restored = await _waitForReady(secondContainer);
    expect(restored.regionColors['region-002']?.toARGB32(), Colors.green.toARGB32());
  });

  test('state does not leak between raster and svg pages', () async {
    final sessionRepository = _MemorySessionRepository();
    final pageRepository = _FakeRepository([
      sampleHappyCatPage,
      sampleLovelyKittenPage,
    ]);

    final container = _buildContainer(
      initialPageId: 'lovely-kitten-raster-poc',
      pageRepository: pageRepository,
      sessionRepository: sessionRepository,
    );
    addTearDown(container.dispose);

    await _waitForReady(container);
    final controller = container.read(coloringControllerProvider.notifier);

    controller.selectColor(Colors.red);
    controller.fillRegion('region-002');

    await controller.loadPageById('happy-cat');

    final state = container.read(coloringControllerProvider);
    expect(state.page!.id, 'happy-cat');
    expect(state.regionColors.containsKey('region-002'), isFalse);
    expect(state.regionColors.containsKey('cat-body'), isTrue);
    expect(state.undoStack, isEmpty);
    expect(state.redoStack, isEmpty);
  });
}
