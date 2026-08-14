import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:color_kingdom/features/coloring/data/sample_coloring_pages.dart';
import 'package:color_kingdom/features/coloring/models/coloring_page.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('raster POC page metadata is configured and deterministic', () {
    final page = sampleLovelyKittenRasterPocPage;
    final metadata = page.rasterRegionMetadata;

    expect(page.rendererType, ColoringRendererType.rasterRegion);
    expect(
      page.assetPath,
      'assets/coloring_pages/animals/lovely_kitten_raster_poc/line_art_foreground.png',
    );
    expect(metadata, isNotNull);
    expect(metadata!.regionMapAssetPath,
        'assets/coloring_pages/animals/lovely_kitten_raster_poc/region_map.png');
    expect(metadata.regionFillMapAssetPath,
      'assets/coloring_pages/animals/lovely_kitten_raster_poc/region_fill_map.png');
    expect(metadata.metadataAssetPath,
        'assets/coloring_pages/animals/lovely_kitten_raster_poc/metadata_children_detailed.json');
    expect(metadata.contentVersion, 'phase2c-tuned-children-detailed-v1');
    expect(metadata.imageWidth, 1133);
    expect(metadata.imageHeight, 1388);
    expect(metadata.regionMapEntries.length, 147);
    expect(page.regions.length, 147);
  });

  testWidgets('metadata asset loads and matches configured map entries', (tester) async {
    final page = sampleLovelyKittenRasterPocPage;
    final metadata = page.rasterRegionMetadata!;

    final rawJson =
        await rootBundle.loadString(metadata.metadataAssetPath!);
    final decoded = jsonDecode(rawJson) as Map<String, dynamic>;
    final regions = decoded['regions'] as List<dynamic>;

    expect(decoded['pageId'], page.id);
    expect(decoded['profile'], 'childrenDetailed');
    expect(decoded['regionCount'], 147);
    expect(
      decoded['lineArtAssetPath'],
      'assets/coloring_pages/animals/lovely_kitten_raster_poc/line_art_foreground.png',
    );
    expect(
      decoded['regionFillMapAssetPath'],
      'assets/coloring_pages/animals/lovely_kitten_raster_poc/region_fill_map.png',
    );
    final visualFillMap = decoded['visualFillMap'] as Map<String, dynamic>;
    expect(visualFillMap['recommendedExpansionPx'], 1);
    expect((visualFillMap['metricsByExpansion'] as Map<String, dynamic>).containsKey('0'), isTrue);
    expect((visualFillMap['metricsByExpansion'] as Map<String, dynamic>).containsKey('1'), isTrue);

    final qaArtifacts = decoded['qaArtifacts'] as Map<String, dynamic>;
    expect(qaArtifacts['haloBaseline0'], isNotNull);
    expect(qaArtifacts['haloExpansion1'], isNotNull);
    expect(qaArtifacts['haloDifference'], isNotNull);
    expect(regions.length, metadata.regionMapEntries.length);

    final firstRegion = regions.first as Map<String, dynamic>;
    expect(firstRegion['regionId'], metadata.regionMapEntries.first.regionId);
    expect(firstRegion['mapColorRgba'], metadata.regionMapEntries.first.rgba);
  });
}
