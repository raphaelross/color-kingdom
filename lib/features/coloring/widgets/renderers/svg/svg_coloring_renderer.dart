import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../models/coloring_page.dart';
import '../../coloring_renderer.dart';
import 'svg_coloring_models.dart';
import 'svg_coloring_parser.dart';
import 'svg_region_hit_tester.dart';

class SvgColoringRenderer extends ColoringRenderer {
  SvgColoringRenderer({
    AssetBundle? assetBundle,
    SvgColoringParser? parser,
    SvgRegionHitTester? hitTester,
  })  : _assetBundle = assetBundle ?? rootBundle,
        _parser = parser ?? SvgColoringParser(),
        _hitTester = hitTester ?? const SvgRegionHitTester();

  final AssetBundle _assetBundle;
  final SvgColoringParser _parser;
  final SvgRegionHitTester _hitTester;

  static final Map<String, Future<SvgColoringLoadResult>> _cache = {};

  @override
  String get id => 'svg-coloring-renderer';

  @override
  List<String> get requiredRegionIds => const [];

  @override
  Widget build({
    required BuildContext context,
    required ColoringPage page,
    required Map<String, Color> regionColors,
    required Color selectedColor,
    required ValueChanged<String> onRegionTap,
  }) {
    return _SvgColoringRendererView(
      page: page,
      regionColors: regionColors,
      selectedColor: selectedColor,
      onRegionTap: onRegionTap,
      parser: _parser,
      hitTester: _hitTester,
      loader: () => _loadAsset(page: page),
    );
  }

  Future<SvgColoringLoadResult> _loadAsset({
    required ColoringPage page,
  }) {
    final cacheKey = '${page.id}::${page.assetPath}';
    return _cache.putIfAbsent(cacheKey, () async {
      final svgXml = await _assetBundle.loadString(page.assetPath);
      final parsed = _parser.parseAndValidate(
        svgXml: svgXml,
        page: page,
      );
      return parsed;
    });
  }

  static Color resolveRegionFillColor({
    required SvgColorableRegion region,
    required Map<String, Color> regionColors,
  }) {
    final selected = regionColors[region.id] ?? Colors.transparent;
    if (selected.a > 0) {
      return selected;
    }
    return region.style.fill ?? Colors.transparent;
  }
}

class _SvgColoringRendererView extends StatefulWidget {
  const _SvgColoringRendererView({
    required this.page,
    required this.regionColors,
    required this.selectedColor,
    required this.onRegionTap,
    required this.parser,
    required this.hitTester,
    required this.loader,
  });

  final ColoringPage page;
  final Map<String, Color> regionColors;
  final Color selectedColor;
  final ValueChanged<String> onRegionTap;
  final SvgColoringParser parser;
  final SvgRegionHitTester hitTester;
  final Future<SvgColoringLoadResult> Function() loader;

  @override
  State<_SvgColoringRendererView> createState() => _SvgColoringRendererViewState();
}

class _SvgColoringRendererViewState extends State<_SvgColoringRendererView> {
  late Future<SvgColoringLoadResult> _loadFuture;

  @override
  void initState() {
    super.initState();
    _loadFuture = widget.loader();
  }

  @override
  void didUpdateWidget(covariant _SvgColoringRendererView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.page.assetPath != widget.page.assetPath || oldWidget.page.id != widget.page.id) {
      _loadFuture = widget.loader();
    }
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<SvgColoringLoadResult>(
      future: _loadFuture,
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return const Center(child: CircularProgressIndicator(strokeWidth: 2));
        }

        final result = snapshot.data;
        if (result == null) {
          return const _SvgDiagnostic(
            title: 'SVG load failed',
            details: 'No SVG data was loaded.',
          );
        }

        if (!result.isValid || result.asset == null) {
          return _SvgDiagnostic(
            title: 'SVG validation failed',
            details: result.validation.diagnosticsSummary(),
          );
        }

        final asset = result.asset!;

        return LayoutBuilder(
          builder: (context, constraints) {
            final size = Size(constraints.maxWidth, constraints.maxHeight);

            return GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTapDown: (details) {
                final regionId = widget.hitTester.hitTest(
                  localPosition: details.localPosition,
                  paintSize: size,
                  viewBox: asset.viewBox,
                  regions: asset.colorableRegions,
                );

                if (regionId != null && regionId.isNotEmpty) {
                  widget.onRegionTap(regionId);
                }
              },
              child: RepaintBoundary(
                child: CustomPaint(
                  painter: _SvgColoringPainter(
                    asset: asset,
                    regionColors: widget.regionColors,
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
}

class _SvgColoringPainter extends CustomPainter {
  const _SvgColoringPainter({
    required this.asset,
    required this.regionColors,
  });

  final SvgColoringAsset asset;
  final Map<String, Color> regionColors;

  @override
  void paint(Canvas canvas, Size size) {
    final scaleX = size.width / asset.viewBox.width;
    final scaleY = size.height / asset.viewBox.height;
    final scale = scaleX < scaleY ? scaleX : scaleY;

    final drawWidth = asset.viewBox.width * scale;
    final drawHeight = asset.viewBox.height * scale;
    final offsetX = (size.width - drawWidth) / 2;
    final offsetY = (size.height - drawHeight) / 2;

    canvas.save();
    canvas.translate(offsetX, offsetY);
    canvas.scale(scale, scale);
    canvas.translate(-asset.viewBox.left, -asset.viewBox.top);

    final ordered = [...asset.drawElements]..sort((a, b) => a.drawOrder.compareTo(b.drawOrder));

    for (final element in ordered) {
      if (element.role == SvgElementRole.colorable && element.regionId != null) {
        final region = asset.colorableById[element.regionId!];
        if (region == null) {
          continue;
        }

        final fillColor = SvgColoringRenderer.resolveRegionFillColor(
          region: region,
          regionColors: regionColors,
        );

        if (fillColor.a > 0) {
          final fillPaint = Paint()
            ..style = PaintingStyle.fill
            ..color = fillColor;
          canvas.drawPath(region.path, fillPaint);
        }

        final strokeColor = region.style.stroke;
        if (strokeColor != null && strokeColor.a > 0) {
          final strokePaint = Paint()
            ..style = PaintingStyle.stroke
            ..strokeJoin = StrokeJoin.round
            ..strokeCap = StrokeCap.round
            ..strokeWidth = region.style.strokeWidth
            ..color = strokeColor;
          canvas.drawPath(region.path, strokePaint);
        }

        continue;
      }

      final fill = element.style.fill;
      if (fill != null && fill.a > 0) {
        final paint = Paint()
          ..style = PaintingStyle.fill
          ..color = fill;
        canvas.drawPath(element.path, paint);
      }

      final stroke = element.style.stroke;
      if (stroke != null && stroke.a > 0) {
        final paint = Paint()
          ..style = PaintingStyle.stroke
          ..strokeJoin = StrokeJoin.round
          ..strokeCap = StrokeCap.round
          ..strokeWidth = element.style.strokeWidth
          ..color = stroke;
        canvas.drawPath(element.path, paint);
      }
    }

    canvas.restore();
  }
  @override
  bool shouldRepaint(covariant _SvgColoringPainter oldDelegate) {
    if (!identical(oldDelegate.asset, asset)) {
      return true;
    }

    if (oldDelegate.regionColors.length != regionColors.length) {
      return true;
    }

    for (final entry in regionColors.entries) {
      if (oldDelegate.regionColors[entry.key] != entry.value) {
        return true;
      }
    }
    return false;
  }
}

class _SvgDiagnostic extends StatelessWidget {
  const _SvgDiagnostic({
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
