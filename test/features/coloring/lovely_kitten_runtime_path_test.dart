import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import 'package:color_kingdom/app/router/app_router.dart';
import 'package:color_kingdom/features/categories/category_screen.dart';
import 'package:color_kingdom/features/coloring/coloring_screen.dart';
import 'package:color_kingdom/features/coloring/models/coloring_page.dart';
import 'package:color_kingdom/features/coloring/models/coloring_session.dart';
import 'package:color_kingdom/features/coloring/providers/coloring_provider.dart';
import 'package:color_kingdom/features/coloring/repositories/coloring_session_repository.dart';
import 'package:color_kingdom/features/coloring/widgets/coloring_canvas.dart';
import 'package:color_kingdom/features/coloring/widgets/coloring_renderer_registry.dart';
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
    final values = _sessions.values.toList(growable: false);
    values.sort(
      (a, b) => b.lastUpdatedAtEpochMs.compareTo(a.lastUpdatedAtEpochMs),
    );
    return values;
  }

  @override
  Future<ColoringSession?> getSession(String pageId) async => _sessions[pageId];

  @override
  Future<void> saveSession(ColoringSession session) async {
    _sessions[session.pageId] = session;
  }
}

Future<void> _pumpUntilFound(
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

Future<void> _pumpApp(WidgetTester tester) async {
  final router = GoRouter(
    initialLocation: '/home',
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
        coloringSessionRepositoryProvider.overrideWithValue(
          _MemorySessionRepository(),
        ),
      ],
      child: MaterialApp.router(routerConfig: router),
    ),
  );

  await _pumpUntilFound(tester, find.text('Choose an Adventure'));
}

Future<void> _waitForColoringReady(WidgetTester tester) async {
  for (var i = 0; i < 50; i++) {
    final container = ProviderScope.containerOf(
      tester.element(find.byType(ColoringScreen)),
    );
    final state = container.read(coloringControllerProvider);
    if (state.isReady && state.page != null) {
      return;
    }
    await tester.pump(const Duration(milliseconds: 50));
  }

  fail('Timed out waiting for Lovely Kitten coloring state to be ready.');
}

int _coloredRegionCount(Map<String, Color> regionColors) {
  return regionColors.values
      .where((color) => color.toARGB32() != Colors.transparent.toARGB32())
      .length;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets(
    'Animals -> Lovely Kitten opens raster page and supports representative raster fill',
    (tester) async {
      await _pumpApp(tester);

      await tester.tap(find.text('Animals').first);
      await _pumpUntilFound(tester, find.text('Lovely Kitten'));

      expect(find.text('Lovely Kitten'), findsOneWidget);
      expect(find.text('Lovely Kitten (Legacy SVG)'), findsNothing);

      await tester.tap(find.widgetWithText(ListTile, 'Lovely Kitten').first);
      await _pumpUntilFound(tester, find.byType(ColoringScreen));
      await _waitForColoringReady(tester);

      final container = ProviderScope.containerOf(
        tester.element(find.byType(ColoringScreen)),
      );
      final controller = container.read(coloringControllerProvider.notifier);
      var state = container.read(coloringControllerProvider);
      final page = state.page!;
      final metadata = page.rasterRegionMetadata!;

      expect(page.id, 'lovely-kitten-raster-poc');
      expect(page.title, 'Lovely Kitten');
      expect(page.rendererType, ColoringRendererType.rasterRegion);
      expect(page.regions.length, 175);
      expect(metadata.regionMapEntries.length, 175);
      expect(
        ColoringRendererRegistry.resolve(page).id,
        'raster-region-coloring-renderer',
      );

      final canvasFinder = find.byType(ColoringCanvas);
      expect(canvasFinder, findsOneWidget);
      final canvasRect = tester.getRect(canvasFinder);

      controller.selectColor(Colors.green);
      controller.fillRegion('region-043');
      await tester.pump();
      state = container.read(coloringControllerProvider);
      expect(
        state.regionColors['region-043']?.toARGB32(),
        Colors.green.toARGB32(),
      );

      final coloredBeforeBackground = _coloredRegionCount(state.regionColors);
      controller.selectColor(Colors.purple);
      await tester.tapAt(
        Offset(canvasRect.left + 1, canvasRect.top + 1),
      );
      await tester.pump();
      state = container.read(coloringControllerProvider);
      expect(_coloredRegionCount(state.regionColors), coloredBeforeBackground);
      expect(
        state.regionColors['region-043']?.toARGB32(),
        Colors.green.toARGB32(),
      );

      await controller.waitForPendingPersistence();
    },
  );
}
