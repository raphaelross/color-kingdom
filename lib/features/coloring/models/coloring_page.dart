import 'package:flutter/material.dart';

enum ColoringRendererType { svg, rasterRegion }

@immutable
class RasterRegionMapEntry {
  const RasterRegionMapEntry({
    required this.regionId,
    required this.rgba,
  });

  final String regionId;
  final List<int> rgba;
}

@immutable
class RasterRegionMetadata {
  const RasterRegionMetadata({
    required this.regionMapAssetPath,
    this.regionFillMapAssetPath,
    required this.contentVersion,
    required this.imageWidth,
    required this.imageHeight,
    required this.regionMapEntries,
    this.metadataAssetPath,
  });

  final String regionMapAssetPath;
  final String? regionFillMapAssetPath;
  final String contentVersion;
  final int imageWidth;
  final int imageHeight;
  final List<RasterRegionMapEntry> regionMapEntries;
  final String? metadataAssetPath;
}

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
    this.rasterRegionMetadata,
  });

  final String id;
  final String title;
  final String categoryId;
  final String assetPath;
  final List<ColoringRegion> regions;
  final int sortOrder;
  final String? thumbnailAssetPath;
  final ColoringRendererType rendererType;
  final RasterRegionMetadata? rasterRegionMetadata;
}
