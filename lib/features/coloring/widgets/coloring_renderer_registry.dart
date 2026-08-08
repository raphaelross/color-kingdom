import '../models/coloring_page.dart';
import 'coloring_renderer.dart';
import 'renderers/happy_cat_renderer.dart';

class ColoringRendererRegistry {
  ColoringRendererRegistry._();

  static const ColoringRenderer _happyCatRenderer = HappyCatRenderer();

  static ColoringRenderer resolve(ColoringPage page) {
    switch (page.id) {
      case 'happy-cat':
        return _happyCatRenderer;
      default:
        return _happyCatRenderer;
    }
  }
}
