import 'package:color_kingdom/features/categories/category_screen.dart';
import 'package:color_kingdom/app/router/app_router.dart';
import 'package:color_kingdom/features/coloring/providers/coloring_provider.dart';
import 'package:color_kingdom/features/coloring/coloring_screen.dart';
import 'package:color_kingdom/features/home/home_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

void main() {
  Future<void> _pumpUntilFound(
    WidgetTester tester,
    Finder finder, {
    int maxPumps = 30,
  }) async {
    for (var i = 0; i < maxPumps; i++) {
      await tester.pump(const Duration(milliseconds: 100));
      if (finder.evaluate().isNotEmpty) {
        return;
      }
    }

    fail('Timed out waiting for widget: $finder');
  }

  Future<void> _pumpToHome(WidgetTester tester) async {
    final router = GoRouter(
      initialLocation: '/home',
      routes: [
        GoRoute(
          path: '/home',
          name: AppRouteName.home,
          builder: (_, __) => const HomeScreen(),
        ),
        GoRoute(
          path: '/category/:categoryId',
          name: AppRouteName.category,
          builder: (_, state) => CategoryScreen(
            categoryId: state.pathParameters['categoryId']!,
          ),
        ),
        GoRoute(
          path: '/coloring/:pageId',
          name: AppRouteName.coloring,
          builder: (context, state) {
            final pageId = state.pathParameters['pageId']!;
            return ProviderScope(
              overrides: [
                coloringInitialPageIdProvider.overrideWithValue(pageId),
              ],
              child: const ColoringScreen(),
            );
          },
        ),
      ],
    );

    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp.router(routerConfig: router),
      ),
    );
    await _pumpUntilFound(tester, find.text('Choose an Adventure'));
  }

  testWidgets('HomeScreen navigates to Animals category and shows Happy Cat', (
    WidgetTester tester,
  ) async {
    await _pumpToHome(tester);

    expect(find.text('Choose an Adventure'), findsOneWidget);
    expect(find.text('Animals'), findsAtLeastNWidgets(1));

    await tester.tap(find.text('Animals').first);
    await _pumpUntilFound(tester, find.text('Happy Cat'));

    expect(
      find.descendant(of: find.byType(AppBar), matching: find.text('Animals')),
      findsOneWidget,
    );
    expect(find.text('Happy Cat'), findsOneWidget);
    expect(find.text('Playful Puppy'), findsOneWidget);
    expect(find.text('Friendly Lion'), findsOneWidget);
    expect(find.text('Cute Elephant'), findsOneWidget);
  });

  testWidgets('tapping Happy Cat opens ColoringScreen with Happy Cat page', (
    WidgetTester tester,
  ) async {
    await _pumpToHome(tester);

    await tester.tap(find.text('Animals').first);
    await _pumpUntilFound(tester, find.text('Happy Cat'));

    expect(find.text('Happy Cat'), findsOneWidget);

    await tester.tap(find.text('Happy Cat').first);
    await _pumpUntilFound(tester, find.text('Back to Animals'));

    expect(find.byType(ColoringScreen), findsOneWidget);
    expect(find.byType(InteractiveViewer), findsOneWidget);
    expect(find.text('Happy Cat'), findsAtLeastNWidgets(1));
    expect(find.byIcon(Icons.arrow_back), findsOneWidget);
    expect(find.text('Back to Animals'), findsOneWidget);
  });

  testWidgets('back control routes to animals catalog from Happy Cat', (
    WidgetTester tester,
  ) async {
    await _pumpToHome(tester);

    await tester.tap(find.text('Animals').first);
    await _pumpUntilFound(tester, find.text('Happy Cat'));

    expect(find.text('Happy Cat'), findsOneWidget);

    await tester.tap(find.text('Happy Cat').first);
    await _pumpUntilFound(tester, find.text('Back to Animals'));

    expect(find.text('Back to Animals'), findsOneWidget);

    await tester.tap(find.byTooltip('Back to Animals'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(
      find.descendant(of: find.byType(AppBar), matching: find.text('Animals')),
      findsAtLeastNWidgets(1),
    );
    expect(find.text('Happy Cat'), findsAtLeastNWidgets(1));
    expect(find.text('Playful Puppy'), findsAtLeastNWidgets(1));
  });

  testWidgets('back control is generic for another animals page', (
    WidgetTester tester,
  ) async {
    await _pumpToHome(tester);

    await tester.tap(find.text('Animals').first);
    await _pumpUntilFound(tester, find.text('Playful Puppy'));

    expect(find.text('Playful Puppy'), findsOneWidget);

    await tester.tap(find.text('Playful Puppy').first);
    await _pumpUntilFound(tester, find.text('Back to Animals'));

    expect(find.byType(ColoringScreen), findsOneWidget);
    expect(find.text('Playful Puppy'), findsAtLeastNWidgets(1));
    expect(find.text('Back to Animals'), findsOneWidget);

    await tester.tap(find.byTooltip('Back to Animals'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(
      find.descendant(of: find.byType(AppBar), matching: find.text('Animals')),
      findsAtLeastNWidgets(1),
    );
    expect(find.text('Happy Cat'), findsAtLeastNWidgets(1));
    expect(find.text('Playful Puppy'), findsAtLeastNWidgets(1));
  });
}
