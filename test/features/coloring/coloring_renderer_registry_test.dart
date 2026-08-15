import 'package:flutter_test/flutter_test.dart';

import 'package:color_kingdom/features/coloring/data/sample_coloring_pages.dart';
import 'package:color_kingdom/features/coloring/models/coloring_page.dart';
import 'package:color_kingdom/features/coloring/widgets/coloring_renderer_registry.dart';
import 'package:color_kingdom/features/coloring/widgets/renderers/raster_region/raster_region_coloring_renderer.dart';
import 'package:color_kingdom/features/coloring/widgets/renderers/svg/svg_coloring_renderer.dart';

void main() {
  test('svg pages resolve to SvgColoringRenderer', () {
    for (final page in sampleColoringPages) {
      if (page.rendererType == ColoringRendererType.rasterRegion) {
        continue;
      }
      final renderer = ColoringRendererRegistry.resolve(page);
      expect(renderer, isA<SvgColoringRenderer>());
    }
  });

  test('raster pages resolve to RasterRegionColoringRenderer', () {
    final rasterPages = sampleColoringPages
        .where((page) => page.rendererType == ColoringRendererType.rasterRegion)
        .toList(growable: false);

    expect(rasterPages, isNotEmpty);
    for (final rasterPage in rasterPages) {
      final renderer = ColoringRendererRegistry.resolve(rasterPage);
      expect(renderer, isA<RasterRegionColoringRenderer>());
    }
  });

  test('renderer mapping does not rely on page id special-cases', () {
    final pageIds = sampleColoringPages.map((page) => page.id).toSet();
    expect(pageIds.contains('happy-cat'), isTrue);
    expect(pageIds.contains('playful-puppy'), isTrue);
    expect(pageIds.contains('friendly-lion'), isTrue);
    expect(pageIds.contains('cute-elephant'), isTrue);
    expect(pageIds.contains('cheerful-baby-panda'), isTrue);
    expect(pageIds.contains('lovely-kitten-raster-poc'), isTrue);

    for (final page in sampleColoringPages) {
      final renderer = ColoringRendererRegistry.resolve(page);
      if (page.rendererType == ColoringRendererType.rasterRegion) {
        expect(renderer.id, 'raster-region-coloring-renderer');
      } else {
        expect(renderer.id, 'svg-coloring-renderer');
      }
    }
  });
}
