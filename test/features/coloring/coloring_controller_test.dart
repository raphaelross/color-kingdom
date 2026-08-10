import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:color_kingdom/features/coloring/data/sample_coloring_pages.dart';
import 'package:color_kingdom/features/coloring/models/coloring_page.dart';
import 'package:color_kingdom/features/coloring/models/coloring_session.dart';
import 'package:color_kingdom/features/coloring/models/coloring_state.dart';
import 'package:color_kingdom/features/coloring/providers/coloring_provider.dart';
import 'package:color_kingdom/features/coloring/repositories/coloring_page_repository.dart';
import 'package:color_kingdom/features/coloring/repositories/coloring_session_repository.dart';
import 'package:color_kingdom/features/categories/models/category.dart';

class _FakeRepository implements ColoringPageRepository {
  _FakeRepository(this.pages);

  final List<ColoringPage> pages;

  @override
  Future<List<ColoringPage>> getPages() async => pages;

  @override
  Future<List<Category>> getCategories() async => const [
        Category(categoryId: 'animals', title: 'Animals', sortOrder: 0),
      ];

  @override
  Future<List<ColoringPage>> getPagesByCategory(String categoryId) async {
    return pages.where((page) => page.categoryId == categoryId).toList();
  }

  @override
  Future<ColoringPage> getPageById(String id) async {
    return pages.firstWhere((page) => page.id == id);
  }
}

class _DelayedRepository implements ColoringPageRepository {
  final Completer<ColoringPage> _completer = Completer<ColoringPage>();

  void complete(ColoringPage page) {
    _completer.complete(page);
  }

  @override
  Future<List<ColoringPage>> getPages() async => [await _completer.future];

  @override
  Future<List<Category>> getCategories() async => const [
        Category(categoryId: 'animals', title: 'Animals', sortOrder: 0),
      ];

  @override
  Future<List<ColoringPage>> getPagesByCategory(String categoryId) async {
    final page = await _completer.future;
    return page.categoryId == categoryId ? [page] : const [];
  }

  @override
  Future<ColoringPage> getPageById(String id) async => _completer.future;
}

class _MemorySessionRepository implements ColoringSessionRepository {
  final Map<String, ColoringSession> sessions = <String, ColoringSession>{};
  final Set<String> readFailures = <String>{};
  final Set<String> writeFailures = <String>{};
  final Set<String> deleteFailures = <String>{};
  final List<ColoringSession> saveHistory = <ColoringSession>[];
  final List<String> deleteHistory = <String>[];

  @override
  Future<ColoringSession?> getSession(String pageId) async {
    if (readFailures.contains(pageId)) {
      throw StateError('Read failure for $pageId');
    }
    return sessions[pageId];
  }

  @override
  Future<void> saveSession(ColoringSession session) async {
    if (writeFailures.contains(session.pageId)) {
      throw StateError('Write failure for ${session.pageId}');
    }
    sessions[session.pageId] = session;
    saveHistory.add(session);
  }

  @override
  Future<void> deleteSession(String pageId) async {
    if (deleteFailures.contains(pageId)) {
      throw StateError('Delete failure for $pageId');
    }
    sessions.remove(pageId);
    deleteHistory.add(pageId);
  }

  @override
  Future<void> clearAllSessions() async {
    sessions.clear();
  }
}

Future<ColoringState> _waitForReady(ProviderContainer container) async {
  for (var i = 0; i < 30; i++) {
    final state = container.read(coloringControllerProvider);
    if (state.status == ColoringLoadStatus.ready) {
      return state;
    }
    await Future<void>.delayed(const Duration(milliseconds: 10));
  }
  return container.read(coloringControllerProvider);
}

Future<void> _flushPersistenceQueue() async {
  await Future<void>.delayed(const Duration(milliseconds: 10));
  await Future<void>.delayed(const Duration(milliseconds: 10));
}

void _expectColorValue(Color? actual, Color expected) {
  expect(actual, isNotNull);
  expect(actual!.toARGB32(), expected.toARGB32());
}

ProviderContainer _buildContainer({
  required ColoringPageRepository pageRepository,
  required ColoringSessionRepository sessionRepository,
  String initialPageId = 'happy-cat',
}) {
  return ProviderContainer(
    overrides: [
      coloringPageRepositoryProvider.overrideWithValue(pageRepository),
      coloringSessionRepositoryProvider.overrideWithValue(sessionRepository),
      coloringInitialPageIdProvider.overrideWithValue(initialPageId),
    ],
  );
}

void main() {
  test('page loads normally without saved session', () async {
    final sessionRepository = _MemorySessionRepository();
    final container = _buildContainer(
      pageRepository: _FakeRepository([sampleHappyCatPage]),
      sessionRepository: sessionRepository,
    );
    addTearDown(container.dispose);

    final initial = container.read(coloringControllerProvider);
    expect(initial.status, ColoringLoadStatus.loading);

    final ready = await _waitForReady(container);
    expect(ready.status, ColoringLoadStatus.ready);
    expect(ready.page?.id, 'happy-cat');
    expect(ready.regionColors['cat-body'], Colors.transparent);
  });

  test('page restores saved region colors', () async {
    final sessionRepository = _MemorySessionRepository();
    sessionRepository.sessions['happy-cat'] = ColoringSession(
      pageId: 'happy-cat',
      regionColors: <String, int>{
        'cat-body': Colors.red.toARGB32(),
        'cat-tail': Colors.green.toARGB32(),
      },
      schemaVersion: ColoringSession.currentSchemaVersion,
      lastUpdatedAtEpochMs: 1,
    );

    final container = _buildContainer(
      pageRepository: _FakeRepository([sampleHappyCatPage]),
      sessionRepository: sessionRepository,
    );
    addTearDown(container.dispose);

    final ready = await _waitForReady(container);
    _expectColorValue(ready.regionColors['cat-body'], Colors.red);
    _expectColorValue(ready.regionColors['cat-tail'], Colors.green);
  });

  test('unknown saved region IDs are ignored', () async {
    final sessionRepository = _MemorySessionRepository();
    sessionRepository.sessions['happy-cat'] = ColoringSession(
      pageId: 'happy-cat',
      regionColors: <String, int>{
        'cat-body': Colors.red.toARGB32(),
        'unknown-region': Colors.blue.toARGB32(),
      },
      schemaVersion: ColoringSession.currentSchemaVersion,
      lastUpdatedAtEpochMs: 1,
    );

    final container = _buildContainer(
      pageRepository: _FakeRepository([sampleHappyCatPage]),
      sessionRepository: sessionRepository,
    );
    addTearDown(container.dispose);

    final ready = await _waitForReady(container);
    _expectColorValue(ready.regionColors['cat-body'], Colors.red);
    expect(ready.regionColors.containsKey('unknown-region'), isFalse);
  });

  test('new page regions absent from saved state retain defaults', () async {
    final sessionRepository = _MemorySessionRepository();
    sessionRepository.sessions['happy-cat'] = ColoringSession(
      pageId: 'happy-cat',
      regionColors: <String, int>{
        'cat-body': Colors.red.toARGB32(),
      },
      schemaVersion: ColoringSession.currentSchemaVersion,
      lastUpdatedAtEpochMs: 1,
    );

    final container = _buildContainer(
      pageRepository: _FakeRepository([sampleHappyCatPage]),
      sessionRepository: sessionRepository,
    );
    addTearDown(container.dispose);

    final ready = await _waitForReady(container);
    _expectColorValue(ready.regionColors['cat-body'], Colors.red);
    _expectColorValue(ready.regionColors['cat-tail'], Colors.transparent);
  });

  test('restored page starts with empty undo and redo stacks', () async {
    final sessionRepository = _MemorySessionRepository();
    sessionRepository.sessions['happy-cat'] = ColoringSession(
      pageId: 'happy-cat',
      regionColors: <String, int>{'cat-body': Colors.red.toARGB32()},
      schemaVersion: ColoringSession.currentSchemaVersion,
      lastUpdatedAtEpochMs: 1,
    );

    final container = _buildContainer(
      pageRepository: _FakeRepository([sampleHappyCatPage]),
      sessionRepository: sessionRepository,
    );
    addTearDown(container.dispose);

    final ready = await _waitForReady(container);
    expect(ready.undoStack, isEmpty);
    expect(ready.redoStack, isEmpty);
  });

  test('loading state transitions to ready with delayed repository', () async {
    final repository = _DelayedRepository();
    final sessionRepository = _MemorySessionRepository();
    final container = _buildContainer(
      pageRepository: repository,
      sessionRepository: sessionRepository,
    );
    addTearDown(container.dispose);

    expect(container.read(coloringControllerProvider).status, ColoringLoadStatus.loading);

    repository.complete(sampleHappyCatPage);

    final ready = await _waitForReady(container);
    expect(ready.status, ColoringLoadStatus.ready);
    expect(ready.page?.id, 'happy-cat');
  });

  test('region coloring creates one action entry', () async {
    final sessionRepository = _MemorySessionRepository();
    final container = _buildContainer(
      pageRepository: _FakeRepository([sampleHappyCatPage]),
      sessionRepository: sessionRepository,
    );
    addTearDown(container.dispose);

    await _waitForReady(container);

    final controller = container.read(coloringControllerProvider.notifier);
    controller.selectColor(Colors.red);
    controller.fillRegion('cat-body');

    final state = container.read(coloringControllerProvider);
    expect(state.regionColors['cat-body'], Colors.red);
    expect(state.undoStack.length, 1);
    expect(state.redoStack, isEmpty);
  });

  test('action-based undo and redo works for one action', () async {
    final sessionRepository = _MemorySessionRepository();
    final container = _buildContainer(
      pageRepository: _FakeRepository([sampleHappyCatPage]),
      sessionRepository: sessionRepository,
    );
    addTearDown(container.dispose);

    await _waitForReady(container);

    final controller = container.read(coloringControllerProvider.notifier);
    final initialColor =
        container.read(coloringControllerProvider).regionColors['cat-body'];

    controller.selectColor(Colors.blue);
    controller.fillRegion('cat-body');
    controller.undo();

    var state = container.read(coloringControllerProvider);
    expect(state.regionColors['cat-body'], initialColor);
    expect(state.undoStack, isEmpty);
    expect(state.redoStack.length, 1);

    controller.redo();
    state = container.read(coloringControllerProvider);
    expect(state.regionColors['cat-body'], Colors.blue);
    expect(state.undoStack.length, 1);
    expect(state.redoStack, isEmpty);
  });

  test('multiple actions support repeated undo and redo', () async {
    final sessionRepository = _MemorySessionRepository();
    final container = _buildContainer(
      pageRepository: _FakeRepository([sampleHappyCatPage]),
      sessionRepository: sessionRepository,
    );
    addTearDown(container.dispose);

    await _waitForReady(container);

    final controller = container.read(coloringControllerProvider.notifier);

    controller.selectColor(Colors.red);
    controller.fillRegion('cat-body');
    controller.selectColor(Colors.green);
    controller.fillRegion('cat-tail');

    controller.undo();
    controller.undo();

    var state = container.read(coloringControllerProvider);
    expect(state.regionColors['cat-body'], Colors.transparent);
    expect(state.regionColors['cat-tail'], Colors.transparent);
    expect(state.redoStack.length, 2);

    controller.redo();
    controller.redo();

    state = container.read(coloringControllerProvider);
    expect(state.regionColors['cat-body'], Colors.red);
    expect(state.regionColors['cat-tail'], Colors.green);
    expect(state.undoStack.length, 2);
    expect(state.redoStack, isEmpty);
  });

  test('undo followed by new action clears redo path', () async {
    final sessionRepository = _MemorySessionRepository();
    final container = _buildContainer(
      pageRepository: _FakeRepository([sampleHappyCatPage]),
      sessionRepository: sessionRepository,
    );
    addTearDown(container.dispose);

    await _waitForReady(container);

    final controller = container.read(coloringControllerProvider.notifier);

    controller.selectColor(Colors.orange);
    controller.fillRegion('cat-body');
    controller.selectColor(Colors.purple);
    controller.fillRegion('cat-tail');

    controller.undo();

    expect(container.read(coloringControllerProvider).redoStack.length, 1);

    controller.selectColor(Colors.cyan);
    controller.fillRegion('cat-head');

    final state = container.read(coloringControllerProvider);
    expect(state.redoStack, isEmpty);
  });

  test('clear resets colors and clears action history', () async {
    final sessionRepository = _MemorySessionRepository();
    final container = _buildContainer(
      pageRepository: _FakeRepository([sampleHappyCatPage]),
      sessionRepository: sessionRepository,
    );
    addTearDown(container.dispose);

    await _waitForReady(container);

    final controller = container.read(coloringControllerProvider.notifier);

    controller.selectColor(Colors.red);
    controller.fillRegion('cat-body');
    controller.fillRegion('cat-tail');

    controller.clear();

    final state = container.read(coloringControllerProvider);
    expect(state.regionColors['cat-body'], Colors.transparent);
    expect(state.regionColors['cat-tail'], Colors.transparent);
    expect(state.undoStack, isEmpty);
    expect(state.redoStack, isEmpty);
  });

  test('fill persists resulting state', () async {
    final sessionRepository = _MemorySessionRepository();
    final container = _buildContainer(
      pageRepository: _FakeRepository([sampleHappyCatPage]),
      sessionRepository: sessionRepository,
    );
    addTearDown(container.dispose);

    await _waitForReady(container);

    final controller = container.read(coloringControllerProvider.notifier);
    controller.selectColor(Colors.red);
    controller.fillRegion('cat-body');
    await _flushPersistenceQueue();

    final saved = sessionRepository.sessions['happy-cat'];
    expect(saved, isNotNull);
    expect(saved!.regionColors['cat-body'], Colors.red.toARGB32());
  });

  test('undo persists resulting state', () async {
    final sessionRepository = _MemorySessionRepository();
    final container = _buildContainer(
      pageRepository: _FakeRepository([sampleHappyCatPage]),
      sessionRepository: sessionRepository,
    );
    addTearDown(container.dispose);

    await _waitForReady(container);

    final controller = container.read(coloringControllerProvider.notifier);
    controller.selectColor(Colors.red);
    controller.fillRegion('cat-body');
    await _flushPersistenceQueue();

    controller.undo();
    await _flushPersistenceQueue();

    final saved = sessionRepository.sessions['happy-cat'];
    expect(saved, isNotNull);
    expect(saved!.regionColors['cat-body'], Colors.transparent.toARGB32());
  });

  test('redo persists resulting state', () async {
    final sessionRepository = _MemorySessionRepository();
    final container = _buildContainer(
      pageRepository: _FakeRepository([sampleHappyCatPage]),
      sessionRepository: sessionRepository,
    );
    addTearDown(container.dispose);

    await _waitForReady(container);

    final controller = container.read(coloringControllerProvider.notifier);
    controller.selectColor(Colors.red);
    controller.fillRegion('cat-body');
    controller.undo();
    controller.redo();
    await _flushPersistenceQueue();

    final saved = sessionRepository.sessions['happy-cat'];
    expect(saved, isNotNull);
    expect(saved!.regionColors['cat-body'], Colors.red.toARGB32());
  });

  test('clear deletes saved session', () async {
    final sessionRepository = _MemorySessionRepository();
    final container = _buildContainer(
      pageRepository: _FakeRepository([sampleHappyCatPage]),
      sessionRepository: sessionRepository,
    );
    addTearDown(container.dispose);

    await _waitForReady(container);

    final controller = container.read(coloringControllerProvider.notifier);
    controller.selectColor(Colors.red);
    controller.fillRegion('cat-body');
    await _flushPersistenceQueue();
    expect(sessionRepository.sessions.containsKey('happy-cat'), isTrue);

    controller.clear();
    await _flushPersistenceQueue();

    expect(sessionRepository.sessions.containsKey('happy-cat'), isFalse);
    expect(sessionRepository.deleteHistory, contains('happy-cat'));
  });

  test('persistence read failure does not prevent page from becoming ready', () async {
    final sessionRepository = _MemorySessionRepository()..readFailures.add('happy-cat');
    final container = _buildContainer(
      pageRepository: _FakeRepository([sampleHappyCatPage]),
      sessionRepository: sessionRepository,
    );
    addTearDown(container.dispose);

    final ready = await _waitForReady(container);

    expect(ready.status, ColoringLoadStatus.ready);
    expect(ready.page?.id, 'happy-cat');
  });

  test('persistence write failure does not prevent continued coloring', () async {
    final sessionRepository = _MemorySessionRepository()..writeFailures.add('happy-cat');
    final container = _buildContainer(
      pageRepository: _FakeRepository([sampleHappyCatPage]),
      sessionRepository: sessionRepository,
    );
    addTearDown(container.dispose);

    await _waitForReady(container);

    final controller = container.read(coloringControllerProvider.notifier);
    controller.selectColor(Colors.red);
    controller.fillRegion('cat-body');
    await _flushPersistenceQueue();

    var state = container.read(coloringControllerProvider);
    expect(state.regionColors['cat-body'], Colors.red);

    controller.selectColor(Colors.blue);
    controller.fillRegion('cat-tail');
    await _flushPersistenceQueue();

    state = container.read(coloringControllerProvider);
    expect(state.regionColors['cat-tail'], Colors.blue);
  });

  test('loading a new page resets colors and history', () async {
    final sessionRepository = _MemorySessionRepository();
    final container = _buildContainer(
      pageRepository: _FakeRepository([
        sampleHappyCatPage,
        samplePlayfulPuppyPage,
      ]),
      sessionRepository: sessionRepository,
    );
    addTearDown(container.dispose);

    await _waitForReady(container);

    final controller = container.read(coloringControllerProvider.notifier);
    controller.selectColor(Colors.red);
    controller.fillRegion('cat-body');

    expect(container.read(coloringControllerProvider).undoStack.length, 1);

    await controller.loadPageById('playful-puppy');

    final state = container.read(coloringControllerProvider);
    expect(state.page?.id, 'playful-puppy');
    expect(state.undoStack, isEmpty);
    expect(state.redoStack, isEmpty);
    expect(state.regionColors.containsKey('cat-body'), isFalse);
    expect(state.regionColors.containsKey('puppy-body'), isTrue);
  });

  test('undo and redo remain scoped to active page', () async {
    final sessionRepository = _MemorySessionRepository();
    final container = _buildContainer(
      pageRepository: _FakeRepository([
        sampleHappyCatPage,
        samplePlayfulPuppyPage,
      ]),
      sessionRepository: sessionRepository,
    );
    addTearDown(container.dispose);

    await _waitForReady(container);

    final controller = container.read(coloringControllerProvider.notifier);
    controller.selectColor(Colors.green);
    controller.fillRegion('cat-tail');

    await controller.loadPageById('playful-puppy');
    controller.selectColor(Colors.blue);
    controller.fillRegion('puppy-body');
    controller.undo();

    final state = container.read(coloringControllerProvider);
    expect(state.page?.id, 'playful-puppy');
    expect(state.regionColors['puppy-body'], Colors.transparent);
    expect(state.regionColors.containsKey('cat-tail'), isFalse);
  });

  test('resume flow restores colors after ProviderContainer recreation', () async {
    final pageRepository = _FakeRepository([sampleHappyCatPage]);
    final sessionRepository = _MemorySessionRepository();

    final firstContainer = _buildContainer(
      pageRepository: pageRepository,
      sessionRepository: sessionRepository,
    );

    await _waitForReady(firstContainer);
    final firstController = firstContainer.read(coloringControllerProvider.notifier);
    firstController.selectColor(Colors.red);
    firstController.fillRegion('cat-body');
    await _flushPersistenceQueue();
    firstContainer.dispose();

    final secondContainer = _buildContainer(
      pageRepository: pageRepository,
      sessionRepository: sessionRepository,
    );
    addTearDown(secondContainer.dispose);

    final restored = await _waitForReady(secondContainer);
    _expectColorValue(restored.regionColors['cat-body'], Colors.red);
    expect(restored.undoStack, isEmpty);
    expect(restored.redoStack, isEmpty);
  });

  test('multi-page sessions restore independently after recreation', () async {
    final pageRepository = _FakeRepository([
      sampleHappyCatPage,
      samplePlayfulPuppyPage,
    ]);
    final sessionRepository = _MemorySessionRepository();

    final firstContainer = _buildContainer(
      pageRepository: pageRepository,
      sessionRepository: sessionRepository,
    );

    await _waitForReady(firstContainer);
    final firstController = firstContainer.read(coloringControllerProvider.notifier);
    firstController.selectColor(Colors.red);
    firstController.fillRegion('cat-body');
    await firstController.loadPageById('playful-puppy');
    firstController.selectColor(Colors.blue);
    firstController.fillRegion('puppy-body');
    await _flushPersistenceQueue();
    firstContainer.dispose();

    final secondContainer = _buildContainer(
      pageRepository: pageRepository,
      sessionRepository: sessionRepository,
      initialPageId: 'happy-cat',
    );
    addTearDown(secondContainer.dispose);

    final happyCatRestored = await _waitForReady(secondContainer);
    expect(happyCatRestored.page?.id, 'happy-cat');
    _expectColorValue(happyCatRestored.regionColors['cat-body'], Colors.red);

    final secondController = secondContainer.read(coloringControllerProvider.notifier);
    await secondController.loadPageById('playful-puppy');

    final puppyRestored = secondContainer.read(coloringControllerProvider);
    expect(puppyRestored.page?.id, 'playful-puppy');
    _expectColorValue(puppyRestored.regionColors['puppy-body'], Colors.blue);
    expect(puppyRestored.regionColors.containsKey('cat-body'), isFalse);
  });
}
