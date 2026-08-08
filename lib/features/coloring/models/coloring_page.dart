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
