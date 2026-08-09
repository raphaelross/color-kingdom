import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:color_kingdom/features/coloring/widgets/renderers/svg/svg_coloring_models.dart';
import 'package:color_kingdom/features/coloring/widgets/renderers/svg/svg_coloring_renderer.dart';

void main() {
  test('uncolored region uses default appearance', () {
    final region = SvgColorableRegion(
      id: 'cat-body',
      path: Path()..addRect(const Rect.fromLTWH(0, 0, 10, 10)),
      style: const SvgPaintStyle(fill: Colors.transparent),
      drawOrder: 0,
    );

    final color = SvgColoringRenderer.resolveRegionFillColor(
      region: region,
      regionColors: const {'cat-body': Colors.transparent},
    );

    expect(color, Colors.transparent);
  });

  test('colored region reflects ColoringState', () {
    final region = SvgColorableRegion(
      id: 'cat-body',
      path: Path()..addRect(const Rect.fromLTWH(0, 0, 10, 10)),
      style: const SvgPaintStyle(fill: Colors.transparent),
      drawOrder: 0,
    );

    final color = SvgColoringRenderer.resolveRegionFillColor(
      region: region,
      regionColors: const {'cat-body': Colors.red},
    );

    expect(color, Colors.red);
  });

  test('changing state color updates resolved renderer fill color', () {
    final region = SvgColorableRegion(
      id: 'cat-body',
      path: Path()..addRect(const Rect.fromLTWH(0, 0, 10, 10)),
      style: const SvgPaintStyle(fill: Colors.transparent),
      drawOrder: 0,
    );

    final first = SvgColoringRenderer.resolveRegionFillColor(
      region: region,
      regionColors: const {'cat-body': Colors.blue},
    );

    final second = SvgColoringRenderer.resolveRegionFillColor(
      region: region,
      regionColors: const {'cat-body': Colors.green},
    );

    expect(first, Colors.blue);
    expect(second, Colors.green);
  });
}
