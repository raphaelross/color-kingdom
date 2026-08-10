import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import 'package:color_kingdom/app/router/app_router.dart';
import 'package:color_kingdom/features/categories/models/category.dart';
import 'package:color_kingdom/features/coloring/coloring_screen.dart';
import 'package:color_kingdom/features/coloring/models/coloring_page.dart';
import 'package:color_kingdom/features/coloring/models/coloring_session.dart';
import 'package:color_kingdom/features/coloring/providers/coloring_provider.dart';
import 'package:color_kingdom/features/coloring/repositories/coloring_page_repository.dart';
import 'package:color_kingdom/features/coloring/repositories/coloring_session_repository.dart';
import 'package:color_kingdom/features/gallery/gallery_screen.dart';
import 'package:color_kingdom/features/gallery/models/my_creation_item.dart';
import 'package:color_kingdom/features/gallery/providers/my_creations_provider.dart';

class _FakePageRepository implements ColoringPageRepository {
  @override
  Future<List<Category>> getCategories() async {
    return const [
      Category(categoryId: 'animals', title: 'Animals', sortOrder: 0),
    ];
  }

  @override
  Future<ColoringPage> getPageById(String id) async {
    return _happyCatPage;
  }

  @override
  Future<List<ColoringPage>> getPages() async {
    return const [_happyCatPage];
  }

  @override
  Future<List<ColoringPage>> getPagesByCategory(String categoryId) async {
    return const [_happyCatPage];
  }
}

class _FakeSessionRepository implements ColoringSessionRepository {
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
    return _sessions.values.toList(growable: false);
  }

  @override
  Future<ColoringSession?> getSession(String pageId) async {
    return _sessions[pageId];
  }

  @override
  Future<void> saveSession(ColoringSession session) async {
    _sessions[session.pageId] = session;
  }
}

const _happyCatPage = ColoringPage(
  id: 'happy-cat',
  title: 'Happy Cat',
  categoryId: 'animals',
  assetPath: 'assets/coloring_pages/animals/happy_cat.svg',
  sortOrder: 0,
  regions: [
    ColoringRegion(id: 'cat-body', name: 'Body', defaultColor: Colors.transparent),
  ],
);

GoRouter _buildRouter() {
  return GoRouter(
    initialLocation: AppRoute.gallery,
    routes: [
      GoRoute(
        path: AppRoute.home,
        name: AppRouteName.home,
        builder: (_, __) => const Scaffold(body: Center(child: Text('Home'))),
      ),
      GoRoute(
        path: AppRoute.gallery,
        name: AppRouteName.gallery,
        builder: (_, __) => const GalleryScreen(),
      ),
      GoRoute(
        path: AppRoute.coloring,
        name: AppRouteName.coloring,
        builder: (_, state) {
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
}

Future<void> _pumpGallery(
  WidgetTester tester, {
  required Override myCreationsOverride,
}) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        myCreationsOverride,
        coloringPageRepositoryProvider.overrideWithValue(_FakePageRepository()),
        coloringSessionRepositoryProvider.overrideWithValue(_FakeSessionRepository()),
      ],
      child: MaterialApp.router(routerConfig: _buildRouter()),
    ),
  );
}

void main() {
  testWidgets('shows loading state', (tester) async {
    final completer = Completer<List<MyCreationItem>>();

    await _pumpGallery(
      tester,
      myCreationsOverride: myCreationsProvider.overrideWith(
        (ref) => completer.future,
      ),
    );

    expect(find.byType(CircularProgressIndicator), findsOneWidget);
  });

  testWidgets('shows empty state with home CTA', (tester) async {
    await _pumpGallery(
      tester,
      myCreationsOverride: myCreationsProvider.overrideWith(
        (ref) async => const <MyCreationItem>[],
      ),
    );

    await tester.pumpAndSettle();

    expect(find.text('No creations yet! Pick a picture and start coloring.'), findsOneWidget);
    expect(find.text('Go to Adventures'), findsOneWidget);
  });

  testWidgets('shows error state and retry refreshes provider', (tester) async {
    var attempts = 0;

    await _pumpGallery(
      tester,
      myCreationsOverride: myCreationsProvider.overrideWith((ref) async {
        attempts += 1;
        if (attempts <= 2) {
          throw StateError('boom');
        }
        return const <MyCreationItem>[];
      }),
    );

    await tester.pumpAndSettle();

    expect(find.text('We could not load your creations right now.'), findsOneWidget);
    expect(find.text('Retry'), findsOneWidget);

    await tester.tap(find.text('Retry'));
    await tester.pumpAndSettle();

    expect(find.text('No creations yet! Pick a picture and start coloring.'), findsOneWidget);
  });

  testWidgets('renders multiple creation cards with page and category info', (tester) async {
    await _pumpGallery(
      tester,
      myCreationsOverride: myCreationsProvider.overrideWith(
        (ref) async => const <MyCreationItem>[
          MyCreationItem(
            pageId: 'happy-cat',
            pageTitle: 'Happy Cat',
            categoryId: 'animals',
            categoryTitle: 'Animals',
            previewAssetPath: 'assets/coloring_pages/animals/happy_cat.svg',
            coloredRegionCount: 3,
            totalRegionCount: 10,
            progressRatio: 0.3,
            progressPercent: 30,
            lastUpdatedAtEpochMs: 100,
          ),
          MyCreationItem(
            pageId: 'playful-puppy',
            pageTitle: 'Playful Puppy',
            categoryId: 'animals',
            categoryTitle: 'Animals',
            previewAssetPath: 'assets/coloring_pages/animals/playful_puppy.svg',
            coloredRegionCount: 5,
            totalRegionCount: 10,
            progressRatio: 0.5,
            progressPercent: 50,
            lastUpdatedAtEpochMs: 90,
          ),
        ],
      ),
    );

    await tester.pumpAndSettle();

    expect(find.text('Happy Cat'), findsOneWidget);
    expect(find.text('Playful Puppy'), findsOneWidget);
    expect(find.text('Animals'), findsNWidgets(2));
    expect(find.text('30% colored'), findsOneWidget);
    expect(find.text('50% colored'), findsOneWidget);
  });

  testWidgets('tapping creation card navigates to coloring page', (tester) async {
    await _pumpGallery(
      tester,
      myCreationsOverride: myCreationsProvider.overrideWith(
        (ref) async => const <MyCreationItem>[
          MyCreationItem(
            pageId: 'happy-cat',
            pageTitle: 'Happy Cat',
            categoryId: 'animals',
            categoryTitle: 'Animals',
            previewAssetPath: 'assets/coloring_pages/animals/happy_cat.svg',
            coloredRegionCount: 3,
            totalRegionCount: 10,
            progressRatio: 0.3,
            progressPercent: 30,
            lastUpdatedAtEpochMs: 100,
          ),
        ],
      ),
    );

    await tester.pumpAndSettle();

    await tester.tap(find.text('Happy Cat'));
    await tester.pumpAndSettle();

    expect(find.byType(ColoringScreen), findsOneWidget);
    expect(find.byTooltip('Back to My Creations'), findsOneWidget);
    expect(find.byTooltip('Home'), findsOneWidget);
  });
}
