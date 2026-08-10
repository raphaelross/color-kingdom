import '../models/coloring_page.dart';
import '../../categories/models/category.dart';

abstract class ColoringPageRepository {
  Future<List<Category>> getCategories();

  Future<List<ColoringPage>> getPages();

  Future<List<ColoringPage>> getPagesByCategory(String categoryId);

  Future<ColoringPage> getPageById(String id);
}
