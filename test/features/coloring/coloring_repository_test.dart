import 'package:flutter_test/flutter_test.dart';

import 'package:color_kingdom/features/coloring/repositories/local_coloring_page_repository.dart';

void main() {
  test('repository returns Happy Cat page', () async {
    final repository = LocalColoringPageRepository();

    final pages = await repository.getPages();
    final happyCat = await repository.getPageById('happy-cat');

    expect(pages, isNotEmpty);
    expect(pages.first.id, 'happy-cat');
    expect(happyCat.id, 'happy-cat');
    expect(happyCat.regions.length, greaterThanOrEqualTo(6));
  });
}
