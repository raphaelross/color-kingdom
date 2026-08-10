import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:color_kingdom/features/coloring/data/sample_coloring_pages.dart';
import 'package:color_kingdom/features/coloring/widgets/renderers/svg/svg_coloring_parser.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('every sample SVG page validates against its model region ids', () async {
    final parser = SvgColoringParser();

    for (final page in sampleColoringPages) {
      final svg = await rootBundle.loadString(page.assetPath);
      final result = parser.parseAndValidate(svgXml: svg, page: page);

      expect(result.isValid, isTrue, reason: 'Failed for page: ${page.id}');
      expect(result.validation.missingModelRegionIds, isEmpty,
          reason: 'Missing model regions for page: ${page.id}');
      expect(result.validation.unexpectedSvgRegionIds, isEmpty,
          reason: 'Unexpected svg regions for page: ${page.id}');
      expect(result.validation.duplicateSvgRegionIds, isEmpty,
          reason: 'Duplicate svg region ids for page: ${page.id}');
    }
  });
}
