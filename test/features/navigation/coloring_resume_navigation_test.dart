import 'package:color_kingdom/app/router/app_router.dart';
import 'package:color_kingdom/features/categories/category_screen.dart';
import 'package:color_kingdom/features/coloring/coloring_screen.dart';
import 'package:color_kingdom/features/coloring/models/coloring_session.dart';
import 'package:color_kingdom/features/coloring/providers/coloring_provider.dart';
import 'package:color_kingdom/features/coloring/repositories/coloring_session_repository.dart';
import 'package:color_kingdom/features/home/home_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

class _MemorySessionRepository implements ColoringSessionRepository {
  final Map<String, ColoringSession> _sessions = <String, ColoringSession>{};

  @override
  Future<ColoringSession?> getSession(String pageId) async => _sessions[pageId];

  @override
  Future<void> saveSession(ColoringSession session) async {
    _sessions[session.pageId] = session;
  }

  @override
  Future<void> deleteSession(String pageId) async {
    _sessions.remove(pageId);
  }

  @override
  Future<void> clearAllSessions() async {
    _sessions.clear();
  }
}

void main() {
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

  Future<void> pumpApp(
    WidgetTester tester,
    ColoringSessionRepository sessionRepository,
  ) async {
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
          builder: (_, state) {
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
          coloringSessionRepositoryProvider.overrideWithValue(sessionRepository),
        ],
        child: MaterialApp.router(routerConfig: router),
      ),
    );

    await pumpUntilFound(tester, find.text('Choose an Adventure'));
  }

  testWidgets('Animals -> Happy Cat resume flow restores saved colors', (
    WidgetTester tester,
  ) async {
    final sessionRepository = _MemorySessionRepository();

    await pumpApp(tester, sessionRepository);

    await tester.tap(find.text('Animals').first);
    await pumpUntilFound(tester, find.text('Happy Cat'));

    await tester.tap(find.widgetWithText(ListTile, 'Happy Cat').first);
    await pumpUntilFound(tester, find.byType(ColoringScreen));
    await pumpUntilFound(tester, find.text('Back to Animals'));

    final firstColoringContainer = ProviderScope.containerOf(
      tester.element(find.byType(ColoringScreen)),
    );
    final firstController = firstColoringContainer.read(
      coloringControllerProvider.notifier,
    );
    firstController.selectColor(Colors.red);
    firstController.fillRegion('cat-body');

    await tester.pump(const Duration(milliseconds: 50));
    await tester.pump(const Duration(milliseconds: 50));

    await tester.tap(find.byTooltip('Back to Animals'));
    await tester.pump(const Duration(milliseconds: 200));

    await pumpUntilFound(tester, find.text('Happy Cat'));

    await tester.tap(find.widgetWithText(ListTile, 'Happy Cat').first);
    await pumpUntilFound(tester, find.byType(ColoringScreen));

    final secondColoringContainer = ProviderScope.containerOf(
      tester.element(find.byType(ColoringScreen)),
    );
    final restoredState = secondColoringContainer.read(coloringControllerProvider);

    expect(
      restoredState.regionColors['cat-body']?.toARGB32(),
      Colors.red.toARGB32(),
    );
  });
}
