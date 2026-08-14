import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:color_kingdom/features/categories/models/category.dart';
import 'package:color_kingdom/features/coloring/models/coloring_page.dart';
import 'package:color_kingdom/features/coloring/models/coloring_session.dart';
import 'package:color_kingdom/features/coloring/providers/coloring_provider.dart';
import 'package:color_kingdom/features/coloring/repositories/coloring_page_repository.dart';
import 'package:color_kingdom/features/coloring/repositories/coloring_session_repository.dart';
import 'package:color_kingdom/features/gallery/providers/my_creations_provider.dart';

class _FakePageRepository implements ColoringPageRepository {
  _FakePageRepository({
    required this.pages,
    required this.categories,
  });

  final List<ColoringPage> pages;
  final List<Category> categories;

  @override
  Future<List<Category>> getCategories() async => categories;

  @override
  Future<ColoringPage> getPageById(String id) async {
    return pages.firstWhere((page) => page.id == id);
  }

  @override
  Future<List<ColoringPage>> getPages() async => pages;

  @override
  Future<List<ColoringPage>> getPagesByCategory(String categoryId) async {
    return pages.where((page) => page.categoryId == categoryId).toList();
  }
}

class _FakeSessionRepository implements ColoringSessionRepository {
  _FakeSessionRepository({
    required this.sessions,
    this.throwOnGetAll = false,
  });

  final List<ColoringSession> sessions;
  final bool throwOnGetAll;

  @override
  Future<void> clearAllSessions() async {}

  @override
  Future<void> deleteSession(String pageId) async {}

  @override
  Future<List<ColoringSession>> getAllSessions() async {
    if (throwOnGetAll) {
      throw StateError('Repository unavailable');
    }
    return sessions;
  }

  @override
  Future<ColoringSession?> getSession(String pageId) async {
    for (final session in sessions) {
      if (session.pageId == pageId) {
        return session;
      }
    }

    return null;
  }

  @override
  Future<void> saveSession(ColoringSession session) async {}
}

const _animalPage = ColoringPage(
  id: 'happy-cat',
  title: 'Happy Cat',
  categoryId: 'animals',
  assetPath: 'assets/coloring_pages/animals/happy_cat.svg',
  sortOrder: 0,
  regions: [
    ColoringRegion(id: 'cat-body', name: 'Body', defaultColor: Colors.transparent),
    ColoringRegion(id: 'cat-tail', name: 'Tail', defaultColor: Colors.transparent),
    ColoringRegion(id: 'cat-head', name: 'Head', defaultColor: Colors.transparent),
  ],
);

const _spacePage = ColoringPage(
  id: 'space-rocket',
  title: 'Space Rocket',
  categoryId: 'space',
  assetPath: 'assets/coloring_pages/space/space_rocket.svg',
  sortOrder: 0,
  regions: [
    ColoringRegion(id: 'rocket-body', name: 'Body', defaultColor: Colors.transparent),
    ColoringRegion(id: 'rocket-window', name: 'Window', defaultColor: Colors.transparent),
  ],
);

const _rasterPage = ColoringPage(
  id: 'lovely-kitten-raster-poc',
  title: 'Lovely Kitten (Raster POC)',
  categoryId: 'animals',
  assetPath: 'assets/coloring_pages/animals/lovely_kitten_raster_poc/line_art.png',
  thumbnailAssetPath: 'assets/coloring_pages/animals/lovely_kitten_raster_poc/line_art.png',
  sortOrder: 1,
  rendererType: ColoringRendererType.rasterRegion,
  regions: [
    ColoringRegion(id: 'region-002', name: 'region-002', defaultColor: Colors.transparent),
  ],
);

ProviderContainer _buildContainer({
  required ColoringPageRepository pageRepository,
  required ColoringSessionRepository sessionRepository,
}) {
  return ProviderContainer(
    overrides: [
      coloringPageRepositoryProvider.overrideWithValue(pageRepository),
      coloringSessionRepositoryProvider.overrideWithValue(sessionRepository),
    ],
  );
}

void main() {
  test('provider joins session with page and category metadata', () async {
    final container = _buildContainer(
      pageRepository: _FakePageRepository(
        pages: const [_animalPage],
        categories: const [
          Category(categoryId: 'animals', title: 'Animals', sortOrder: 0),
        ],
      ),
      sessionRepository: _FakeSessionRepository(
        sessions: const [
          ColoringSession(
            pageId: 'happy-cat',
            regionColors: {'cat-body': 0xFFFF0000},
            schemaVersion: ColoringSession.currentSchemaVersion,
            lastUpdatedAtEpochMs: 100,
          ),
        ],
      ),
    );
    addTearDown(container.dispose);

    final result = await container.read(myCreationsProvider.future);

    expect(result.length, 1);
    expect(result.single.pageId, 'happy-cat');
    expect(result.single.pageTitle, 'Happy Cat');
    expect(result.single.categoryTitle, 'Animals');
  });

  test('progress calculation counts only valid known non-default regions', () async {
    final container = _buildContainer(
      pageRepository: _FakePageRepository(
        pages: const [_animalPage],
        categories: const [
          Category(categoryId: 'animals', title: 'Animals', sortOrder: 0),
        ],
      ),
      sessionRepository: _FakeSessionRepository(
        sessions: const [
          ColoringSession(
            pageId: 'happy-cat',
            regionColors: {
              'cat-body': 0xFFFF0000,
              'cat-tail': 0x00000000,
              'unknown-region': 0xFF00FF00,
            },
            schemaVersion: ColoringSession.currentSchemaVersion,
            lastUpdatedAtEpochMs: 100,
          ),
        ],
      ),
    );
    addTearDown(container.dispose);

    final result = await container.read(myCreationsProvider.future);

    expect(result.length, 1);
    expect(result.single.coloredRegionCount, 1);
    expect(result.single.totalRegionCount, 3);
    expect(result.single.progressRatio, closeTo(1 / 3, 0.001));
    expect(result.single.progressPercent, 33);
  });

  test('zero progress sessions are excluded', () async {
    final container = _buildContainer(
      pageRepository: _FakePageRepository(
        pages: const [_animalPage],
        categories: const [
          Category(categoryId: 'animals', title: 'Animals', sortOrder: 0),
        ],
      ),
      sessionRepository: _FakeSessionRepository(
        sessions: const [
          ColoringSession(
            pageId: 'happy-cat',
            regionColors: {'cat-body': 0x00000000},
            schemaVersion: ColoringSession.currentSchemaVersion,
            lastUpdatedAtEpochMs: 100,
          ),
        ],
      ),
    );
    addTearDown(container.dispose);

    final result = await container.read(myCreationsProvider.future);

    expect(result, isEmpty);
  });

  test('stale sessions missing pages are excluded', () async {
    final container = _buildContainer(
      pageRepository: _FakePageRepository(
        pages: const [_animalPage],
        categories: const [
          Category(categoryId: 'animals', title: 'Animals', sortOrder: 0),
        ],
      ),
      sessionRepository: _FakeSessionRepository(
        sessions: const [
          ColoringSession(
            pageId: 'unknown-page',
            regionColors: {'x': 0xFFFF0000},
            schemaVersion: ColoringSession.currentSchemaVersion,
            lastUpdatedAtEpochMs: 100,
          ),
        ],
      ),
    );
    addTearDown(container.dispose);

    final result = await container.read(myCreationsProvider.future);

    expect(result, isEmpty);
  });

  test('newest-first ordering from session repository is preserved', () async {
    final container = _buildContainer(
      pageRepository: _FakePageRepository(
        pages: const [_animalPage, _spacePage],
        categories: const [
          Category(categoryId: 'animals', title: 'Animals', sortOrder: 0),
          Category(categoryId: 'space', title: 'Space', sortOrder: 1),
        ],
      ),
      sessionRepository: _FakeSessionRepository(
        sessions: const [
          ColoringSession(
            pageId: 'space-rocket',
            regionColors: {'rocket-body': 0xFFFF0000},
            schemaVersion: ColoringSession.currentSchemaVersion,
            lastUpdatedAtEpochMs: 200,
          ),
          ColoringSession(
            pageId: 'happy-cat',
            regionColors: {'cat-body': 0xFF00FF00},
            schemaVersion: ColoringSession.currentSchemaVersion,
            lastUpdatedAtEpochMs: 100,
          ),
        ],
      ),
    );
    addTearDown(container.dispose);

    final result = await container.read(myCreationsProvider.future);

    expect(result.map((item) => item.pageId).toList(), ['space-rocket', 'happy-cat']);
  });

  test('repository failure becomes provider error', () async {
    final container = _buildContainer(
      pageRepository: _FakePageRepository(
        pages: const [_animalPage],
        categories: const [
          Category(categoryId: 'animals', title: 'Animals', sortOrder: 0),
        ],
      ),
      sessionRepository: _FakeSessionRepository(
        sessions: const [],
        throwOnGetAll: true,
      ),
    );
    addTearDown(container.dispose);

    final value = container.read(myCreationsProvider);

    expect(value.isLoading, isTrue);
    await expectLater(container.read(myCreationsProvider.future), throwsStateError);
  });

  test('raster pages produce raster preview asset paths', () async {
    final container = _buildContainer(
      pageRepository: _FakePageRepository(
        pages: const [_rasterPage],
        categories: const [
          Category(categoryId: 'animals', title: 'Animals', sortOrder: 0),
        ],
      ),
      sessionRepository: _FakeSessionRepository(
        sessions: const [
          ColoringSession(
            pageId: 'lovely-kitten-raster-poc',
            regionColors: {'region-002': 0xFFFF0000},
            schemaVersion: ColoringSession.currentSchemaVersion,
            lastUpdatedAtEpochMs: 100,
          ),
        ],
      ),
    );
    addTearDown(container.dispose);

    final result = await container.read(myCreationsProvider.future);
    expect(result.length, 1);
    expect(
      result.single.previewAssetPath,
      'assets/coloring_pages/animals/lovely_kitten_raster_poc/line_art.png',
    );
  });
}
