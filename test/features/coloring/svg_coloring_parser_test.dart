import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:color_kingdom/features/coloring/models/coloring_page.dart';
import 'package:color_kingdom/features/coloring/widgets/renderers/svg/svg_coloring_parser.dart';

const ColoringPage _page = ColoringPage(
  id: 'page',
  title: 'Page',
  categoryId: 'test',
  assetPath: 'assets/page.svg',
  sortOrder: 0,
  regions: [
    ColoringRegion(id: 'a', name: 'A', defaultColor: Colors.transparent),
    ColoringRegion(id: 'b', name: 'B', defaultColor: Colors.transparent),
  ],
);

void main() {
  final parser = SvgColoringParser();

  test('valid SVG loads and discovers colorable regions', () {
    const svg = '''
<svg viewBox="0 0 100 100">
  <path id="a" data-role="colorable" d="M0 0 L40 0 L40 40 L0 40 Z" fill="transparent"/>
  <path id="b" data-role="colorable" d="M50 0 L90 0 L90 40 L50 40 Z" fill="transparent"/>
  <path data-role="static" d="M0 50 L90 50" stroke="#000" fill="none"/>
</svg>
''';

    final result = parser.parseAndValidate(svgXml: svg, page: _page);

    expect(result.isValid, isTrue);
    expect(result.asset, isNotNull);
    expect(result.asset!.colorableRegions.length, 2);
    expect(result.asset!.colorableById.keys, containsAll(['a', 'b']));
  });

  test('duplicate region ids are detected', () {
    const svg = '''
<svg viewBox="0 0 100 100">
  <path id="a" data-role="colorable" d="M0 0 L40 0 L40 40 L0 40 Z"/>
  <path id="a" data-role="colorable" d="M50 0 L90 0 L90 40 L50 40 Z"/>
</svg>
''';

    final result = parser.parseAndValidate(svgXml: svg, page: _page);

    expect(result.isValid, isFalse);
    expect(result.validation.duplicateSvgRegionIds, contains('a'));
  });

  test('missing model regions and unexpected SVG regions are detected', () {
    const svg = '''
<svg viewBox="0 0 100 100">
  <path id="a" data-role="colorable" d="M0 0 L40 0 L40 40 L0 40 Z"/>
  <path id="x" data-role="colorable" d="M50 0 L90 0 L90 40 L50 40 Z"/>
</svg>
''';

    final result = parser.parseAndValidate(svgXml: svg, page: _page);

    expect(result.isValid, isFalse);
    expect(result.validation.missingModelRegionIds, contains('b'));
    expect(result.validation.unexpectedSvgRegionIds, contains('x'));
  });

  test('static regions are not treated as colorable', () {
    const svg = '''
<svg viewBox="0 0 100 100">
  <path id="a" data-role="colorable" d="M0 0 L40 0 L40 40 L0 40 Z"/>
  <path id="outline" data-role="static" d="M0 50 L90 50" stroke="#000" fill="none"/>
</svg>
''';

    final singleRegionPage = const ColoringPage(
      id: 'page',
      title: 'Page',
      categoryId: 'test',
      assetPath: 'assets/page.svg',
      sortOrder: 0,
      regions: [
        ColoringRegion(id: 'a', name: 'A', defaultColor: Colors.transparent),
      ],
    );

    final result = parser.parseAndValidate(svgXml: svg, page: singleRegionPage);

    expect(result.isValid, isTrue);
    expect(result.asset!.colorableRegions.map((e) => e.id), ['a']);
  });
}
