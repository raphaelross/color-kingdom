import 'package:flutter/material.dart';

enum ColoringRendererType { svg }

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
    required this.categoryId,
    required this.assetPath,
    required this.regions,
    required this.sortOrder,
    this.thumbnailAssetPath,
    this.rendererType = ColoringRendererType.svg,
  });

  final String id;
  final String title;
  final String categoryId;
  final String assetPath;
  final List<ColoringRegion> regions;
  final int sortOrder;
  final String? thumbnailAssetPath;
  final ColoringRendererType rendererType;
}
