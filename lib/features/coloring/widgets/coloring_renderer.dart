import 'package:flutter/material.dart';

import '../models/coloring_page.dart';

class ColoringRendererValidation {
  const ColoringRendererValidation({
    required this.isValid,
    required this.missingRegionIds,
  });

  final bool isValid;
  final List<String> missingRegionIds;
}

abstract class ColoringRenderer {
  const ColoringRenderer();

  String get id;

  List<String> get requiredRegionIds;

  Widget build({
    required BuildContext context,
    required ColoringPage page,
    required Map<String, Color> regionColors,
    required Color selectedColor,
    required ValueChanged<String> onRegionTap,
  });

  ColoringRendererValidation validate(ColoringPage page) {
    final pageRegionIds = page.regions.map((region) => region.id).toSet();
    final missing = requiredRegionIds
        .where((regionId) => !pageRegionIds.contains(regionId))
        .toList(growable: false);

    return ColoringRendererValidation(
      isValid: missing.isEmpty,
      missingRegionIds: missing,
    );
  }
}
