import '../models/coloring_page.dart';

abstract class ColoringPageRepository {
  Future<List<ColoringPage>> getPages();

  Future<ColoringPage> getPageById(String id);
}
