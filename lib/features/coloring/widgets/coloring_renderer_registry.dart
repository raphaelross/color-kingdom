import '../models/coloring_page.dart';
import 'coloring_renderer.dart';
import 'renderers/happy_cat_renderer.dart';
import 'renderers/raster_region/raster_region_coloring_renderer.dart';
import 'renderers/svg/svg_coloring_renderer.dart';

class ColoringRendererRegistry {
  ColoringRendererRegistry._();

  static const ColoringRenderer _fallbackRenderer = HappyCatRenderer();
  static final ColoringRenderer _svgRenderer = SvgColoringRenderer();
  static final ColoringRenderer _rasterRenderer = RasterRegionColoringRenderer();

  static ColoringRenderer resolve(ColoringPage page) {
    if (page.rendererType == ColoringRendererType.svg) {
      return _svgRenderer;
    }

    if (page.rendererType == ColoringRendererType.rasterRegion) {
      return _rasterRenderer;
    }

    return _fallbackRenderer;
  }
}
