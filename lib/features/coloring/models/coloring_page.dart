import 'package:flutter/material.dart';

@immutable
class ColoringRegion {
  const ColoringRegion({
    required this.id,
    required this.name,
    required this.defaultColor,
  });

  final String id;
  final String name;
  final Color defaultColor;
}

@immutable
class ColoringPage {
  const ColoringPage({
    required this.id,
    required this.title,
    required this.category,
    required this.assetPath,
    required this.regions,
  });

  final String id;
  final String title;
  final String category;
  final String assetPath;
  final List<ColoringRegion> regions;
}

@immutable
class ColoringPageState {
  const ColoringPageState({
    required this.page,
    required this.regionColors,
    required this.selectedColor,
    required this.undoStack,
    required this.redoStack,
    required this.isZoomed,
  });

  final ColoringPage page;
  final Map<String, Color> regionColors;
  final Color selectedColor;
  final List<Map<String, Color>> undoStack;
  final List<Map<String, Color>> redoStack;
  final bool isZoomed;

  factory ColoringPageState.initial(ColoringPage page) {
    return ColoringPageState(
      page: page,
      regionColors: {
        for (final region in page.regions) region.id: region.defaultColor,
      },
      selectedColor: const Color(0xFF4FC3F7),
      undoStack: const [],
      redoStack: const [],
      isZoomed: false,
    );
  }

  ColoringPageState copyWith({
    Map<String, Color>? regionColors,
    Color? selectedColor,
    List<Map<String, Color>>? undoStack,
    List<Map<String, Color>>? redoStack,
    bool? isZoomed,
  }) {
    return ColoringPageState(
      page: page,
      regionColors: regionColors ?? this.regionColors,
      selectedColor: selectedColor ?? this.selectedColor,
      undoStack: undoStack ?? this.undoStack,
      redoStack: redoStack ?? this.redoStack,
      isZoomed: isZoomed ?? this.isZoomed,
    );
  }
}
