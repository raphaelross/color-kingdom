import 'package:flutter/material.dart';

import 'svg_coloring_models.dart';

class SvgRegionHitTester {
  const SvgRegionHitTester();

  String? hitTest({
    required Offset localPosition,
    required Size paintSize,
    required Rect viewBox,
    required List<SvgColorableRegion> regions,
  }) {
    final mapped = mapToViewBox(
      localPosition: localPosition,
      paintSize: paintSize,
      viewBox: viewBox,
    );

    if (mapped == null) {
      return null;
    }

    final inZOrder = [...regions]..sort((a, b) => a.drawOrder.compareTo(b.drawOrder));
    for (final region in inZOrder.reversed) {
      if (region.path.contains(mapped)) {
        return region.id;
      }
    }
    return null;
  }

  Offset? mapToViewBox({
    required Offset localPosition,
    required Size paintSize,
    required Rect viewBox,
  }) {
    final scaleX = paintSize.width / viewBox.width;
    final scaleY = paintSize.height / viewBox.height;
    final scale = scaleX < scaleY ? scaleX : scaleY;

    if (scale <= 0) {
      return null;
    }

    final drawWidth = viewBox.width * scale;
    final drawHeight = viewBox.height * scale;

    final offsetX = (paintSize.width - drawWidth) / 2;
    final offsetY = (paintSize.height - drawHeight) / 2;

    final x = localPosition.dx;
    final y = localPosition.dy;

    if (x < offsetX || y < offsetY || x > offsetX + drawWidth || y > offsetY + drawHeight) {
      return null;
    }

    final svgX = (x - offsetX) / scale + viewBox.left;
    final svgY = (y - offsetY) / scale + viewBox.top;
    return Offset(svgX, svgY);
  }
}
