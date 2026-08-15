import 'package:flutter_test/flutter_test.dart';

import 'package:color_kingdom/features/coloring/repositories/local_coloring_page_repository.dart';

void main() {
  test('repository returns categories with stable ids and ordering', () async {
    final repository = LocalColoringPageRepository();
    final categories = await repository.getCategories();

    expect(categories, isNotEmpty);
    expect(categories.map((category) => category.categoryId), [
      'animals',
      'dinosaurs',
      'space',
      'vehicles',
      'unicorns',
      'holidays',
    ]);
  });

  test(
    'repository returns multiple pages with deterministic ordering',
    () async {
      final repository = LocalColoringPageRepository();

      final pages = await repository.getPages();

      expect(pages.length, greaterThanOrEqualTo(4));
      expect(pages.map((page) => page.id).toList(), [
        'happy-cat',
        'playful-puppy',
        'friendly-lion',
        'cute-elephant',
        'lovely-kitten',
        'cheerful-baby-panda',
        'lovely-kitten-raster-poc',
      ]);
    },
  );

  test('getPagesByCategory returns only matching pages', () async {
    final repository = LocalColoringPageRepository();

    final animals = await repository.getPagesByCategory('animals');

    expect(animals, isNotEmpty);
    expect(animals.every((page) => page.categoryId == 'animals'), isTrue);
  });

  test('getPagesByCategory returns empty list for unknown category', () async {
    final repository = LocalColoringPageRepository();

    final unknown = await repository.getPagesByCategory('unknown');

    expect(unknown, isEmpty);
  });

  test('getPageById returns expected page and unknown page throws', () async {
    final repository = LocalColoringPageRepository();

    final happyCat = await repository.getPageById('happy-cat');
    final puppy = await repository.getPageById('playful-puppy');

    expect(happyCat.id, 'happy-cat');
    expect(puppy.id, 'playful-puppy');
    expect(() => repository.getPageById('missing-page'), throwsStateError);
  });
}
