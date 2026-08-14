import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:color_kingdom/features/coloring/data/sample_coloring_pages.dart';
import 'package:color_kingdom/features/coloring/widgets/renderers/raster_region/raster_region_hit_tester.dart';

Future<ui.Image> _decodeImage(Uint8List bytes) {
  return () async {
    final codec = await ui.instantiateImageCodec(bytes);
    final frame = await codec.getNextFrame();
    return frame.image;
  }();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('region map loads and known region pixel maps to expected region id', () async {
    final page = sampleLovelyKittenRasterPocPage;
    final metadata = page.rasterRegionMetadata!;

    final bytes = await rootBundle.load(metadata.regionMapAssetPath);
    final image = await _decodeImage(bytes.buffer.asUint8List());
    final byteData = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
    expect(byteData, isNotNull);

    final hitTester = const RasterRegionHitTester();
    final colorToRegionId = <int, String>{
      for (final entry in metadata.regionMapEntries)
        hitTester.encodeColorKey(entry.rgba[0], entry.rgba[1], entry.rgba[2], entry.rgba[3]):
            entry.regionId,
    };

    final regionId = hitTester.regionIdAtPixel(
      x: 367,
      y: 32,
      imageWidth: metadata.imageWidth,
      imageHeight: metadata.imageHeight,
      rgbaBytes: byteData!.buffer.asUint8List(),
      colorToRegionId: colorToRegionId,
    );

    expect(regionId, 'region-002');

    image.dispose();
  });

  test('exterior/background and line barrier pixels map to no region', () async {
    final page = sampleLovelyKittenRasterPocPage;
    final metadata = page.rasterRegionMetadata!;

    final bytes = await rootBundle.load(metadata.regionMapAssetPath);
    final image = await _decodeImage(bytes.buffer.asUint8List());
    final byteData = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
    expect(byteData, isNotNull);

    final hitTester = const RasterRegionHitTester();
    final colorToRegionId = <int, String>{
      for (final entry in metadata.regionMapEntries)
        hitTester.encodeColorKey(entry.rgba[0], entry.rgba[1], entry.rgba[2], entry.rgba[3]):
            entry.regionId,
    };

    final exterior = hitTester.regionIdAtPixel(
      x: 0,
      y: 0,
      imageWidth: metadata.imageWidth,
      imageHeight: metadata.imageHeight,
      rgbaBytes: byteData!.buffer.asUint8List(),
      colorToRegionId: colorToRegionId,
    );
    final line = hitTester.regionIdAtPixel(
      x: 367,
      y: 26,
      imageWidth: metadata.imageWidth,
      imageHeight: metadata.imageHeight,
      rgbaBytes: byteData.buffer.asUint8List(),
      colorToRegionId: colorToRegionId,
    );

    expect(exterior, isNull);
    expect(line, isNull);

    image.dispose();
  });

  test('coordinate mapping handles letterboxing and out-of-bounds safely', () {
    const hitTester = RasterRegionHitTester();

    final mapped = hitTester.mapLocalToImagePixel(
      localPosition: const Offset(162.0, 107.7),
      paintSize: const Size(500, 800),
      imageWidth: 1133,
      imageHeight: 1388,
    );
    expect(mapped, isNotNull);
    expect(mapped!.x, 367);
    expect(mapped.y, 31);

    final outside = hitTester.mapLocalToImagePixel(
      localPosition: const Offset(10, 10),
      paintSize: const Size(500, 800),
      imageWidth: 1133,
      imageHeight: 1388,
    );
    expect(outside, isNull);
  });
}
