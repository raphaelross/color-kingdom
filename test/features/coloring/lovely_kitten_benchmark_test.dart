import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:xml/xml.dart';

import 'package:color_kingdom/features/categories/models/category.dart';
import 'package:color_kingdom/features/coloring/data/sample_coloring_pages.dart';
import 'package:color_kingdom/features/coloring/models/coloring_page.dart';
import 'package:color_kingdom/features/coloring/models/coloring_session.dart';
import 'package:color_kingdom/features/coloring/models/coloring_state.dart';
import 'package:color_kingdom/features/coloring/providers/coloring_provider.dart';
import 'package:color_kingdom/features/coloring/repositories/coloring_page_repository.dart';
import 'package:color_kingdom/features/coloring/repositories/coloring_session_repository.dart';
import 'package:color_kingdom/features/coloring/widgets/coloring_renderer_registry.dart';
import 'package:color_kingdom/features/coloring/widgets/renderers/svg/svg_coloring_parser.dart';
import 'package:color_kingdom/features/coloring/widgets/renderers/svg/svg_coloring_renderer.dart';
import 'package:color_kingdom/features/coloring/widgets/renderers/svg/svg_content_validator.dart';
import 'package:color_kingdom/features/coloring/widgets/renderers/svg/svg_region_hit_tester.dart';
import 'package:color_kingdom/features/gallery/providers/my_creations_provider.dart';

const _expectedLovelyKittenRegionIds = <String>{
  'region-bow-center',
  'region-bow-left',
  'region-heart-center',
  'region-paw-left',
  'region-star-01',
};

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
    return pages.where((page) => page.categoryId == categoryId).toList(growable: false);
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
    values.sort((a, b) {
      final timestampOrder = b.lastUpdatedAtEpochMs.compareTo(a.lastUpdatedAtEpochMs);
      if (timestampOrder != 0) {
        return timestampOrder;
      }
      return a.pageId.compareTo(b.pageId);
    });
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

ProviderContainer _buildContainer({
  required ColoringPageRepository pageRepository,
  required ColoringSessionRepository sessionRepository,
  String initialPageId = 'lovely-kitten',
}) {
  return ProviderContainer(
    overrides: [
      coloringPageRepositoryProvider.overrideWithValue(pageRepository),
      coloringSessionRepositoryProvider.overrideWithValue(sessionRepository),
      coloringInitialPageIdProvider.overrideWithValue(initialPageId),
    ],
  );
}

Offset _viewBoxPointToLocal({
  required Offset point,
  required Rect viewBox,
  required Size paintSize,
}) {
  final scaleX = paintSize.width / viewBox.width;
  final scaleY = paintSize.height / viewBox.height;
  final scale = scaleX < scaleY ? scaleX : scaleY;

  final drawWidth = viewBox.width * scale;
  final drawHeight = viewBox.height * scale;
  final offsetX = (paintSize.width - drawWidth) / 2;
  final offsetY = (paintSize.height - drawHeight) / 2;

  final localX = (point.dx - viewBox.left) * scale + offsetX;
  final localY = (point.dy - viewBox.top) * scale + offsetY;
  return Offset(localX, localY);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('Lovely Kitten production SVG parses successfully', () async {
    final parser = SvgColoringParser();
    final svg = await rootBundle.loadString(sampleLovelyKittenPage.assetPath);

    final result = parser.parseAndValidate(
      svgXml: svg,
      page: sampleLovelyKittenPage,
    );

    expect(result.isValid, isTrue);
    expect(result.asset, isNotNull);
  });

  test('Lovely Kitten production SVG preserves path1 geometry from working source', () {
    final workingRaw = File(
      'assets/source_artwork/animals/lovely_kitten_interactive_working.svg',
    ).readAsStringSync();
    final productionRaw = File(
      'assets/coloring_pages/animals/lovely_kitten.svg',
    ).readAsStringSync();

    final workingDoc = XmlDocument.parse(workingRaw);
    final productionDoc = XmlDocument.parse(productionRaw);

    final workingPath = workingDoc.findAllElements('path').firstWhere(
          (element) => element.getAttribute('id') == 'path1',
        );
    final productionPath = productionDoc.findAllElements('path').firstWhere(
          (element) => element.getAttribute('id') == 'path1',
        );

    expect(productionPath.getAttribute('d'), workingPath.getAttribute('d'));
  });

  test('Lovely Kitten discovers exactly the five expected colorable IDs', () async {
    final parser = SvgColoringParser();
    final svg = await rootBundle.loadString(sampleLovelyKittenPage.assetPath);

    final result = parser.parseAndValidate(svgXml: svg, page: sampleLovelyKittenPage);

    expect(result.isValid, isTrue);
    expect(result.asset!.colorableById.keys.toSet(), _expectedLovelyKittenRegionIds);
  });

  test('Lovely Kitten static path1 is not considered colorable', () async {
    final parser = SvgColoringParser();
    final svg = await rootBundle.loadString(sampleLovelyKittenPage.assetPath);

    final result = parser.parseAndValidate(svgXml: svg, page: sampleLovelyKittenPage);

    expect(result.isValid, isTrue);
    expect(result.asset!.colorableById.containsKey('path1'), isFalse);
  });

  test('Lovely Kitten model and SVG parity passes validator without hard errors', () async {
    final validator = SvgContentValidator();
    final svg = await rootBundle.loadString(sampleLovelyKittenPage.assetPath);

    final report = validator.validate(svgXml: svg, page: sampleLovelyKittenPage);

    expect(report.errors, isEmpty);
    expect(report.colorableRegionIds, _expectedLovelyKittenRegionIds);
    expect(report.colorableRegionCount, _expectedLovelyKittenRegionIds.length);
  });

  test('Lovely Kitten five regions can be independently represented by state colors', () async {
    final sessionRepository = _MemorySessionRepository();
    final container = _buildContainer(
      pageRepository: _FakeRepository([sampleLovelyKittenPage]),
      sessionRepository: sessionRepository,
    );
    addTearDown(container.dispose);

    await _waitForReady(container);

    final controller = container.read(coloringControllerProvider.notifier);
    final updates = <String, Color>{
      'region-bow-center': Colors.red,
      'region-bow-left': Colors.blue,
      'region-heart-center': Colors.green,
      'region-paw-left': Colors.orange,
      'region-star-01': Colors.purple,
    };

    for (final entry in updates.entries) {
      controller.selectColor(entry.value);
      controller.fillRegion(entry.key);
    }

    final state = container.read(coloringControllerProvider);
    for (final entry in updates.entries) {
      expect(state.regionColors[entry.key]?.toARGB32(), entry.value.toARGB32());
    }
  });

  test('Lovely Kitten resolves via SvgColoringRenderer in registry', () {
    final renderer = ColoringRendererRegistry.resolve(sampleLovelyKittenPage);
    expect(renderer, isA<SvgColoringRenderer>());
  });

  test('Lovely Kitten representative region centers are hit-testable', () async {
    final parser = SvgColoringParser();
    const hitTester = SvgRegionHitTester();
    final svg = await rootBundle.loadString(sampleLovelyKittenPage.assetPath);

    final parsed = parser.parseAndValidate(svgXml: svg, page: sampleLovelyKittenPage);
    expect(parsed.isValid, isTrue);

    final asset = parsed.asset!;
    final paintSize = const Size(1133, 1388);

    for (final id in _expectedLovelyKittenRegionIds) {
      final region = asset.colorableById[id]!;
      final center = region.path.getBounds().center;
      final local = _viewBoxPointToLocal(
        point: center,
        viewBox: asset.viewBox,
        paintSize: paintSize,
      );

      final hit = hitTester.hitTest(
        localPosition: local,
        paintSize: paintSize,
        viewBox: asset.viewBox,
        regions: asset.colorableRegions,
      );

      expect(hit, id, reason: 'Expected center hit for $id');
    }
  });

  test('Lovely Kitten zoom/pan coordinate mapping supports hit testing', () async {
    final parser = SvgColoringParser();
    const hitTester = SvgRegionHitTester();
    final svg = await rootBundle.loadString(sampleLovelyKittenPage.assetPath);

    final parsed = parser.parseAndValidate(svgXml: svg, page: sampleLovelyKittenPage);
    final asset = parsed.asset!;

    final targetRegion = asset.colorableById['region-heart-center']!;
    final viewBoxPoint = targetRegion.path.getBounds().center;
    final paintSize = const Size(520, 640);
    final local = _viewBoxPointToLocal(
      point: viewBoxPoint,
      viewBox: asset.viewBox,
      paintSize: paintSize,
    );

    final mapped = hitTester.mapToViewBox(
      localPosition: local,
      paintSize: paintSize,
      viewBox: asset.viewBox,
    );

    expect(mapped, isNotNull);
    expect(mapped!.dx, closeTo(viewBoxPoint.dx, 0.8));
    expect(mapped.dy, closeTo(viewBoxPoint.dy, 0.8));

    final hit = hitTester.hitTest(
      localPosition: local,
      paintSize: paintSize,
      viewBox: asset.viewBox,
      regions: asset.colorableRegions,
    );
    expect(hit, 'region-heart-center');
  });

  test('Lovely Kitten persistence and restore works for five-region POC', () async {
    final pageRepository = _FakeRepository([sampleLovelyKittenPage]);
    final sessionRepository = _MemorySessionRepository();

    final first = _buildContainer(
      pageRepository: pageRepository,
      sessionRepository: sessionRepository,
    );

    await _waitForReady(first);
    final firstController = first.read(coloringControllerProvider.notifier);
    firstController.selectColor(Colors.purple);
    firstController.fillRegion('region-heart-center');
    firstController.selectColor(Colors.yellow);
    firstController.fillRegion('region-star-01');
    await firstController.waitForPendingPersistence();
    first.dispose();

    final second = _buildContainer(
      pageRepository: pageRepository,
      sessionRepository: sessionRepository,
    );
    addTearDown(second.dispose);

    final restored = await _waitForReady(second);
    expect(restored.regionColors['region-heart-center']?.toARGB32(), Colors.purple.toARGB32());
    expect(restored.regionColors['region-star-01']?.toARGB32(), Colors.yellow.toARGB32());
  });

  test('My Creations progress works for five-region Lovely Kitten POC', () async {
    final sessionRepository = _MemorySessionRepository();
    sessionRepository.sessions['lovely-kitten'] = ColoringSession(
      pageId: 'lovely-kitten',
      regionColors: {
        'region-bow-center': Colors.red.toARGB32(),
        'region-paw-left': Colors.blue.toARGB32(),
      },
      schemaVersion: ColoringSession.currentSchemaVersion,
      lastUpdatedAtEpochMs: 100,
    );

    final container = _buildContainer(
      pageRepository: _FakeRepository([sampleLovelyKittenPage]),
      sessionRepository: sessionRepository,
    );
    addTearDown(container.dispose);

    final items = await container.read(myCreationsProvider.future);

    expect(items.length, 1);
    expect(items.single.pageId, 'lovely-kitten');
    expect(items.single.totalRegionCount, 5);
    expect(items.single.coloredRegionCount, 2);
  });

  test('switching between Lovely Kitten and Happy Cat does not leak region state', () async {
    final sessionRepository = _MemorySessionRepository();
    final pageRepository = _FakeRepository([
      sampleLovelyKittenPage,
      sampleHappyCatPage,
    ]);

    final container = _buildContainer(
      pageRepository: pageRepository,
      sessionRepository: sessionRepository,
      initialPageId: 'lovely-kitten',
    );
    addTearDown(container.dispose);

    await _waitForReady(container);

    final controller = container.read(coloringControllerProvider.notifier);
    controller.selectColor(Colors.red);
    controller.fillRegion('region-bow-left');

    await controller.loadPageById('happy-cat');
    var state = container.read(coloringControllerProvider);
    expect(state.page?.id, 'happy-cat');
    expect(state.regionColors.containsKey('region-bow-left'), isFalse);

    await controller.loadPageById('lovely-kitten');
    state = container.read(coloringControllerProvider);
    expect(state.page?.id, 'lovely-kitten');
    expect(state.regionColors.containsKey('cat-body'), isFalse);
  });
}
