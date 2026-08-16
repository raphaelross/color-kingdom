import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../coloring/models/coloring_page.dart';
import '../../coloring/models/coloring_session.dart';
import '../../coloring/providers/coloring_provider.dart';
import '../models/my_creation_item.dart';

final myCreationsProvider = FutureProvider.autoDispose<List<MyCreationItem>>((
  ref,
) async {
  final sessionRepository = ref.watch(coloringSessionRepositoryProvider);
  final pageRepository = ref.watch(coloringPageRepositoryProvider);

  final sessions = await sessionRepository.getAllSessions();
  if (sessions.isEmpty) {
    return const <MyCreationItem>[];
  }

  final categories = await pageRepository.getCategories();

  final categoryTitleById = <String, String>{
    for (final category in categories) category.categoryId: category.title,
  };

  final items = <MyCreationItem>[];

  for (final session in sessions) {
    ColoringPage page;
    try {
      page = await pageRepository.getPageById(session.pageId);
    } on StateError {
      continue;
    }

    final progress = calculateMyCreationProgress(page: page, session: session);

    if (progress.coloredRegionCount <= 0) {
      continue;
    }

    items.add(
      MyCreationItem(
        pageId: page.id,
        pageTitle: page.title,
        categoryId: page.categoryId,
        categoryTitle:
            categoryTitleById[page.categoryId] ??
            _formatCategoryId(page.categoryId),
        previewAssetPath: page.thumbnailAssetPath ?? page.assetPath,
        coloredRegionCount: progress.coloredRegionCount,
        totalRegionCount: progress.totalRegionCount,
        progressRatio: progress.progressRatio,
        progressPercent: progress.progressPercent,
        lastUpdatedAtEpochMs: session.lastUpdatedAtEpochMs,
      ),
    );
  }

  return items;
});

@immutable
class MyCreationProgress {
  const MyCreationProgress({
    required this.coloredRegionCount,
    required this.totalRegionCount,
  });

  final int coloredRegionCount;
  final int totalRegionCount;

  double get progressRatio {
    if (totalRegionCount <= 0) {
      return 0;
    }

    final ratio = coloredRegionCount / totalRegionCount;
    if (ratio < 0) {
      return 0;
    }
    if (ratio > 1) {
      return 1;
    }

    return ratio;
  }

  int get progressPercent => (progressRatio * 100).round();
}

MyCreationProgress calculateMyCreationProgress({
  required ColoringPage page,
  required ColoringSession session,
}) {
  final totalRegionCount = page.regions.length;
  if (totalRegionCount == 0) {
    return const MyCreationProgress(coloredRegionCount: 0, totalRegionCount: 0);
  }

  var coloredRegionCount = 0;
  for (final region in page.regions) {
    final sessionColorValue = session.regionColors[region.id];
    if (sessionColorValue == null) {
      continue;
    }

    if (sessionColorValue == region.defaultColor.toARGB32()) {
      continue;
    }

    coloredRegionCount += 1;
  }

  return MyCreationProgress(
    coloredRegionCount: coloredRegionCount,
    totalRegionCount: totalRegionCount,
  );
}

String _formatCategoryId(String categoryId) {
  final words = categoryId
      .replaceAll('_', ' ')
      .replaceAll('-', ' ')
      .split(' ')
      .where((word) => word.isNotEmpty)
      .map((word) => word[0].toUpperCase() + word.substring(1).toLowerCase())
      .toList(growable: false);

  if (words.isEmpty) {
    return categoryId;
  }

  return words.join(' ');
}
