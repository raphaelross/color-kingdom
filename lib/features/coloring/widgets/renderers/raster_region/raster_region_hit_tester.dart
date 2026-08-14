import 'dart:typed_data';

import 'package:flutter/material.dart';

@immutable
class RasterImagePixel {
  const RasterImagePixel({
    required this.x,
    required this.y,
  });

  final int x;
  final int y;
}

class RasterRegionHitTester {
  const RasterRegionHitTester();

  RasterImagePixel? mapLocalToImagePixel({
    required Offset localPosition,
    required Size paintSize,
    required int imageWidth,
    required int imageHeight,
  }) {
    if (paintSize.width <= 0 || paintSize.height <= 0) {
      return null;
    }

    final scaleX = paintSize.width / imageWidth;
    final scaleY = paintSize.height / imageHeight;
    final scale = scaleX < scaleY ? scaleX : scaleY;

    final drawWidth = imageWidth * scale;
    final drawHeight = imageHeight * scale;
    final offsetX = (paintSize.width - drawWidth) / 2;
    final offsetY = (paintSize.height - drawHeight) / 2;

    final localX = localPosition.dx;
    final localY = localPosition.dy;
    if (localX < offsetX || localY < offsetY) {
      return null;
    }
    if (localX >= offsetX + drawWidth || localY >= offsetY + drawHeight) {
      return null;
    }

    final pixelX = ((localX - offsetX) / scale).floor();
    final pixelY = ((localY - offsetY) / scale).floor();

    if (pixelX < 0 || pixelY < 0 || pixelX >= imageWidth || pixelY >= imageHeight) {
      return null;
    }

    return RasterImagePixel(x: pixelX, y: pixelY);
  }

  String? regionIdAtPixel({
    required int x,
    required int y,
    required int imageWidth,
    required int imageHeight,
    required Uint8List rgbaBytes,
    required Map<int, String> colorToRegionId,
  }) {
    if (x < 0 || y < 0 || x >= imageWidth || y >= imageHeight) {
      return null;
    }

    final offset = (y * imageWidth + x) * 4;
    if (offset + 3 >= rgbaBytes.length) {
      return null;
    }

    final colorKey = encodeColorKey(
      rgbaBytes[offset],
      rgbaBytes[offset + 1],
      rgbaBytes[offset + 2],
      rgbaBytes[offset + 3],
    );

    return colorToRegionId[colorKey];
  }

  int encodeColorKey(int r, int g, int b, int a) {
    return ((r & 0xFF) << 24) |
        ((g & 0xFF) << 16) |
        ((b & 0xFF) << 8) |
        (a & 0xFF);
  }
}
