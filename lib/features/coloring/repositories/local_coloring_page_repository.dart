import '../../categories/data/local_categories.dart';
import '../../categories/models/category.dart';
import '../data/sample_coloring_pages.dart';
import '../models/coloring_page.dart';
import 'coloring_page_repository.dart';

class LocalColoringPageRepository implements ColoringPageRepository {
  static final List<ColoringPage> _validatedPages = _validatePages();
  static final List<ColoringPage> _visiblePages = _validatedPages
      .where((page) => page.id != 'lovely-kitten')
      .toList(growable: false);

  static List<ColoringPage> _validatePages() {
    final categoryIds = localCategories
        .map((category) => category.categoryId)
        .toSet();
    final seenPageIds = <String>{};

    for (final page in sampleColoringPages) {
      if (!seenPageIds.add(page.id)) {
        throw StateError('Duplicate coloring page id: ${page.id}');
      }
      if (!categoryIds.contains(page.categoryId)) {
        throw StateError(
          'Unknown category id for page ${page.id}: ${page.categoryId}',
        );
      }
      if (page.assetPath.trim().isEmpty) {
        throw StateError('Missing asset path for page: ${page.id}');
      }
      if (page.rendererType == ColoringRendererType.rasterRegion &&
          page.rasterRegionMetadata == null) {
        throw StateError('Missing raster metadata for page: ${page.id}');
      }
    }

    return sampleColoringPages;
  }

  @override
  Future<List<Category>> getCategories() async {
    final sorted = [...localCategories]
      ..sort((a, b) => a.sortOrder.compareTo(b.sortOrder));
    return sorted;
  }

  @override
  Future<List<ColoringPage>> getPages() async {
    final sorted = [..._visiblePages]
      ..sort((a, b) => a.sortOrder.compareTo(b.sortOrder));
    return sorted;
  }

  @override
  Future<List<ColoringPage>> getPagesByCategory(String categoryId) async {
    final normalized = categoryId.toLowerCase();
    final pages =
        _visiblePages
            .where((page) => page.categoryId.toLowerCase() == normalized)
            .toList(growable: false)
          ..sort((a, b) => a.sortOrder.compareTo(b.sortOrder));
    return pages;
  }

  @override
  Future<ColoringPage> getPageById(String id) async {
    return _validatedPages.firstWhere(
      (page) => page.id == id,
      orElse: () => throw StateError('Coloring page not found: $id'),
    );
  }
}
