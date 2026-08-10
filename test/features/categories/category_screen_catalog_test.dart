import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:color_kingdom/features/categories/category_screen.dart';
import 'package:color_kingdom/features/categories/models/category.dart';
import 'package:color_kingdom/features/coloring/models/coloring_page.dart';
import 'package:color_kingdom/features/coloring/providers/coloring_provider.dart';
import 'package:color_kingdom/features/coloring/repositories/coloring_page_repository.dart';

class _CatalogRepository implements ColoringPageRepository {
  _CatalogRepository({required this.pages, this.throwOnCategoryLookup = false});

  final List<ColoringPage> pages;
  final bool throwOnCategoryLookup;

  @override
  Future<List<Category>> getCategories() async {
    return const [Category(categoryId: 'animals', title: 'Animals', sortOrder: 0)];
  }

  @override
  Future<ColoringPage> getPageById(String id) async {
    return pages.firstWhere((page) => page.id == id);
  }

  @override
  Future<List<ColoringPage>> getPages() async => pages;

  @override
  Future<List<ColoringPage>> getPagesByCategory(String categoryId) async {
    if (throwOnCategoryLookup) {
      throw StateError('Catalog lookup failed');
    }

    return pages.where((page) => page.categoryId == categoryId).toList();
  }
}

const _animalsPages = [
  ColoringPage(
    id: 'happy-cat',
    title: 'Happy Cat',
    categoryId: 'animals',
    assetPath: 'assets/coloring_pages/animals/happy_cat.svg',
    sortOrder: 0,
    regions: [
      ColoringRegion(id: 'cat-body', name: 'Body', defaultColor: Colors.transparent),
    ],
  ),
  ColoringPage(
    id: 'playful-puppy',
    title: 'Playful Puppy',
    categoryId: 'animals',
    assetPath: 'assets/coloring_pages/animals/playful_puppy.svg',
    sortOrder: 1,
    regions: [
      ColoringRegion(id: 'puppy-body', name: 'Body', defaultColor: Colors.transparent),
    ],
  ),
];

Widget _buildSubject(ColoringPageRepository repository, {String categoryId = 'animals'}) {
  return ProviderScope(
    overrides: [coloringPageRepositoryProvider.overrideWithValue(repository)],
    child: MaterialApp(home: CategoryScreen(categoryId: categoryId)),
  );
}

void main() {
  testWidgets('category catalog displays multiple page cards', (tester) async {
    await tester.pumpWidget(_buildSubject(_CatalogRepository(pages: _animalsPages)));
    await tester.pumpAndSettle();

    expect(find.text('Happy Cat'), findsOneWidget);
    expect(find.text('Playful Puppy'), findsOneWidget);
  });

  testWidgets('empty category behavior is shown', (tester) async {
    await tester.pumpWidget(
      _buildSubject(_CatalogRepository(pages: _animalsPages), categoryId: 'space'),
    );
    await tester.pumpAndSettle();

    expect(find.text('Space category is ready for content.'), findsOneWidget);
  });

  testWidgets('repository error behavior is shown', (tester) async {
    await tester.pumpWidget(
      _buildSubject(
        _CatalogRepository(
          pages: _animalsPages,
          throwOnCategoryLookup: true,
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.textContaining('Failed to load category pages'), findsOneWidget);
  });
}
