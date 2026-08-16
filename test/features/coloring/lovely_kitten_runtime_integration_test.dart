import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:color_kingdom/features/categories/models/category.dart';
import 'package:color_kingdom/features/coloring/data/sample_coloring_pages.dart';
import 'package:color_kingdom/features/coloring/models/coloring_page.dart';
import 'package:color_kingdom/features/coloring/models/coloring_session.dart';
import 'package:color_kingdom/features/coloring/models/coloring_state.dart';
import 'package:color_kingdom/features/coloring/providers/coloring_provider.dart';
import 'package:color_kingdom/features/coloring/repositories/coloring_page_repository.dart';
import 'package:color_kingdom/features/coloring/repositories/coloring_session_repository.dart';
import 'package:color_kingdom/features/coloring/widgets/renderers/raster_region/raster_region_hit_tester.dart';

class _FakeRepository implements ColoringPageRepository {
  _FakeRepository(this.pages);

  final List<ColoringPage> pages;

  @override
  Future<List<Category>> getCategories() async => const [
    Category(categoryId: 'animals', title: 'Animals', sortOrder: 0),
  ];

  @override
  Future<ColoringPage> getPageById(String id) async {
    return pages.firstWhere((page) => page.id == id);
  }

  @override
  Future<List<ColoringPage>> getPages() async => pages;

  @override
  Future<List<ColoringPage>> getPagesByCategory(String categoryId) async {
    return pages
        .where((p) => p.categoryId == categoryId)
        .toList(growable: false);
  }
}

class _MemorySessionRepository implements ColoringSessionRepository {
  final Map<String, ColoringSession> sessions = <String, ColoringSession>{};

  @override
  Future<void> clearAllSessions() async {
    sessions.clear();
  }

  @override
  Future<void> deleteSession(String pageId) async {
    sessions.remove(pageId);
  }

  @override
  Future<List<ColoringSession>> getAllSessions() async {
    final values = sessions.values.toList();
    values.sort(
      (a, b) => b.lastUpdatedAtEpochMs.compareTo(a.lastUpdatedAtEpochMs),
    );
    return values;
  }

  @override
  Future<ColoringSession?> getSession(String pageId) async => sessions[pageId];

  @override
  Future<void> saveSession(ColoringSession session) async {
    sessions[session.pageId] = session;
  }
}

Future<ui.Image> _decodeImage(Uint8List bytes) async {
  final codec = await ui.instantiateImageCodec(bytes);
  try {
    final frame = await codec.getNextFrame();
    return frame.image;
  } finally {
    codec.dispose();
  }
}

Future<ColoringState> _waitForReady(ProviderContainer container) async {
  for (var i = 0; i < 50; i++) {
    final state = container.read(coloringControllerProvider);
    if (state.status == ColoringLoadStatus.ready) {
      return state;
    }
    await Future<void>.delayed(const Duration(milliseconds: 10));
  }
  return container.read(coloringControllerProvider);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('Lovely Kitten runtime metadata and region list expose 175 regions', () {
    final page = sampleLovelyKittenPage;
    final metadata = page.rasterRegionMetadata!;

    expect(page.id, 'lovely-kitten-raster-poc');
    expect(page.rendererType, ColoringRendererType.rasterRegion);
    expect(page.regions.length, 175);
    expect(metadata.regionMapEntries.length, 175);
    expect(page.regions.any((r) => r.id == 'region-001'), isTrue);
    expect(
      metadata.regionMapEntries.any((e) => e.regionId == 'region-001'),
      isTrue,
    );
  });

  test(
    'Lovely Kitten runtime maps are coherent for all 175 metadata regions',
    () async {
      final page = sampleLovelyKittenPage;
      final metadata = page.rasterRegionMetadata!;
      final hitTester = const RasterRegionHitTester();

      final ids = metadata.regionMapEntries
          .map((e) => e.regionId)
          .toList(growable: false);
      expect(ids.toSet().length, 175);

      final colorToRegionId = <int, String>{};
      for (final entry in metadata.regionMapEntries) {
        expect(entry.rgba.length, 4);
        for (final c in entry.rgba) {
          expect(c, inInclusiveRange(0, 255));
        }
        final key = hitTester.encodeColorKey(
          entry.rgba[0],
          entry.rgba[1],
          entry.rgba[2],
          entry.rgba[3],
        );
        expect(colorToRegionId.containsKey(key), isFalse);
        colorToRegionId[key] = entry.regionId;
      }

      final logicalAsset = await rootBundle.load(metadata.regionMapAssetPath);
      final fillAsset = await rootBundle.load(metadata.regionFillMapAssetPath!);
      expect(logicalAsset.lengthInBytes, greaterThan(0));
      expect(fillAsset.lengthInBytes, greaterThan(0));

      final logicalImage = await _decodeImage(
        logicalAsset.buffer.asUint8List(),
      );
      final fillImage = await _decodeImage(fillAsset.buffer.asUint8List());
      expect(logicalImage.width, metadata.imageWidth);
      expect(logicalImage.height, metadata.imageHeight);
      expect(fillImage.width, metadata.imageWidth);
      expect(fillImage.height, metadata.imageHeight);

      final logicalRaw = await logicalImage.toByteData(
        format: ui.ImageByteFormat.rawRgba,
      );
      final fillRaw = await fillImage.toByteData(
        format: ui.ImageByteFormat.rawRgba,
      );
      expect(logicalRaw, isNotNull);
      expect(fillRaw, isNotNull);

      final logicalRgba = logicalRaw!.buffer.asUint8List();
      final fillRgba = fillRaw!.buffer.asUint8List();

      final logicalCounts = <String, int>{for (final id in ids) id: 0};
      final fillCounts = <String, int>{for (final id in ids) id: 0};

      int? region001Offset;
      int? backgroundOffset;
      final pixelCount = metadata.imageWidth * metadata.imageHeight;
      for (var i = 0; i < pixelCount; i++) {
        final offset = i * 4;

        final logicalKey = hitTester.encodeColorKey(
          logicalRgba[offset],
          logicalRgba[offset + 1],
          logicalRgba[offset + 2],
          logicalRgba[offset + 3],
        );
        final logicalRegion = colorToRegionId[logicalKey];
        if (logicalRegion != null) {
          logicalCounts[logicalRegion] = logicalCounts[logicalRegion]! + 1;
          if (logicalRegion == 'region-001' && region001Offset == null) {
            region001Offset = offset;
          }
        } else {
          backgroundOffset ??= offset;
        }

        final fillKey = hitTester.encodeColorKey(
          fillRgba[offset],
          fillRgba[offset + 1],
          fillRgba[offset + 2],
          fillRgba[offset + 3],
        );
        final fillRegion = colorToRegionId[fillKey];
        if (fillRegion != null) {
          fillCounts[fillRegion] = fillCounts[fillRegion]! + 1;
        }
      }

      for (final id in ids) {
        expect(
          logicalCounts[id],
          greaterThan(0),
          reason: '$id missing logical-map pixels',
        );
        expect(
          fillCounts[id],
          greaterThan(0),
          reason: '$id missing visual-fill pixels',
        );
      }

      expect(
        region001Offset,
        isNotNull,
        reason: 'region-001 should be present and colorable',
      );
      expect(
        backgroundOffset,
        isNotNull,
        reason: 'background should remain non-region',
      );

      final region001X = (region001Offset! ~/ 4) % metadata.imageWidth;
      final region001Y = (region001Offset ~/ 4) ~/ metadata.imageWidth;
      final hit001 = hitTester.regionIdAtPixel(
        x: region001X,
        y: region001Y,
        imageWidth: metadata.imageWidth,
        imageHeight: metadata.imageHeight,
        rgbaBytes: logicalRgba,
        colorToRegionId: colorToRegionId,
      );
      expect(hit001, 'region-001');

      final bgX = (backgroundOffset! ~/ 4) % metadata.imageWidth;
      final bgY = (backgroundOffset ~/ 4) ~/ metadata.imageWidth;
      final bgHit = hitTester.regionIdAtPixel(
        x: bgX,
        y: bgY,
        imageWidth: metadata.imageWidth,
        imageHeight: metadata.imageHeight,
        rgbaBytes: logicalRgba,
        colorToRegionId: colorToRegionId,
      );
      expect(bgHit, isNull);

      logicalImage.dispose();
      fillImage.dispose();
    },
  );

  test(
    'Lovely Kitten old-session subset restores and preserves new regions uncolored',
    () async {
      final sessionRepository = _MemorySessionRepository();
      final pageRepository = _FakeRepository([
        sampleLovelyKittenPage,
        sampleCheerfulBabyPandaPage,
      ]);

      const restoredColor = 0xFFFF0000;
      sessionRepository.sessions['lovely-kitten-raster-poc'] =
          const ColoringSession(
            pageId: 'lovely-kitten-raster-poc',
            regionColors: <String, int>{
              'region-002': restoredColor,
              'region-075': restoredColor,
              'legacy-missing-region': 0xFF00FF00,
            },
            schemaVersion: ColoringSession.currentSchemaVersion,
            lastUpdatedAtEpochMs: 1,
          );

      final container = ProviderContainer(
        overrides: [
          coloringInitialPageIdProvider.overrideWithValue(
            'lovely-kitten-raster-poc',
          ),
          coloringPageRepositoryProvider.overrideWithValue(pageRepository),
          coloringSessionRepositoryProvider.overrideWithValue(
            sessionRepository,
          ),
        ],
      );
      addTearDown(container.dispose);

      final state = await _waitForReady(container);
      expect(state.page!.id, 'lovely-kitten-raster-poc');
      expect(state.regionColors.length, 175);
      expect(state.regionColors['region-002']!.toARGB32(), restoredColor);
      expect(state.regionColors['region-075']!.toARGB32(), restoredColor);
      expect(state.regionColors.containsKey('legacy-missing-region'), isFalse);
      expect(
        state.regionColors['region-001']!.toARGB32(),
        Colors.transparent.toARGB32(),
      );
    },
  );
}
