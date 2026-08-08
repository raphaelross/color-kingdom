import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:color_kingdom/features/coloring/data/sample_coloring_pages.dart';
import 'package:color_kingdom/features/coloring/models/coloring_page.dart';
import 'package:color_kingdom/features/coloring/models/coloring_state.dart';
import 'package:color_kingdom/features/coloring/providers/coloring_provider.dart';
import 'package:color_kingdom/features/coloring/repositories/coloring_page_repository.dart';

class _FakeRepository implements ColoringPageRepository {
  _FakeRepository(this.pages);

  final List<ColoringPage> pages;

  @override
  Future<List<ColoringPage>> getPages() async => pages;

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
  Future<ColoringPage> getPageById(String id) async => _completer.future;
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

void main() {
  test('provider starts loading then loads Happy Cat', () async {
    final container = ProviderContainer();
    addTearDown(container.dispose);

    final initial = container.read(coloringControllerProvider);
    expect(initial.status, ColoringLoadStatus.loading);

    final ready = await _waitForReady(container);
    expect(ready.status, ColoringLoadStatus.ready);
    expect(ready.page?.id, 'happy-cat');
  });

  test('loading state transitions to ready with delayed repository', () async {
    final repository = _DelayedRepository();
    final container = ProviderContainer(
      overrides: [
        coloringPageRepositoryProvider.overrideWithValue(repository),
      ],
    );
    addTearDown(container.dispose);

    expect(container.read(coloringControllerProvider).status, ColoringLoadStatus.loading);

    repository.complete(sampleHappyCatPage);

    final ready = await _waitForReady(container);
    expect(ready.status, ColoringLoadStatus.ready);
    expect(ready.page?.id, 'happy-cat');
  });

  test('region coloring creates one action entry', () async {
    final container = ProviderContainer(
      overrides: [
        coloringPageRepositoryProvider.overrideWithValue(
          _FakeRepository([sampleHappyCatPage]),
        ),
      ],
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
    final container = ProviderContainer(
      overrides: [
        coloringPageRepositoryProvider.overrideWithValue(
          _FakeRepository([sampleHappyCatPage]),
        ),
      ],
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
    final container = ProviderContainer(
      overrides: [
        coloringPageRepositoryProvider.overrideWithValue(
          _FakeRepository([sampleHappyCatPage]),
        ),
      ],
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
    final container = ProviderContainer(
      overrides: [
        coloringPageRepositoryProvider.overrideWithValue(
          _FakeRepository([sampleHappyCatPage]),
        ),
      ],
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
    final container = ProviderContainer(
      overrides: [
        coloringPageRepositoryProvider.overrideWithValue(
          _FakeRepository([sampleHappyCatPage]),
        ),
      ],
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
}
