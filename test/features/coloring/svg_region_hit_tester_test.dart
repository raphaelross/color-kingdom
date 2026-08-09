import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:color_kingdom/features/coloring/widgets/renderers/svg/svg_coloring_models.dart';
import 'package:color_kingdom/features/coloring/widgets/renderers/svg/svg_region_hit_tester.dart';

SvgColorableRegion _region({
  required String id,
  required Path path,
  required int order,
}) {
  return SvgColorableRegion(
    id: id,
    path: path,
    style: const SvgPaintStyle(fill: Colors.transparent),
    drawOrder: order,
  );
}

void main() {
  final tester = const SvgRegionHitTester();

  test('tapping inside region returns correct region id', () {
    final regions = [
      _region(
        id: 'a',
        order: 0,
        path: Path()..addRect(const Rect.fromLTWH(0, 0, 40, 40)),
      ),
    ];

    final id = tester.hitTest(
      localPosition: const Offset(20, 20),
      paintSize: const Size(100, 100),
      viewBox: const Rect.fromLTWH(0, 0, 100, 100),
      regions: regions,
    );

    expect(id, 'a');
  });

  test('tapping outside all regions returns null', () {
    final regions = [
      _region(
        id: 'a',
        order: 0,
        path: Path()..addRect(const Rect.fromLTWH(0, 0, 40, 40)),
      ),
    ];

    final id = tester.hitTest(
      localPosition: const Offset(90, 90),
      paintSize: const Size(100, 100),
      viewBox: const Rect.fromLTWH(0, 0, 100, 100),
      regions: regions,
    );

    expect(id, isNull);
  });

  test('overlapping regions resolve by z-order (top-most wins)', () {
    final bottom = _region(
      id: 'bottom',
      order: 0,
      path: Path()..addRect(const Rect.fromLTWH(0, 0, 60, 60)),
    );

    final top = _region(
      id: 'top',
      order: 1,
      path: Path()..addRect(const Rect.fromLTWH(20, 20, 60, 60)),
    );

    final id = tester.hitTest(
      localPosition: const Offset(30, 30),
      paintSize: const Size(100, 100),
      viewBox: const Rect.fromLTWH(0, 0, 100, 100),
      regions: [bottom, top],
    );

    expect(id, 'top');
  });
}
