import 'package:flutter/material.dart';

import 'coloring_page.dart';

enum ColoringLoadStatus { loading, ready, error }

@immutable
class ColoringHistoryAction {
  const ColoringHistoryAction({
    required this.regionId,
    required this.previousColor,
    required this.nextColor,
  });

  final String regionId;
  final Color previousColor;
  final Color nextColor;
}

@immutable
class ColoringState {
  const ColoringState({
    required this.status,
    required this.page,
    required this.regionColors,
    required this.selectedColor,
    required this.undoStack,
    required this.redoStack,
    required this.errorMessage,
  });

  final ColoringLoadStatus status;
  final ColoringPage? page;
  final Map<String, Color> regionColors;
  final Color selectedColor;
  final List<ColoringHistoryAction> undoStack;
  final List<ColoringHistoryAction> redoStack;
  final String? errorMessage;

  bool get isReady => status == ColoringLoadStatus.ready && page != null;

  factory ColoringState.loading({
    Color selectedColor = const Color(0xFF4FC3F7),
  }) {
    return ColoringState(
      status: ColoringLoadStatus.loading,
      page: null,
      regionColors: const {},
      selectedColor: selectedColor,
      undoStack: const [],
      redoStack: const [],
      errorMessage: null,
    );
  }

  factory ColoringState.ready({
    required ColoringPage page,
    required Map<String, Color> regionColors,
    required Color selectedColor,
    List<ColoringHistoryAction> undoStack = const [],
    List<ColoringHistoryAction> redoStack = const [],
  }) {
    return ColoringState(
      status: ColoringLoadStatus.ready,
      page: page,
      regionColors: regionColors,
      selectedColor: selectedColor,
      undoStack: undoStack,
      redoStack: redoStack,
      errorMessage: null,
    );
  }

  factory ColoringState.error({
    required String message,
    required Color selectedColor,
  }) {
    return ColoringState(
      status: ColoringLoadStatus.error,
      page: null,
      regionColors: const {},
      selectedColor: selectedColor,
      undoStack: const [],
      redoStack: const [],
      errorMessage: message,
    );
  }

  ColoringState copyWith({
    ColoringLoadStatus? status,
    ColoringPage? page,
    Map<String, Color>? regionColors,
    Color? selectedColor,
    List<ColoringHistoryAction>? undoStack,
    List<ColoringHistoryAction>? redoStack,
    String? errorMessage,
  }) {
    return ColoringState(
      status: status ?? this.status,
      page: page ?? this.page,
      regionColors: regionColors ?? this.regionColors,
      selectedColor: selectedColor ?? this.selectedColor,
      undoStack: undoStack ?? this.undoStack,
      redoStack: redoStack ?? this.redoStack,
      errorMessage: errorMessage ?? this.errorMessage,
    );
  }
}
