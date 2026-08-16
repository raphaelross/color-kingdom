import 'dart:convert';
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
import 'package:color_kingdom/features/gallery/providers/my_creations_provider.dart';

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
        .where((page) => page.categoryId == categoryId)
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
  Future<ColoringSession?> getSession(String pageId) async {
    return sessions[pageId];
  }

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

  test(
    'Cheerful Panda exists in animals catalog and resolves to raster renderer',
    () {
      final page = sampleCheerfulBabyPandaPage;
      expect(sampleColoringPages.any((p) => p.id == page.id), isTrue);
      expect(page.categoryId, 'animals');
      expect(page.rendererType, ColoringRendererType.rasterRegion);
      expect(page.regions.length, 77);
      expect(page.rasterRegionMetadata!.regionMapEntries.length, 77);
    },
  );

  test(
    'Panda runtime metadata and assets are coherent with 77 regions',
    () async {
      final page = sampleCheerfulBabyPandaPage;
      final metadata = page.rasterRegionMetadata!;

      final metadataJson = await rootBundle.loadString(
        metadata.metadataAssetPath!,
      );
      final decoded = jsonDecode(metadataJson) as Map<String, dynamic>;
      final regions = (decoded['regions'] as List<dynamic>)
          .cast<Map<String, dynamic>>();
      expect(decoded['pageId'], page.id);
      expect(decoded['regionCount'], 77);
      expect(regions.length, 77);

      final logicalMapAsset = await rootBundle.load(
        metadata.regionMapAssetPath,
      );
      expect(logicalMapAsset.lengthInBytes, greaterThan(0));

      final visualMapAsset = await rootBundle.load(
        metadata.regionFillMapAssetPath!,
      );
      expect(visualMapAsset.lengthInBytes, greaterThan(0));

      final runtimeIntegrity =
          decoded['runtimeIntegrity'] as Map<String, dynamic>?;
      expect(runtimeIntegrity, isNotNull);
      expect(
        runtimeIntegrity!['logicalRegionCountWithPixels'],
        metadata.regionMapEntries.length,
      );
      expect(
        runtimeIntegrity['fillRegionCountWithPixels'],
        metadata.regionMapEntries.length,
      );
      expect(runtimeIntegrity['missingLogicalRegionIds'], isEmpty);
      expect(runtimeIntegrity['missingFillRegionIds'], isEmpty);
    },
  );

  test(
    'Panda hit testing supports large and small regions with background no-op',
    () async {
      final page = sampleCheerfulBabyPandaPage;
      final metadata = page.rasterRegionMetadata!;
      final hitTester = const RasterRegionHitTester();

      final colorToRegionId = <int, String>{
        for (final entry in metadata.regionMapEntries)
          hitTester.encodeColorKey(
            entry.rgba[0],
            entry.rgba[1],
            entry.rgba[2],
            entry.rgba[3],
          ): entry.regionId,
      };

      final logicalMapAsset = await rootBundle.load(
        metadata.regionMapAssetPath,
      );
      final logicalMapImage = await _decodeImage(
        logicalMapAsset.buffer.asUint8List(),
      );
      final logicalMapBytes = await logicalMapImage.toByteData(
        format: ui.ImageByteFormat.rawRgba,
      );
      expect(logicalMapBytes, isNotNull);
      final logicalRgba = logicalMapBytes!.buffer.asUint8List();

      final primaryRegionId = metadata.regionMapEntries.first.regionId;
      final secondaryRegionId =
          metadata.regionMapEntries
              .map((e) => e.regionId)
              .contains('region-020')
          ? 'region-020'
          : metadata.regionMapEntries.last.regionId;

      int? primaryOffset;
      int? secondaryOffset;
      int? backgroundOffset;
      final pixelCount = metadata.imageWidth * metadata.imageHeight;
      for (var i = 0; i < pixelCount; i++) {
        final offset = i * 4;
        final key = hitTester.encodeColorKey(
          logicalRgba[offset],
          logicalRgba[offset + 1],
          logicalRgba[offset + 2],
          logicalRgba[offset + 3],
        );
        final regionId = colorToRegionId[key];

        if (regionId == primaryRegionId && primaryOffset == null) {
          primaryOffset = offset;
        }
        if (regionId == secondaryRegionId && secondaryOffset == null) {
          secondaryOffset = offset;
        }
        if (regionId == null && backgroundOffset == null) {
          backgroundOffset = offset;
        }

        if (primaryOffset != null &&
            secondaryOffset != null &&
            backgroundOffset != null) {
          break;
        }
      }

      expect(primaryOffset, isNotNull);
      expect(secondaryOffset, isNotNull);
      expect(backgroundOffset, isNotNull);

      final primaryX = (primaryOffset! ~/ 4) % metadata.imageWidth;
      final primaryY = (primaryOffset ~/ 4) ~/ metadata.imageWidth;
      final primaryHit = hitTester.regionIdAtPixel(
        x: primaryX,
        y: primaryY,
        imageWidth: metadata.imageWidth,
        imageHeight: metadata.imageHeight,
        rgbaBytes: logicalRgba,
        colorToRegionId: colorToRegionId,
      );
      expect(primaryHit, primaryRegionId);

      final secondaryX = (secondaryOffset! ~/ 4) % metadata.imageWidth;
      final secondaryY = (secondaryOffset ~/ 4) ~/ metadata.imageWidth;
      final secondaryHit = hitTester.regionIdAtPixel(
        x: secondaryX,
        y: secondaryY,
        imageWidth: metadata.imageWidth,
        imageHeight: metadata.imageHeight,
        rgbaBytes: logicalRgba,
        colorToRegionId: colorToRegionId,
      );
      expect(secondaryHit, secondaryRegionId);

      final backgroundPixelX = (backgroundOffset! ~/ 4) % metadata.imageWidth;
      final backgroundPixelY = (backgroundOffset ~/ 4) ~/ metadata.imageWidth;

      final backgroundHit = hitTester.regionIdAtPixel(
        x: backgroundPixelX,
        y: backgroundPixelY,
        imageWidth: metadata.imageWidth,
        imageHeight: metadata.imageHeight,
        rgbaBytes: logicalRgba,
        colorToRegionId: colorToRegionId,
      );
      expect(backgroundHit, isNull);

      logicalMapImage.dispose();
    },
  );

  test(
    'Panda controller supports independent fills, undo/redo, clear, and persistence',
    () async {
      final sessionRepository = _MemorySessionRepository();
      final pageRepository = _FakeRepository([
        sampleCheerfulBabyPandaPage,
        sampleLovelyKittenPage,
      ]);

      final container = ProviderContainer(
        overrides: [
          coloringInitialPageIdProvider.overrideWithValue(
            'cheerful-baby-panda',
          ),
          coloringPageRepositoryProvider.overrideWithValue(pageRepository),
          coloringSessionRepositoryProvider.overrideWithValue(
            sessionRepository,
          ),
        ],
      );
      addTearDown(container.dispose);

      await _waitForReady(container);
      final controller = container.read(coloringControllerProvider.notifier);

      final regionA = sampleCheerfulBabyPandaPage.regions.first.id;
      final regionB = sampleCheerfulBabyPandaPage.regions[1].id;

      controller.selectColor(Colors.red);
      controller.fillRegion(regionA);
      controller.selectColor(Colors.blue);
      controller.fillRegion(regionB);

      var state = container.read(coloringControllerProvider);
      expect(state.regionColors[regionA]?.toARGB32(), Colors.red.toARGB32());
      expect(state.regionColors[regionB]?.toARGB32(), Colors.blue.toARGB32());

      controller.undo();
      state = container.read(coloringControllerProvider);
      expect(
        state.regionColors[regionB]?.toARGB32(),
        Colors.transparent.toARGB32(),
      );

      controller.undo();
      state = container.read(coloringControllerProvider);
      expect(
        state.regionColors[regionA]?.toARGB32(),
        Colors.transparent.toARGB32(),
      );

      controller.redo();
      controller.redo();
      state = container.read(coloringControllerProvider);
      expect(state.regionColors[regionA]?.toARGB32(), Colors.red.toARGB32());
      expect(state.regionColors[regionB]?.toARGB32(), Colors.blue.toARGB32());

      controller.clear();
      state = container.read(coloringControllerProvider);
      expect(
        state.regionColors.values.every(
          (c) => c.toARGB32() == Colors.transparent.toARGB32(),
        ),
        isTrue,
      );

      controller.selectColor(Colors.green);
      controller.fillRegion(regionA);
      await controller.waitForPendingPersistence();

      final saved = sessionRepository.sessions['cheerful-baby-panda'];
      expect(saved, isNotNull);
      expect(saved!.regionColors[regionA], Colors.green.toARGB32());

      final reopened = ProviderContainer(
        overrides: [
          coloringInitialPageIdProvider.overrideWithValue(
            'cheerful-baby-panda',
          ),
          coloringPageRepositoryProvider.overrideWithValue(pageRepository),
          coloringSessionRepositoryProvider.overrideWithValue(
            sessionRepository,
          ),
        ],
      );
      addTearDown(reopened.dispose);

      final restored = await _waitForReady(reopened);
      expect(
        restored.regionColors[regionA]?.toARGB32(),
        Colors.green.toARGB32(),
      );

      await controller.loadPageById('lovely-kitten-raster-poc');
      state = container.read(coloringControllerProvider);
      expect(state.page!.id, 'lovely-kitten-raster-poc');
      expect(state.regionColors.length, 175);
      expect(
        state.regionColors[regionA]?.toARGB32(),
        Colors.transparent.toARGB32(),
      );
    },
  );

  test(
    'My Creations includes Panda after progress and preserves origin metadata',
    () async {
      final sessionRepository = _MemorySessionRepository();
      final pageRepository = _FakeRepository([
        sampleCheerfulBabyPandaPage,
        sampleLovelyKittenPage,
      ]);

      final controllerContainer = ProviderContainer(
        overrides: [
          coloringInitialPageIdProvider.overrideWithValue(
            'cheerful-baby-panda',
          ),
          coloringPageRepositoryProvider.overrideWithValue(pageRepository),
          coloringSessionRepositoryProvider.overrideWithValue(
            sessionRepository,
          ),
        ],
      );
      addTearDown(controllerContainer.dispose);
      await _waitForReady(controllerContainer);

      final controller = controllerContainer.read(
        coloringControllerProvider.notifier,
      );
      controller.selectColor(Colors.teal);
      controller.fillRegion(sampleCheerfulBabyPandaPage.regions.first.id);
      await controller.waitForPendingPersistence();

      final galleryContainer = ProviderContainer(
        overrides: [
          coloringPageRepositoryProvider.overrideWithValue(pageRepository),
          coloringSessionRepositoryProvider.overrideWithValue(
            sessionRepository,
          ),
        ],
      );
      addTearDown(galleryContainer.dispose);

      final creations = await galleryContainer.read(myCreationsProvider.future);
      expect(
        creations
            .where((item) => item.pageId == 'cheerful-baby-panda')
            .isNotEmpty,
        isTrue,
      );

      final panda = creations.firstWhere(
        (item) => item.pageId == 'cheerful-baby-panda',
      );
      expect(panda.progressPercent, greaterThan(0));
      expect(
        panda.previewAssetPath,
        'assets/coloring_pages/animals/cheerful_baby_panda/line_art_foreground.png',
      );
    },
  );
}
