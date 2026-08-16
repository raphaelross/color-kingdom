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

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('region mapping provides deterministic pixel offsets for tapped region', () async {
    final page = sampleLovelyKittenPage;
    final metadata = page.rasterRegionMetadata!;

    final regionMapAsset = await rootBundle.load(metadata.regionMapAssetPath);
    final regionMapImage = await _decodeImage(regionMapAsset.buffer.asUint8List());
    final regionMapBytes = await regionMapImage.toByteData(format: ui.ImageByteFormat.rawRgba);
    expect(regionMapBytes, isNotNull);

    final hitTester = const RasterRegionHitTester();
    final colorToRegionId = <int, String>{
      for (final entry in metadata.regionMapEntries)
        hitTester.encodeColorKey(entry.rgba[0], entry.rgba[1], entry.rgba[2], entry.rgba[3]):
            entry.regionId,
    };

    final pixelsByRegion = RasterRegionColoringRenderer.buildRegionPixelsForTesting(
      width: metadata.imageWidth,
      height: metadata.imageHeight,
      rgbaBytes: regionMapBytes!.buffer.asUint8List(),
      colorToRegionId: colorToRegionId,
    );

    final offsets = pixelsByRegion['region-002'];
    expect(offsets, isNotNull);
    expect(offsets!.isNotEmpty, isTrue, reason: 'region-002 offset count=${offsets.length}');

    regionMapImage.dispose();
  });

  test('color-layer byte mutation reflects fill/undo/redo/clear transitions', () async {
    final page = sampleLovelyKittenPage;
    final metadata = page.rasterRegionMetadata!;

    final regionMapAsset = await rootBundle.load(metadata.regionMapAssetPath);
    final regionMapImage = await _decodeImage(regionMapAsset.buffer.asUint8List());
    final regionMapBytes = await regionMapImage.toByteData(format: ui.ImageByteFormat.rawRgba);
    expect(regionMapBytes, isNotNull);

    final hitTester = const RasterRegionHitTester();
    final colorToRegionId = <int, String>{
      for (final entry in metadata.regionMapEntries)
        hitTester.encodeColorKey(entry.rgba[0], entry.rgba[1], entry.rgba[2], entry.rgba[3]):
            entry.regionId,
    };

    final pixelsByRegion = RasterRegionColoringRenderer.buildRegionPixelsForTesting(
      width: metadata.imageWidth,
      height: metadata.imageHeight,
      rgbaBytes: regionMapBytes!.buffer.asUint8List(),
      colorToRegionId: colorToRegionId,
    );

    final offsets = pixelsByRegion['region-002'];
    expect(offsets, isNotNull);
    expect(offsets!.isNotEmpty, isTrue);

    final buffer = Uint8List(metadata.imageWidth * metadata.imageHeight * 4);
    final sampleOffset = offsets.first;

    expect(
      RasterRegionColoringRenderer.sampleRgbaAtOffset(buffer: buffer, byteOffset: sampleOffset),
      <int>[0, 0, 0, 0],
    );

    RasterRegionColoringRenderer.paintRegionColorIntoBuffer(
      buffer: buffer,
      pixelOffsets: offsets,
      color: Colors.red,
    );
    final redValue = Colors.red.toARGB32();
    expect(
      RasterRegionColoringRenderer.sampleRgbaAtOffset(buffer: buffer, byteOffset: sampleOffset),
      <int>[
        (redValue >> 16) & 0xFF,
        (redValue >> 8) & 0xFF,
        redValue & 0xFF,
        (redValue >> 24) & 0xFF,
      ],
    );

    RasterRegionColoringRenderer.paintRegionColorIntoBuffer(
      buffer: buffer,
      pixelOffsets: offsets,
      color: Colors.transparent,
    );
    expect(
      RasterRegionColoringRenderer.sampleRgbaAtOffset(buffer: buffer, byteOffset: sampleOffset),
      <int>[0, 0, 0, 0],
    );

    RasterRegionColoringRenderer.paintRegionColorIntoBuffer(
      buffer: buffer,
      pixelOffsets: offsets,
      color: Colors.blue,
    );
    final blueValue = Colors.blue.toARGB32();
    expect(
      RasterRegionColoringRenderer.sampleRgbaAtOffset(buffer: buffer, byteOffset: sampleOffset),
      <int>[
        (blueValue >> 16) & 0xFF,
        (blueValue >> 8) & 0xFF,
        blueValue & 0xFF,
        (blueValue >> 24) & 0xFF,
      ],
    );

    RasterRegionColoringRenderer.paintRegionColorIntoBuffer(
      buffer: buffer,
      pixelOffsets: offsets,
      color: Colors.transparent,
    );
    expect(
      RasterRegionColoringRenderer.sampleRgbaAtOffset(buffer: buffer, byteOffset: sampleOffset),
      <int>[0, 0, 0, 0],
    );

    regionMapImage.dispose();
  });

  test('opaque source line art hides fill while transparent foreground preserves it', () async {
    final page = sampleLovelyKittenPage;
    final metadata = page.rasterRegionMetadata!;

    final regionMapAsset = await rootBundle.load(metadata.regionMapAssetPath);
    final regionMapImage = await _decodeImage(regionMapAsset.buffer.asUint8List());
    final regionMapBytes = await regionMapImage.toByteData(format: ui.ImageByteFormat.rawRgba);
    expect(regionMapBytes, isNotNull);

    final hitTester = const RasterRegionHitTester();
    final colorToRegionId = <int, String>{
      for (final entry in metadata.regionMapEntries)
        hitTester.encodeColorKey(entry.rgba[0], entry.rgba[1], entry.rgba[2], entry.rgba[3]):
            entry.regionId,
    };

    final pixelsByRegion = RasterRegionColoringRenderer.buildRegionPixelsForTesting(
      width: metadata.imageWidth,
      height: metadata.imageHeight,
      rgbaBytes: regionMapBytes!.buffer.asUint8List(),
      colorToRegionId: colorToRegionId,
    );

    final offsets = pixelsByRegion['region-002'];
    expect(offsets, isNotNull);
    expect(offsets!.isNotEmpty, isTrue);

    final sourceLineArtAsset = await rootBundle
        .load('assets/coloring_pages/animals/lovely_kitten_raster_poc/line_art.png');
    final sourceLineArt = await _decodeImage(sourceLineArtAsset.buffer.asUint8List());
    final sourceBytes = await sourceLineArt.toByteData(format: ui.ImageByteFormat.rawRgba);

    final transparentLineArtAsset = await rootBundle
        .load('assets/coloring_pages/animals/lovely_kitten_raster_poc/line_art_foreground.png');
    final transparentLineArt = await _decodeImage(transparentLineArtAsset.buffer.asUint8List());
    final transparentBytes =
        await transparentLineArt.toByteData(format: ui.ImageByteFormat.rawRgba);

    expect(sourceBytes, isNotNull);
    expect(transparentBytes, isNotNull);

    int? sampleByteOffset;
    for (final candidateOffset in offsets) {
      final sourceTopCandidate = RasterRegionColoringRenderer.sampleRgbaAtOffset(
        buffer: sourceBytes!.buffer.asUint8List(),
        byteOffset: candidateOffset,
      );
      final transparentTopCandidate = RasterRegionColoringRenderer.sampleRgbaAtOffset(
        buffer: transparentBytes!.buffer.asUint8List(),
        byteOffset: candidateOffset,
      );

      final sourceLooksWhite = sourceTopCandidate[3] == 255 &&
          sourceTopCandidate[0] > 245 &&
          sourceTopCandidate[1] > 245 &&
          sourceTopCandidate[2] > 245;
      final transparentCleared = transparentTopCandidate[3] == 0;
      if (sourceLooksWhite && transparentCleared) {
        sampleByteOffset = candidateOffset;
        break;
      }
    }

    expect(sampleByteOffset, isNotNull,
        reason: 'Expected at least one region-002 pixel to be white in source and transparent in foreground');

    final sourceTop = RasterRegionColoringRenderer.sampleRgbaAtOffset(
      buffer: sourceBytes!.buffer.asUint8List(),
      byteOffset: sampleByteOffset!,
    );
    final transparentTop = RasterRegionColoringRenderer.sampleRgbaAtOffset(
      buffer: transparentBytes!.buffer.asUint8List(),
      byteOffset: sampleByteOffset,
    );

    expect(sourceTop[3], 255, reason: 'source top alpha should be opaque at region sample');
    expect(sourceTop[0] > 245 && sourceTop[1] > 245 && sourceTop[2] > 245, isTrue,
        reason: 'source top pixel should be near white at region sample');

    expect(transparentTop[3], 0,
        reason: 'transparent foreground should not hide fill at region sample');

    sourceLineArt.dispose();
    transparentLineArt.dispose();
    regionMapImage.dispose();
  });
}
