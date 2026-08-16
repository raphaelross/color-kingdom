import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import 'package:color_kingdom/app/router/app_router.dart';
import 'package:color_kingdom/features/categories/category_screen.dart';
import 'package:color_kingdom/features/coloring/coloring_screen.dart';
import 'package:color_kingdom/features/coloring/models/coloring_session.dart';
import 'package:color_kingdom/features/coloring/providers/coloring_provider.dart';
import 'package:color_kingdom/features/coloring/repositories/coloring_session_repository.dart';
import 'package:color_kingdom/features/gallery/gallery_screen.dart';
import 'package:color_kingdom/features/gallery/providers/my_creations_provider.dart';
import 'package:color_kingdom/features/home/home_screen.dart';

class _MemorySessionRepository implements ColoringSessionRepository {
  final Map<String, ColoringSession> _sessions = <String, ColoringSession>{};

  @override
  Future<void> clearAllSessions() async {
    _sessions.clear();
  }

  @override
  Future<void> deleteSession(String pageId) async {
    _sessions.remove(pageId);
  }

  @override
  Future<List<ColoringSession>> getAllSessions() async {
    final sessions = _sessions.values.toList();
    sessions.sort((a, b) {
      final timestampOrder = b.lastUpdatedAtEpochMs.compareTo(
        a.lastUpdatedAtEpochMs,
      );
      if (timestampOrder != 0) {
        return timestampOrder;
      }

      return a.pageId.compareTo(b.pageId);
    });
    return sessions;
  }

  @override
  Future<ColoringSession?> getSession(String pageId) async {
    return _sessions[pageId];
  }

  @override
  Future<void> saveSession(ColoringSession session) async {
    _sessions[session.pageId] = session;
  }

  void seed(ColoringSession session) {
    _sessions[session.pageId] = session;
  }
}

Future<void> pumpUntilFound(
  WidgetTester tester,
  Finder finder, {
  int maxPumps = 40,
}) async {
  for (var i = 0; i < maxPumps; i++) {
    await tester.pump(const Duration(milliseconds: 100));
    if (finder.evaluate().isNotEmpty) {
      return;
    }
  }

  fail('Timed out waiting for widget: $finder');
}

Future<void> waitForColoringReady(WidgetTester tester) async {
  for (var i = 0; i < 40; i++) {
    final container = ProviderScope.containerOf(
      tester.element(find.byType(ColoringScreen)),
    );
    final state = container.read(coloringControllerProvider);
    if (state.isReady) {
      return;
    }
    await tester.pump(const Duration(milliseconds: 100));
  }

  fail('Timed out waiting for coloring state to be ready.');
}

Future<GoRouter> _pumpApp(
  WidgetTester tester,
  ColoringSessionRepository sessionRepository, {
  String initialLocation = '/home',
}) async {
  final router = GoRouter(
    initialLocation: initialLocation,
    routes: [
      GoRoute(
        path: '/home',
        name: AppRouteName.home,
        builder: (context, state) => const HomeScreen(),
      ),
      GoRoute(
        path: '/category/:categoryId',
        name: AppRouteName.category,
        builder: (context, state) =>
            CategoryScreen(categoryId: state.pathParameters['categoryId']!),
      ),
      GoRoute(
        path: '/gallery',
        name: AppRouteName.gallery,
        builder: (context, state) => const GalleryScreen(),
      ),
      GoRoute(
        path: '/coloring/:pageId',
        name: AppRouteName.coloring,
        builder: (context, state) {
          final pageId = state.pathParameters['pageId']!;
          final source = state.uri.queryParameters[ColoringRouteQuery.source];
          final sourceCategoryId =
              state.uri.queryParameters[ColoringRouteQuery.sourceCategoryId];
          return ProviderScope(
            overrides: [
              coloringInitialPageIdProvider.overrideWithValue(pageId),
            ],
            child: ColoringScreen(
              navigationSource: source,
              sourceCategoryId: sourceCategoryId,
            ),
          );
        },
      ),
    ],
  );

  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        coloringSessionRepositoryProvider.overrideWithValue(sessionRepository),
      ],
      child: MaterialApp.router(routerConfig: router),
    ),
  );

  return router;
}

void main() {
  Finder findIconButtonByTooltip(String tooltip) {
    return find.byWidgetPredicate(
      (widget) => widget is IconButton && widget.tooltip == tooltip,
    );
  }

  Future<void> pressIconButtonByTooltip(
    WidgetTester tester,
    String tooltip,
  ) async {
    final buttonFinder = findIconButtonByTooltip(tooltip);
    expect(buttonFinder, findsWidgets);
    final button = tester.widget<IconButton>(buttonFinder.last);
    expect(button.onPressed, isNotNull);
    button.onPressed!.call();
    await tester.pump();
  }

  testWidgets('Home route exposes My Creations destination', (tester) async {
    final router = await _pumpApp(
      tester,
      _MemorySessionRepository(),
      initialLocation: '/home',
    );
    await pumpUntilFound(tester, find.text('Choose an Adventure'));

    router.goNamed(AppRouteName.gallery);
    await tester.pumpAndSettle();

    expect(
      find.text('No creations yet! Pick a picture and start coloring.'),
      findsOneWidget,
    );
  });

  testWidgets('My Creations shows Back and Home controls and both go Home', (
    tester,
  ) async {
    final router = await _pumpApp(
      tester,
      _MemorySessionRepository(),
      initialLocation: '/gallery',
    );
    await pumpUntilFound(
      tester,
      find.text('No creations yet! Pick a picture and start coloring.'),
    );

    expect(findIconButtonByTooltip('Back'), findsWidgets);
    expect(findIconButtonByTooltip('Home'), findsWidgets);

    await pressIconButtonByTooltip(tester, 'Back');
    await pumpUntilFound(tester, find.text('Choose an Adventure'));

    router.goNamed(AppRouteName.gallery);
    await tester.pumpAndSettle();
    await pumpUntilFound(
      tester,
      find.text('No creations yet! Pick a picture and start coloring.'),
    );

    await pressIconButtonByTooltip(tester, 'Home');
    await pumpUntilFound(tester, find.text('Choose an Adventure'));
  });

  testWidgets('My Creations to Happy Cat and back returns to My Creations', (
    tester,
  ) async {
    final sessionRepository = _MemorySessionRepository()
      ..seed(
        const ColoringSession(
          pageId: 'happy-cat',
          regionColors: {'cat-body': 0xFFFF0000},
          schemaVersion: ColoringSession.currentSchemaVersion,
          lastUpdatedAtEpochMs: 100,
        ),
      );

    await _pumpApp(tester, sessionRepository, initialLocation: '/gallery');
    await pumpUntilFound(tester, find.text('Happy Cat'));

    await tester.tap(find.text('Happy Cat'));
    await pumpUntilFound(tester, find.byType(ColoringScreen));
    await pumpUntilFound(tester, find.byTooltip('Back to My Creations'));

    await tester.tap(find.byTooltip('Back to My Creations'));
    await tester.pumpAndSettle();

    expect(find.text('My Creations'), findsAtLeastNWidgets(1));
    final galleryContainer = ProviderScope.containerOf(
      tester.element(find.byType(GalleryScreen)),
    );
    final items = await galleryContainer.read(myCreationsProvider.future);

    expect(items.length, 1);
    expect(items.single.pageId, 'happy-cat');
  });

  testWidgets('Animals to Happy Cat and back returns to Animals', (
    tester,
  ) async {
    await _pumpApp(tester, _MemorySessionRepository());
    await pumpUntilFound(tester, find.text('Choose an Adventure'));

    await tester.tap(find.text('Animals').first);
    await pumpUntilFound(tester, find.text('Happy Cat'));

    await tester.tap(find.widgetWithText(ListTile, 'Happy Cat').first);
    await pumpUntilFound(tester, find.byType(ColoringScreen));
    await pumpUntilFound(tester, find.byTooltip('Back to Animals'));

    await tester.tap(find.byTooltip('Back to Animals'));
    await tester.pumpAndSettle();

    expect(
      find.descendant(of: find.byType(AppBar), matching: find.text('Animals')),
      findsOneWidget,
    );
  });

  testWidgets('direct coloring route back uses safe category fallback', (
    tester,
  ) async {
    await _pumpApp(
      tester,
      _MemorySessionRepository(),
      initialLocation: '/coloring/happy-cat',
    );
    await pumpUntilFound(tester, find.byType(ColoringScreen));
    await pumpUntilFound(tester, find.byTooltip('Back to Animals'));

    await tester.tap(find.byTooltip('Back to Animals'));
    await tester.pumpAndSettle();

    expect(
      find.descendant(of: find.byType(AppBar), matching: find.text('Animals')),
      findsOneWidget,
    );
  });

  testWidgets('direct coloring route Home control returns Home', (
    tester,
  ) async {
    await _pumpApp(
      tester,
      _MemorySessionRepository(),
      initialLocation: '/coloring/happy-cat',
    );
    await pumpUntilFound(tester, find.byType(ColoringScreen));

    expect(findIconButtonByTooltip('Home'), findsWidgets);

    await pressIconButtonByTooltip(tester, 'Home');
    await pumpUntilFound(tester, find.text('Choose an Adventure'));
  });

  testWidgets('My Creations refreshes progress after returning from coloring', (
    tester,
  ) async {
    final sessionRepository = _MemorySessionRepository()
      ..seed(
        const ColoringSession(
          pageId: 'happy-cat',
          regionColors: {'cat-body': 0xFFFF0000},
          schemaVersion: ColoringSession.currentSchemaVersion,
          lastUpdatedAtEpochMs: 100,
        ),
      );

    await _pumpApp(tester, sessionRepository, initialLocation: '/gallery');
    await pumpUntilFound(tester, find.text('10% colored'));

    await tester.tap(find.text('Happy Cat'));
    await pumpUntilFound(tester, find.byType(ColoringScreen));
    await waitForColoringReady(tester);

    final container = ProviderScope.containerOf(
      tester.element(find.byType(ColoringScreen)),
    );
    final controller = container.read(coloringControllerProvider.notifier);
    controller.selectColor(Colors.blue);
    controller.fillRegion('cat-head');

    await tester.pump(const Duration(milliseconds: 50));
    await tester.pump(const Duration(milliseconds: 50));

    await tester.tap(find.byTooltip('Back to My Creations'));
    await pumpUntilFound(tester, find.text('My Creations'));

    final galleryContainer = ProviderScope.containerOf(
      tester.element(find.byType(GalleryScreen)),
    );
    final items = await galleryContainer.read(myCreationsProvider.future);

    expect(items.length, 1);
    expect(items.single.progressPercent, 20);
  });

  testWidgets('Coloring from My Creations Home control returns Home', (
    tester,
  ) async {
    final sessionRepository = _MemorySessionRepository()
      ..seed(
        const ColoringSession(
          pageId: 'happy-cat',
          regionColors: {'cat-body': 0xFFFF0000},
          schemaVersion: ColoringSession.currentSchemaVersion,
          lastUpdatedAtEpochMs: 100,
        ),
      );

    await _pumpApp(tester, sessionRepository, initialLocation: '/gallery');
    await pumpUntilFound(tester, find.text('Happy Cat'));

    await tester.tap(find.text('Happy Cat'));
    await pumpUntilFound(tester, find.byType(ColoringScreen));

    expect(findIconButtonByTooltip('Home'), findsWidgets);

    await pressIconButtonByTooltip(tester, 'Home');
    await pumpUntilFound(tester, find.text('Choose an Adventure'));
  });

  testWidgets('clear from coloring removes item from My Creations', (
    tester,
  ) async {
    final sessionRepository = _MemorySessionRepository()
      ..seed(
        const ColoringSession(
          pageId: 'happy-cat',
          regionColors: {'cat-body': 0xFFFF0000},
          schemaVersion: ColoringSession.currentSchemaVersion,
          lastUpdatedAtEpochMs: 100,
        ),
      );

    await _pumpApp(tester, sessionRepository, initialLocation: '/gallery');
    await pumpUntilFound(tester, find.text('Happy Cat'));

    await tester.tap(find.text('Happy Cat'));
    await pumpUntilFound(tester, find.byType(ColoringScreen));
    await waitForColoringReady(tester);

    await tester.tap(find.text('Clear'));
    await tester.pump(const Duration(milliseconds: 100));

    await tester.tap(find.byTooltip('Back to My Creations'));
    await pumpUntilFound(tester, find.text('My Creations'));

    final galleryContainer = ProviderScope.containerOf(
      tester.element(find.byType(GalleryScreen)),
    );
    final items = await galleryContainer.read(myCreationsProvider.future);

    expect(items, isEmpty);
  });
}
