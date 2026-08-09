import '../models/coloring_page.dart';
import 'coloring_renderer.dart';
import 'renderers/happy_cat_renderer.dart';
import 'renderers/svg/svg_coloring_renderer.dart';

class ColoringRendererRegistry {
  ColoringRendererRegistry._();

  static const ColoringRenderer _fallbackRenderer = HappyCatRenderer();

  static ColoringRenderer resolve(ColoringPage page) {
    switch (page.id) {
      case 'happy-cat':
        return SvgColoringRenderer();
      default:
        return _fallbackRenderer;
    }
  }
}
