import 'dart:convert';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:color_kingdom/features/coloring/data/sample_coloring_pages.dart';
import 'package:color_kingdom/features/coloring/widgets/renderers/raster_region/raster_region_coloring_renderer.dart';
import 'package:color_kingdom/features/coloring/widgets/renderers/raster_region/raster_region_hit_tester.dart';

Future<ui.Image> _decodeImage(Uint8List bytes) async {
  final codec = await ui.instantiateImageCodec(bytes);
  final frame = await codec.getNextFrame();
  return frame.image;
}

int _colorKey(Uint8List rgba, int pixelIndex) {
  final offset = pixelIndex * 4;
  return ((rgba[offset] & 0xFF) << 24) |
      ((rgba[offset + 1] & 0xFF) << 16) |
      ((rgba[offset + 2] & 0xFF) << 8) |
      (rgba[offset + 3] & 0xFF);
}

List<int> _compositeOverWhite({
  required List<int> underRgba,
  required List<int> foregroundRgba,
}) {
  final underA = underRgba[3] / 255.0;
  final underR = underRgba[0] * underA + 255 * (1.0 - underA);
  final underG = underRgba[1] * underA + 255 * (1.0 - underA);
  final underB = underRgba[2] * underA + 255 * (1.0 - underA);

  final fgA = foregroundRgba[3] / 255.0;
  final outR = (foregroundRgba[0] * fgA) + (underR * (1.0 - fgA));
  final outG = (foregroundRgba[1] * fgA) + (underG * (1.0 - fgA));
  final outB = (foregroundRgba[2] * fgA) + (underB * (1.0 - fgA));

  return <int>[outR.round(), outG.round(), outB.round(), 255];
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('logical region map is preserved while visual fill map expands ownership', () async {
    final page = sampleLovelyKittenRasterPocPage;
    final metadata = page.rasterRegionMetadata!;

    final logicalAsset = await rootBundle.load(metadata.regionMapAssetPath);
    final logicalImage = await _decodeImage(logicalAsset.buffer.asUint8List());
    final logicalBytes = await logicalImage.toByteData(format: ui.ImageByteFormat.rawRgba);
    expect(logicalBytes, isNotNull);

    final fillAsset = await rootBundle.load(metadata.regionFillMapAssetPath!);
    final fillImage = await _decodeImage(fillAsset.buffer.asUint8List());
    final fillBytes = await fillImage.toByteData(format: ui.ImageByteFormat.rawRgba);
    expect(fillBytes, isNotNull);

    final logicalRgba = logicalBytes!.buffer.asUint8List();
    final fillRgba = fillBytes!.buffer.asUint8List();

    final hitTester = const RasterRegionHitTester();
    final colorToRegionId = <int, String>{
      for (final entry in metadata.regionMapEntries)
        hitTester.encodeColorKey(entry.rgba[0], entry.rgba[1], entry.rgba[2], entry.rgba[3]):
            entry.regionId,
    };

    int? sampleX;
    int? sampleY;
    String? sampleFillRegion;
    for (var y = 0; y < metadata.imageHeight && sampleX == null; y++) {
      for (var x = 0; x < metadata.imageWidth; x++) {
        final regionInLogical = hitTester.regionIdAtPixel(
          x: x,
          y: y,
          imageWidth: metadata.imageWidth,
          imageHeight: metadata.imageHeight,
          rgbaBytes: logicalRgba,
          colorToRegionId: colorToRegionId,
        );
        if (regionInLogical != null) {
          continue;
        }

        final regionInFill = hitTester.regionIdAtPixel(
          x: x,
          y: y,
          imageWidth: metadata.imageWidth,
          imageHeight: metadata.imageHeight,
          rgbaBytes: fillRgba,
          colorToRegionId: colorToRegionId,
        );
        if (regionInFill == null) {
          continue;
        }

        sampleX = x;
        sampleY = y;
        sampleFillRegion = regionInFill;
        break;
      }
    }

    expect(sampleX, isNotNull,
        reason: 'Expected at least one pixel claimed by visual fill map but unowned in logical map');

    final logicalRegionAtSample = hitTester.regionIdAtPixel(
      x: sampleX!,
      y: sampleY!,
      imageWidth: metadata.imageWidth,
      imageHeight: metadata.imageHeight,
      rgbaBytes: logicalRgba,
      colorToRegionId: colorToRegionId,
    );
    final fillRegionAtSample = hitTester.regionIdAtPixel(
      x: sampleX,
      y: sampleY,
      imageWidth: metadata.imageWidth,
      imageHeight: metadata.imageHeight,
      rgbaBytes: fillRgba,
      colorToRegionId: colorToRegionId,
    );

    expect(logicalRegionAtSample, isNull,
        reason: 'Sample halo pixel must remain unassigned in logical map for hit testing');

    expect(fillRegionAtSample, sampleFillRegion,
        reason: 'Visual fill map should claim representative halo pixel');

    var logicalOwnedPixels = 0;
    for (var i = 0; i < metadata.imageWidth * metadata.imageHeight; i++) {
      final logicalKey = _colorKey(logicalRgba, i);
      final logicalRegion = colorToRegionId[logicalKey];
      if (logicalRegion == null) {
        continue;
      }
      logicalOwnedPixels += 1;

      final fillKey = _colorKey(fillRgba, i);
      final fillRegion = colorToRegionId[fillKey];
      expect(fillRegion, logicalRegion,
          reason: 'Visual fill map must not overwrite logical interior ownership');
    }
    expect(logicalOwnedPixels, greaterThan(0));

    logicalImage.dispose();
    fillImage.dispose();
  });

  test('expansion metrics remain bounded and deterministic for 0..4px', () async {
    final page = sampleLovelyKittenRasterPocPage;
    final metadata = page.rasterRegionMetadata!;

    final metadataJson = jsonDecode(await rootBundle.loadString(metadata.metadataAssetPath!))
        as Map<String, dynamic>;
    final visualFill = metadataJson['visualFillMap'] as Map<String, dynamic>;
    final metricsByExpansion = visualFill['metricsByExpansion'] as Map<String, dynamic>;

    expect(visualFill['recommendedExpansionPx'], 1);

    final m0 = metricsByExpansion['0'] as Map<String, dynamic>;
    final m1 = metricsByExpansion['1'] as Map<String, dynamic>;
    final m2 = metricsByExpansion['2'] as Map<String, dynamic>;
    final m3 = metricsByExpansion['3'] as Map<String, dynamic>;
    final m4 = metricsByExpansion['4'] as Map<String, dynamic>;

    expect(m0['addedPixels'], 0);

    expect((m1['addedPixels'] as int) > 0, isTrue);
    expect(m1['bleedRiskPixels'], 0);
    expect(m1['ambiguousPixels'], 164);

    expect((m1['addedPixels'] as int) < (m2['addedPixels'] as int), isTrue);
    expect((m2['addedPixels'] as int) < (m3['addedPixels'] as int), isTrue);
    expect((m3['addedPixels'] as int) < (m4['addedPixels'] as int), isTrue);

    expect(m4['bleedRiskPixels'], 0);

    final totalPixels = metadata.imageWidth * metadata.imageHeight;
    final addedRatio = (m1['addedPixels'] as int) / totalPixels;
    expect(addedRatio, lessThan(0.07), reason: 'Expansion should stay a narrow boundary band');
  });

  test('composited representative halo pixel is no longer white after visual fill', () async {
    final page = sampleLovelyKittenRasterPocPage;
    final metadata = page.rasterRegionMetadata!;

    final logicalAsset = await rootBundle.load(metadata.regionMapAssetPath);
    final logicalImage = await _decodeImage(logicalAsset.buffer.asUint8List());
    final logicalBytes = await logicalImage.toByteData(format: ui.ImageByteFormat.rawRgba);
    expect(logicalBytes, isNotNull);

    final fillAsset = await rootBundle.load(metadata.regionFillMapAssetPath!);
    final fillImage = await _decodeImage(fillAsset.buffer.asUint8List());
    final fillBytes = await fillImage.toByteData(format: ui.ImageByteFormat.rawRgba);
    expect(fillBytes, isNotNull);

    final foregroundAsset = await rootBundle.load(page.assetPath);
    final foregroundImage = await _decodeImage(foregroundAsset.buffer.asUint8List());
    final foregroundBytes = await foregroundImage.toByteData(format: ui.ImageByteFormat.rawRgba);
    expect(foregroundBytes, isNotNull);

    final hitTester = const RasterRegionHitTester();
    final colorToRegionId = <int, String>{
      for (final entry in metadata.regionMapEntries)
        hitTester.encodeColorKey(entry.rgba[0], entry.rgba[1], entry.rgba[2], entry.rgba[3]):
            entry.regionId,
    };

    int? sampleX;
    int? sampleY;
    String? expectedRegionId;
    final logicalRgba = logicalBytes!.buffer.asUint8List();
    final fillRgba = fillBytes!.buffer.asUint8List();

    for (var y = 0; y < metadata.imageHeight && sampleX == null; y++) {
      for (var x = 0; x < metadata.imageWidth; x++) {
        final regionInLogical = hitTester.regionIdAtPixel(
          x: x,
          y: y,
          imageWidth: metadata.imageWidth,
          imageHeight: metadata.imageHeight,
          rgbaBytes: logicalRgba,
          colorToRegionId: colorToRegionId,
        );
        if (regionInLogical != null) {
          continue;
        }

        final regionInFill = hitTester.regionIdAtPixel(
          x: x,
          y: y,
          imageWidth: metadata.imageWidth,
          imageHeight: metadata.imageHeight,
          rgbaBytes: fillRgba,
          colorToRegionId: colorToRegionId,
        );
        if (regionInFill == null) {
          continue;
        }

        final offset = (y * metadata.imageWidth + x) * 4;
        final foregroundAlpha = foregroundBytes!.buffer.asUint8List()[offset + 3];
        if (foregroundAlpha == 0 || foregroundAlpha == 255) {
          continue;
        }

        sampleX = x;
        sampleY = y;
        expectedRegionId = regionInFill;
        break;
      }
    }

    if (sampleX == null) {
      for (var y = 0; y < metadata.imageHeight && sampleX == null; y++) {
        for (var x = 0; x < metadata.imageWidth; x++) {
          final regionInLogical = hitTester.regionIdAtPixel(
            x: x,
            y: y,
            imageWidth: metadata.imageWidth,
            imageHeight: metadata.imageHeight,
            rgbaBytes: logicalRgba,
            colorToRegionId: colorToRegionId,
          );
          if (regionInLogical != null) {
            continue;
          }

          final regionInFill = hitTester.regionIdAtPixel(
            x: x,
            y: y,
            imageWidth: metadata.imageWidth,
            imageHeight: metadata.imageHeight,
            rgbaBytes: fillRgba,
            colorToRegionId: colorToRegionId,
          );
          if (regionInFill == null) {
            continue;
          }

          sampleX = x;
          sampleY = y;
          expectedRegionId = regionInFill;
          break;
        }
      }
    }

    expect(sampleX, isNotNull);
    expect(expectedRegionId, isNotNull);

    final logicalPixels = RasterRegionColoringRenderer.buildRegionPixelsForTesting(
      width: metadata.imageWidth,
      height: metadata.imageHeight,
      rgbaBytes: logicalRgba,
      colorToRegionId: colorToRegionId,
    );
    final fillPixels = RasterRegionColoringRenderer.buildRegionPixelsForTesting(
      width: metadata.imageWidth,
      height: metadata.imageHeight,
      rgbaBytes: fillRgba,
      colorToRegionId: colorToRegionId,
    );

    final logicalBuffer = Uint8List(metadata.imageWidth * metadata.imageHeight * 4);
    final fillBuffer = Uint8List(metadata.imageWidth * metadata.imageHeight * 4);

    RasterRegionColoringRenderer.paintRegionColorIntoBuffer(
      buffer: logicalBuffer,
      pixelOffsets: logicalPixels[expectedRegionId!]!,
      color: Colors.red,
    );
    RasterRegionColoringRenderer.paintRegionColorIntoBuffer(
      buffer: fillBuffer,
      pixelOffsets: fillPixels[expectedRegionId]!,
      color: Colors.red,
    );

    final sampleOffset = (sampleY! * metadata.imageWidth + sampleX!) * 4;
    final baselineUnder = RasterRegionColoringRenderer.sampleRgbaAtOffset(
      buffer: logicalBuffer,
      byteOffset: sampleOffset,
    );
    final expandedUnder = RasterRegionColoringRenderer.sampleRgbaAtOffset(
      buffer: fillBuffer,
      byteOffset: sampleOffset,
    );
    final foregroundAtSample = RasterRegionColoringRenderer.sampleRgbaAtOffset(
      buffer: foregroundBytes!.buffer.asUint8List(),
      byteOffset: sampleOffset,
    );

    final baselineComposite = _compositeOverWhite(
      underRgba: baselineUnder,
      foregroundRgba: foregroundAtSample,
    );
    final expandedComposite = _compositeOverWhite(
      underRgba: expandedUnder,
      foregroundRgba: foregroundAtSample,
    );

    expect(baselineUnder[3], 0,
        reason: 'Baseline logical fill should not own representative halo sample pixel');
    expect(expandedUnder[3], 255,
        reason: 'Visual fill map should own representative halo sample pixel');

    expect(expandedComposite[0] > expandedComposite[1], isTrue,
        reason: 'Expanded composite should carry selected red fill tint at halo sample');
    expect(expandedComposite[1] < baselineComposite[1], isTrue,
        reason: 'Expanded composite should reduce gray/white halo channel intensity');

    logicalImage.dispose();
    fillImage.dispose();
    foregroundImage.dispose();
  });
}
