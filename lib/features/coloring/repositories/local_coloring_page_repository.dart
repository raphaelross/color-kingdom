import '../data/sample_coloring_pages.dart';
import '../models/coloring_page.dart';
import 'coloring_page_repository.dart';

class LocalColoringPageRepository implements ColoringPageRepository {
  @override
  Future<List<ColoringPage>> getPages() async {
    return sampleColoringPages;
  }

  @override
  Future<ColoringPage> getPageById(String id) async {
    return sampleColoringPages.firstWhere(
      (page) => page.id == id,
      orElse: () => throw StateError('Coloring page not found: $id'),
    );
  }
}
