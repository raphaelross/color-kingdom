import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:color_kingdom/features/coloring/models/coloring_page.dart';
import 'package:color_kingdom/features/coloring/widgets/renderers/svg/svg_content_validator.dart';

const ColoringPage _page = ColoringPage(
  id: 'validator-page',
  title: 'Validator Page',
  categoryId: 'test',
  assetPath: 'assets/test.svg',
  sortOrder: 0,
  regions: [
    ColoringRegion(id: 'region-a', name: 'A', defaultColor: Colors.transparent),
  ],
);

void main() {
  final validator = SvgContentValidator();

  test('accepts valid path-only svg content', () {
    const svg = '''
<svg viewBox="0 0 512 512">
  <path id="region-a" data-role="colorable" d="M100 100 L200 100 L200 200 L100 200 Z" fill="transparent"/>
  <path data-role="static" d="M100 100 L200 100 L200 200 L100 200 Z" fill="none" stroke="#000"/>
</svg>
''';

    final report = validator.validate(svgXml: svg, page: _page);

    expect(report.isValid, isTrue);
    expect(report.errors, isEmpty);
    expect(report.colorableRegionCount, 1);
    expect(report.totalPathCount, 2);
  });

  test('flags unsupported geometry and transforms as errors', () {
    const svg = '''
<svg viewBox="0 0 512 512">
  <circle id="c1" cx="100" cy="100" r="20"/>
  <path id="region-a" data-role="colorable" transform="translate(4,4)" d="M100 100 L200 100 L200 200 L100 200 Z"/>
</svg>
''';

    final report = validator.validate(svgXml: svg, page: _page);

    expect(report.isValid, isFalse);
    expect(report.errors.any((issue) => issue.code == 'unsupported-element'), isTrue);
    expect(report.errors.any((issue) => issue.code == 'transform-not-allowed'), isTrue);
  });

  test('flags missing metadata and id issues', () {
    const svg = '''
<svg viewBox="0 0 512 512">
  <path id="" data-role="colorable" d="M100 100 L200 100 L200 200 L100 200 Z"/>
  <path id="region-a" d="M220 100 L320 100 L320 200 L220 200 Z"/>
</svg>
''';

    final report = validator.validate(svgXml: svg, page: _page);

    expect(report.isValid, isFalse);
    expect(report.errors.any((issue) => issue.code == 'empty-colorable-id'), isTrue);
    expect(report.errors.any((issue) => issue.code == 'missing-data-role'), isTrue);
  });
}
