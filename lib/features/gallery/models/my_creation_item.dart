import 'package:flutter/foundation.dart';

@immutable
class MyCreationItem {
  const MyCreationItem({
    required this.pageId,
    required this.pageTitle,
    required this.categoryId,
    required this.categoryTitle,
    required this.previewAssetPath,
    required this.coloredRegionCount,
    required this.totalRegionCount,
    required this.progressRatio,
    required this.progressPercent,
    required this.lastUpdatedAtEpochMs,
  });

  final String pageId;
  final String pageTitle;
  final String categoryId;
  final String categoryTitle;
  final String previewAssetPath;
  final int coloredRegionCount;
  final int totalRegionCount;
  final double progressRatio;
  final int progressPercent;
  final int lastUpdatedAtEpochMs;
}
