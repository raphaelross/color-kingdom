import 'package:color_kingdom/features/categories/category_screen.dart';
import 'package:color_kingdom/app/router/app_router.dart';
import 'package:color_kingdom/features/coloring/models/coloring_session.dart';
import 'package:color_kingdom/features/coloring/providers/coloring_provider.dart';
import 'package:color_kingdom/features/coloring/coloring_screen.dart';
import 'package:color_kingdom/features/coloring/repositories/coloring_session_repository.dart';
import 'package:color_kingdom/features/home/home_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

class _InMemorySessionRepository implements ColoringSessionRepository {
  @override
  Future<List<ColoringSession>> getAllSessions() async => const [];

  @override
  Future<void> clearAllSessions() async {}

  @override
  Future<void> deleteSession(String pageId) async {}

  @override
  Future<ColoringSession?> getSession(String pageId) async => null;

  @override
  Future<void> saveSession(ColoringSession session) async {}
}

void main() {
  Finder _findIconButtonByTooltip(String tooltip) {
    return find.byWidgetPredicate(
      (widget) => widget is IconButton && widget.tooltip == tooltip,
    );
  }

  Future<void> _pressIconButtonByTooltip(
    WidgetTester tester,
    String tooltip,
  ) async {
    final buttonFinder = _findIconButtonByTooltip(tooltip);
    expect(buttonFinder, findsWidgets);
    final button = tester.widget<IconButton>(buttonFinder.last);
    expect(button.onPressed, isNotNull);
    button.onPressed!.call();
    await tester.pump();
  }

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
        overrides: [
          coloringSessionRepositoryProvider.overrideWithValue(
            _InMemorySessionRepository(),
          ),
        ],
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

    await tester.tap(find.text('Animals').hitTestable().first);
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

    await tester.tap(find.widgetWithText(ListTile, 'Happy Cat').first);
    await _pumpUntilFound(tester, find.byType(ColoringScreen));

    expect(find.byType(ColoringScreen), findsOneWidget);
    expect(find.byType(InteractiveViewer), findsOneWidget);
    expect(find.text('Happy Cat'), findsAtLeastNWidgets(1));
    expect(find.byTooltip('Back to Animals'), findsWidgets);
  });

  testWidgets('back control routes to animals catalog from Happy Cat', (
    WidgetTester tester,
  ) async {
    await _pumpToHome(tester);

    await tester.tap(find.text('Animals').first);
    await _pumpUntilFound(tester, find.text('Happy Cat'));

    expect(find.text('Happy Cat'), findsOneWidget);

    await tester.tap(find.widgetWithText(ListTile, 'Happy Cat').first);
    await _pumpUntilFound(tester, find.byType(ColoringScreen));

    expect(find.byTooltip('Back to Animals'), findsWidgets);

    await tester.tap(find.byTooltip('Back to Animals').hitTestable().first);
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

    await tester.tap(find.widgetWithText(ListTile, 'Playful Puppy').first);
    await _pumpUntilFound(tester, find.byType(ColoringScreen));

    expect(find.byType(ColoringScreen), findsOneWidget);
    expect(find.text('Playful Puppy'), findsAtLeastNWidgets(1));
    expect(find.byTooltip('Back to Animals'), findsWidgets);

    await tester.tap(find.byTooltip('Back to Animals').hitTestable().first);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(
      find.descendant(of: find.byType(AppBar), matching: find.text('Animals')),
      findsAtLeastNWidgets(1),
    );
    expect(find.text('Happy Cat'), findsAtLeastNWidgets(1));
    expect(find.text('Playful Puppy'), findsAtLeastNWidgets(1));
  });

  testWidgets('Animals category shows Back and Home controls and both go Home', (
    WidgetTester tester,
  ) async {
    await _pumpToHome(tester);

    await tester.tap(find.text('Animals').first);
    await _pumpUntilFound(tester, find.text('Happy Cat'));

    expect(_findIconButtonByTooltip('Back'), findsWidgets);
    expect(_findIconButtonByTooltip('Home'), findsWidgets);

    await _pressIconButtonByTooltip(tester, 'Back');
    await _pumpUntilFound(tester, find.text('Choose an Adventure'));

    await tester.tap(find.text('Animals').first);
    await _pumpUntilFound(tester, find.text('Happy Cat'));

    await _pressIconButtonByTooltip(tester, 'Home');
    await _pumpUntilFound(tester, find.text('Choose an Adventure'));
  });

  testWidgets('Coloring opened from category shows Home control that returns Home', (
    WidgetTester tester,
  ) async {
    await _pumpToHome(tester);

    await tester.tap(find.text('Animals').first);
    await _pumpUntilFound(tester, find.text('Happy Cat'));

    await tester.tap(find.widgetWithText(ListTile, 'Happy Cat').first);
    await _pumpUntilFound(tester, find.byType(ColoringScreen));

    expect(_findIconButtonByTooltip('Home'), findsWidgets);

    await _pressIconButtonByTooltip(tester, 'Home');
    await _pumpUntilFound(tester, find.text('Choose an Adventure'));
  });
}
