import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/sample_coloring_pages.dart';
import '../models/coloring_page.dart';

final availableColoringPagesProvider = Provider<List<ColoringPage>>(
  (ref) => sampleColoringPages,
);

final activeColoringPageProvider = StateProvider<ColoringPage>(
  (ref) => sampleColoringPages.first,
);

final coloringControllerProvider =
    StateNotifierProvider<ColoringController, ColoringPageState>((ref) {
  final page = ref.watch(activeColoringPageProvider);
  return ColoringController(page);
});

class ColoringController extends StateNotifier<ColoringPageState> {
  ColoringController(ColoringPage page) : super(ColoringPageState.initial(page));

  void selectColor(Color color) {
    state = state.copyWith(selectedColor: color);
  }

  void fillRegion(String regionId) {
    final currentColors = Map<String, Color>.from(state.regionColors);
    final nextColors = Map<String, Color>.from(currentColors);
    nextColors[regionId] = state.selectedColor;

    if (_mapsEqual(currentColors, nextColors)) {
      return;
    }

    state = state.copyWith(
      regionColors: nextColors,
      undoStack: [...state.undoStack, currentColors],
      redoStack: const [],
    );
  }

  void undo() {
    if (state.undoStack.isEmpty) {
      return;
    }

    final previous = state.undoStack.last;
    final remainingUndo = [...state.undoStack]..removeLast();
    state = state.copyWith(
      regionColors: previous,
      undoStack: remainingUndo,
      redoStack: [state.regionColors, ...state.redoStack],
    );
  }

  void redo() {
    if (state.redoStack.isEmpty) {
      return;
    }

    final next = state.redoStack.first;
    state = state.copyWith(
      regionColors: next,
      undoStack: [...state.undoStack, state.regionColors],
      redoStack: state.redoStack.sublist(1),
    );
  }

  void clear() {
    state = ColoringPageState.initial(state.page).copyWith(
      selectedColor: state.selectedColor,
    );
  }

  void setPage(ColoringPage page) {
    state = ColoringPageState.initial(page).copyWith(
      selectedColor: state.selectedColor,
    );
  }

  bool _mapsEqual(Map<String, Color> a, Map<String, Color> b) {
    if (identical(a, b)) {
      return true;
    }
    if (a.length != b.length) {
      return false;
    }
    for (final entry in a.entries) {
      if (b[entry.key] != entry.value) {
        return false;
      }
    }
    return true;
  }
}
