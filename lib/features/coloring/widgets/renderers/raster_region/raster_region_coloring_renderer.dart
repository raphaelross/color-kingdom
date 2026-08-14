import 'dart:async';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../models/coloring_page.dart';
import '../../coloring_renderer.dart';
import 'raster_region_hit_tester.dart';

class RasterRegionColoringRenderer extends ColoringRenderer {
  RasterRegionColoringRenderer({
    AssetBundle? assetBundle,
    RasterRegionHitTester? hitTester,
  })  : _assetBundle = assetBundle ?? rootBundle,
        _hitTester = hitTester ?? const RasterRegionHitTester();

  static final Map<String, Future<_RasterRuntimeData>> _cache =
      <String, Future<_RasterRuntimeData>>{};

  final AssetBundle _assetBundle;
  final RasterRegionHitTester _hitTester;

  @visibleForTesting
  static Map<String, Uint32List> buildRegionPixelsForTesting({
    required int width,
    required int height,
    required Uint8List rgbaBytes,
    required Map<int, String> colorToRegionId,
  }) {
    return _buildRegionPixels(
      width: width,
      height: height,
      rgbaBytes: rgbaBytes,
      colorToRegionId: colorToRegionId,
    );
  }

  @visibleForTesting
  static void paintRegionColorIntoBuffer({
    required Uint8List buffer,
    required Uint32List pixelOffsets,
    required Color color,
  }) {
    final argb = color.toARGB32();
    final a = (argb >> 24) & 0xFF;
    final r = (argb >> 16) & 0xFF;
    final g = (argb >> 8) & 0xFF;
    final b = argb & 0xFF;

    for (final offset in pixelOffsets) {
      buffer[offset] = r;
      buffer[offset + 1] = g;
      buffer[offset + 2] = b;
      buffer[offset + 3] = a;
    }
  }

  @visibleForTesting
  static List<int> sampleRgbaAtOffset({
    required Uint8List buffer,
    required int byteOffset,
  }) {
    if (byteOffset < 0 || byteOffset + 3 >= buffer.length) {
      return const <int>[0, 0, 0, 0];
    }
    return <int>[
      buffer[byteOffset],
      buffer[byteOffset + 1],
      buffer[byteOffset + 2],
      buffer[byteOffset + 3],
    ];
  }

  @override
  String get id => 'raster-region-coloring-renderer';

  @override
  List<String> get requiredRegionIds => const <String>[];

  @override
  Widget build({
    required BuildContext context,
    required ColoringPage page,
    required Map<String, Color> regionColors,
    required Color selectedColor,
    required ValueChanged<String> onRegionTap,
  }) {
    return _RasterRegionRendererView(
      page: page,
      regionColors: regionColors,
      onRegionTap: onRegionTap,
      hitTester: _hitTester,
      loader: () => _loadData(page),
    );
  }

  Future<_RasterRuntimeData> _loadData(ColoringPage page) {
    final metadata = page.rasterRegionMetadata;
    if (metadata == null) {
      throw StateError('Raster metadata missing for page: ${page.id}');
    }

    final cacheKey =
        '${page.id}::${page.assetPath}::${metadata.regionMapAssetPath}::${metadata.regionFillMapAssetPath ?? metadata.regionMapAssetPath}::${metadata.contentVersion}';
    return _cache.putIfAbsent(cacheKey, () async {
      final pageInitWatch = Stopwatch()..start();
      final lineArtWatch = Stopwatch()..start();
      final lineArtData = await _assetBundle.load(page.assetPath);
      final lineArtImage = await _decodeUiImage(lineArtData.buffer.asUint8List());
      lineArtWatch.stop();

      final logicalMapWatch = Stopwatch()..start();
      final regionMapData = await _assetBundle.load(metadata.regionMapAssetPath);
      final regionMapImage = await _decodeUiImage(regionMapData.buffer.asUint8List());
      final regionMapBytes = await regionMapImage.toByteData(format: ui.ImageByteFormat.rawRgba);
      logicalMapWatch.stop();

      if (regionMapBytes == null) {
        throw StateError('Failed to decode region map bytes for page ${page.id}.');
      }

      final logicalRgbaBytes = regionMapBytes.buffer.asUint8List();

      final visualMapAssetPath = metadata.regionFillMapAssetPath ?? metadata.regionMapAssetPath;
      final visualMapWatch = Stopwatch()..start();
      final visualMapData = await _assetBundle.load(visualMapAssetPath);
      final visualMapImage = await _decodeUiImage(visualMapData.buffer.asUint8List());
      final visualMapBytes = await visualMapImage.toByteData(format: ui.ImageByteFormat.rawRgba);
      visualMapWatch.stop();
      if (visualMapBytes == null) {
        throw StateError('Failed to decode visual fill map bytes for page ${page.id}.');
      }

      final visualRgbaBytes = visualMapBytes.buffer.asUint8List();
      final colorToRegionId = <int, String>{
        for (final entry in metadata.regionMapEntries)
          _hitTester.encodeColorKey(
            entry.rgba[0],
            entry.rgba[1],
            entry.rgba[2],
            entry.rgba[3],
          ): entry.regionId,
      };

      final pixelBuildWatch = Stopwatch()..start();
      final pixelsByRegion = _buildRegionPixels(
        width: metadata.imageWidth,
        height: metadata.imageHeight,
        rgbaBytes: visualRgbaBytes,
        colorToRegionId: colorToRegionId,
      );
      pixelBuildWatch.stop();
      pageInitWatch.stop();

      assert(() {
        if (kDebugMode) {
          debugPrint(
            'RasterRegionColoringRenderer loaded ${page.id} '
            'lineArt=${lineArtWatch.elapsedMilliseconds}ms '
            'logicalMap=${logicalMapWatch.elapsedMilliseconds}ms '
            'visualMap=${visualMapWatch.elapsedMilliseconds}ms '
            'pixelIndex=${pixelBuildWatch.elapsedMilliseconds}ms '
            'total=${pageInitWatch.elapsedMilliseconds}ms '
            'size=${metadata.imageWidth}x${metadata.imageHeight} '
            'regions=${metadata.regionMapEntries.length}',
          );
        }
        return true;
      }());

      return _RasterRuntimeData(
        width: metadata.imageWidth,
        height: metadata.imageHeight,
        lineArt: lineArtImage,
        regionMapRgbaBytes: logicalRgbaBytes,
        colorToRegionId: colorToRegionId,
        pixelsByRegion: pixelsByRegion,
      );
    });
  }

  static Future<ui.Image> _decodeUiImage(Uint8List bytes) {
    final completer = Completer<ui.Image>();
    ui.decodeImageFromList(bytes, completer.complete);
    return completer.future;
  }

  static Map<String, Uint32List> _buildRegionPixels({
    required int width,
    required int height,
    required Uint8List rgbaBytes,
    required Map<int, String> colorToRegionId,
  }) {
    final temp = <String, List<int>>{};

    final pixelCount = width * height;
    for (var i = 0; i < pixelCount; i++) {
      final offset = i * 4;
      final key = ((rgbaBytes[offset] & 0xFF) << 24) |
          ((rgbaBytes[offset + 1] & 0xFF) << 16) |
          ((rgbaBytes[offset + 2] & 0xFF) << 8) |
          (rgbaBytes[offset + 3] & 0xFF);
      final regionId = colorToRegionId[key];
      if (regionId == null) {
        continue;
      }

      final bucket = temp.putIfAbsent(regionId, () => <int>[]);
      bucket.add(offset);
    }

    return {
      for (final entry in temp.entries) entry.key: Uint32List.fromList(entry.value),
    };
  }
}

class _RasterRuntimeData {
  const _RasterRuntimeData({
    required this.width,
    required this.height,
    required this.lineArt,
    required this.regionMapRgbaBytes,
    required this.colorToRegionId,
    required this.pixelsByRegion,
  });

  final int width;
  final int height;
  final ui.Image lineArt;
  final Uint8List regionMapRgbaBytes;
  final Map<int, String> colorToRegionId;
  final Map<String, Uint32List> pixelsByRegion;
}

class _RasterRegionRendererView extends StatefulWidget {
  const _RasterRegionRendererView({
    required this.page,
    required this.regionColors,
    required this.onRegionTap,
    required this.hitTester,
    required this.loader,
  });

  final ColoringPage page;
  final Map<String, Color> regionColors;
  final ValueChanged<String> onRegionTap;
  final RasterRegionHitTester hitTester;
  final Future<_RasterRuntimeData> Function() loader;

  @override
  State<_RasterRegionRendererView> createState() => _RasterRegionRendererViewState();
}

class _RasterRegionRendererViewState extends State<_RasterRegionRendererView> {
  late Future<_RasterRuntimeData> _loadFuture;
  _RasterRuntimeData? _runtimeData;
  Uint8List? _colorLayerBuffer;
  ui.Image? _colorLayerImage;
  Map<String, Color> _appliedRegionColors = <String, Color>{};
  int _renderVersion = 0;
  int _buildCount = 0;

  @override
  void dispose() {
    _colorLayerImage?.dispose();
    super.dispose();
  }

  @override
  void initState() {
    super.initState();
    _loadFuture = widget.loader();
  }

  @override
  void didUpdateWidget(covariant _RasterRegionRendererView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.page.id != widget.page.id || oldWidget.page.assetPath != widget.page.assetPath) {
      _loadFuture = widget.loader();
      _runtimeData = null;
      _colorLayerBuffer = null;
      _colorLayerImage = null;
      _appliedRegionColors = <String, Color>{};
    }

    if (!mapEquals(oldWidget.regionColors, widget.regionColors)) {
      _syncColorLayer();
    }
  }

  @override
  Widget build(BuildContext context) {
    _buildCount += 1;
    assert(() {
      if (kDebugMode) {
        debugPrint(
          'Raster build #$_buildCount page=${widget.page.id} '
          'regionColors=${widget.regionColors.length}',
        );
      }
      return true;
    }());

    return FutureBuilder<_RasterRuntimeData>(
      future: _loadFuture,
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return const Center(child: CircularProgressIndicator(strokeWidth: 2));
        }

        final error = snapshot.error;
        if (error != null) {
          return _RasterDiagnostic(
            title: 'Raster asset load failed',
            details: '$error',
          );
        }

        final data = snapshot.data;
        if (data == null) {
          return const _RasterDiagnostic(
            title: 'Raster asset load failed',
            details: 'No raster data was loaded.',
          );
        }

        if (_runtimeData == null) {
          _runtimeData = data;
          _colorLayerBuffer = Uint8List(data.width * data.height * 4);
          _syncColorLayer(forceFullRebuild: true);
        }

        return LayoutBuilder(
          builder: (context, constraints) {
            final size = Size(constraints.maxWidth, constraints.maxHeight);

            return GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTapDown: (details) {
                final active = _runtimeData;
                if (active == null) {
                  return;
                }

                final tapWatch = Stopwatch()..start();
                final pixel = widget.hitTester.mapLocalToImagePixel(
                  localPosition: details.localPosition,
                  paintSize: size,
                  imageWidth: active.width,
                  imageHeight: active.height,
                );
                if (pixel == null) {
                  return;
                }

                final regionId = widget.hitTester.regionIdAtPixel(
                  x: pixel.x,
                  y: pixel.y,
                  imageWidth: active.width,
                  imageHeight: active.height,
                  rgbaBytes: active.regionMapRgbaBytes,
                  colorToRegionId: active.colorToRegionId,
                );

                tapWatch.stop();
                assert(() {
                  if (kDebugMode) {
                    debugPrint(
                      'Raster tap page=${widget.page.id} pixel=(${pixel.x},${pixel.y}) '
                      'regionId=${regionId ?? 'none'} lookup=${tapWatch.elapsedMicroseconds}us',
                    );
                  }
                  return true;
                }());

                if (regionId == null) {
                  return;
                }

                widget.onRegionTap(regionId);
              },
              child: RepaintBoundary(
                child: CustomPaint(
                  painter: _RasterRegionPainter(
                    lineArt: data.lineArt,
                    colorLayer: _colorLayerImage,
                    imageWidth: data.width,
                    imageHeight: data.height,
                  ),
                  size: size,
                ),
              ),
            );
          },
        );
      },
    );
  }

  Future<void> _syncColorLayer({
    bool forceFullRebuild = false,
  }) async {
    final active = _runtimeData;
    final buffer = _colorLayerBuffer;
    if (active == null || buffer == null) {
      return;
    }

    final changedRegionIds = <String>{};
    if (forceFullRebuild) {
      changedRegionIds.addAll(active.pixelsByRegion.keys);
    } else {
      final allKeys = <String>{}
        ..addAll(_appliedRegionColors.keys)
        ..addAll(widget.regionColors.keys);
      for (final regionId in allKeys) {
        if (_appliedRegionColors[regionId] != widget.regionColors[regionId]) {
          changedRegionIds.add(regionId);
        }
      }
    }

    if (changedRegionIds.isEmpty && _colorLayerImage != null) {
      return;
    }

    for (final regionId in changedRegionIds) {
      final offsets = active.pixelsByRegion[regionId];
      if (offsets == null || offsets.isEmpty) {
        assert(() {
          if (kDebugMode) {
            debugPrint('Raster color sync region=$regionId has no cached pixel offsets');
          }
          return true;
        }());
        continue;
      }

      final color = widget.regionColors[regionId] ?? Colors.transparent;
      final firstOffset = offsets.first;
      final beforePixel = RasterRegionColoringRenderer.sampleRgbaAtOffset(
        buffer: buffer,
        byteOffset: firstOffset,
      );
      RasterRegionColoringRenderer.paintRegionColorIntoBuffer(
        buffer: buffer,
        pixelOffsets: offsets,
        color: color,
      );
      final afterPixel = RasterRegionColoringRenderer.sampleRgbaAtOffset(
        buffer: buffer,
        byteOffset: firstOffset,
      );
      assert(() {
        if (kDebugMode) {
          debugPrint(
            'Raster color sync region=$regionId pixels=${offsets.length} '
            'color=0x${color.toARGB32().toRadixString(16).padLeft(8, '0')} '
            'sampleBefore=$beforePixel sampleAfter=$afterPixel',
          );
        }
        return true;
      }());
    }

    _appliedRegionColors = Map<String, Color>.from(widget.regionColors);
    final nextVersion = ++_renderVersion;
    final image = await _decodeColorLayer(
      rgba: buffer,
      width: active.width,
      height: active.height,
    );

    if (!mounted || nextVersion != _renderVersion) {
      image.dispose();
      return;
    }

    setState(() {
      _colorLayerImage?.dispose();
      _colorLayerImage = image;
    });

    assert(() {
      if (kDebugMode) {
        debugPrint(
          'Raster color layer image refreshed page=${widget.page.id} '
          'changedRegions=${changedRegionIds.length} renderVersion=$_renderVersion',
        );
      }
      return true;
    }());
  }

  Future<ui.Image> _decodeColorLayer({
    required Uint8List rgba,
    required int width,
    required int height,
  }) {
    final completer = Completer<ui.Image>();
    ui.decodeImageFromPixels(
      rgba,
      width,
      height,
      ui.PixelFormat.rgba8888,
      completer.complete,
    );
    return completer.future;
  }
}

class _RasterRegionPainter extends CustomPainter {
  const _RasterRegionPainter({
    required this.lineArt,
    required this.colorLayer,
    required this.imageWidth,
    required this.imageHeight,
  });

  final ui.Image lineArt;
  final ui.Image? colorLayer;
  final int imageWidth;
  final int imageHeight;

  @override
  void paint(Canvas canvas, Size size) {
    final srcRect = Rect.fromLTWH(0, 0, imageWidth.toDouble(), imageHeight.toDouble());

    final scaleX = size.width / imageWidth;
    final scaleY = size.height / imageHeight;
    final scale = scaleX < scaleY ? scaleX : scaleY;

    final drawWidth = imageWidth * scale;
    final drawHeight = imageHeight * scale;
    final dstRect = Rect.fromLTWH(
      (size.width - drawWidth) / 2,
      (size.height - drawHeight) / 2,
      drawWidth,
      drawHeight,
    );

    final colorLayerImage = colorLayer;
    if (colorLayerImage != null) {
      canvas.drawImageRect(colorLayerImage, srcRect, dstRect, Paint());
    }
    canvas.drawImageRect(lineArt, srcRect, dstRect, Paint());
  }

  @override
  bool shouldRepaint(covariant _RasterRegionPainter oldDelegate) {
    return oldDelegate.lineArt != lineArt ||
        oldDelegate.colorLayer != colorLayer ||
        oldDelegate.imageWidth != imageWidth ||
        oldDelegate.imageHeight != imageHeight;
  }
}

class _RasterDiagnostic extends StatelessWidget {
  const _RasterDiagnostic({
    required this.title,
    required this.details,
  });

  final String title;
  final String details;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(24),
      child: SingleChildScrollView(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.warning_amber_rounded, size: 40),
            const SizedBox(height: 12),
            Text(
              title,
              style: Theme.of(context).textTheme.titleLarge,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 12),
            Text(
              details,
              style: Theme.of(context).textTheme.bodyMedium,
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}
