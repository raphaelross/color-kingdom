import 'package:flutter/material.dart';
import 'package:path_drawing/path_drawing.dart';
import 'package:xml/xml.dart';

import '../../../models/coloring_page.dart';
import 'svg_coloring_models.dart';

class SvgColoringParser {
  SvgColoringParser();

  SvgColoringLoadResult parseAndValidate({
    required String svgXml,
    required ColoringPage page,
  }) {
    try {
      final document = XmlDocument.parse(svgXml);
      final svgRoot = document.rootElement;
      if (svgRoot.name.local != 'svg') {
        return SvgColoringLoadResult.invalid(
          validation: const SvgAssetValidationResult(
            isValid: false,
            errorMessage: 'Root element is not <svg>.',
          ),
        );
      }

      final viewBox = _parseViewBox(svgRoot);
      if (viewBox == null) {
        return SvgColoringLoadResult.invalid(
          validation: const SvgAssetValidationResult(
            isValid: false,
            errorMessage: 'SVG viewBox is missing or invalid.',
          ),
        );
      }

      final drawElements = <SvgDrawElement>[];
      final colorableRegions = <SvgColorableRegion>[];
      final metadataErrors = <String>[];
      final duplicateIds = <String>[];
      final seenIds = <String>{};
      var drawOrder = 0;

      const rootStyle = SvgPaintStyle(
        fill: null,
        stroke: null,
        strokeWidth: 1,
      );

      void walk(
        XmlElement element,
        String? inheritedRole,
        SvgPaintStyle inheritedStyle,
      ) {
        final elementRole = element.getAttribute('data-role') ?? inheritedRole;
        final elementStyle = _parseStyle(element, inherited: inheritedStyle);
        final isPath = element.name.local == 'path';
        if (isPath) {
          final roleText = elementRole;
          if (roleText == null) {
            metadataErrors.add('Path missing data-role attribute.');
          } else if (roleText != 'colorable' && roleText != 'static') {
            metadataErrors.add('Invalid data-role "$roleText".');
          }

          final d = element.getAttribute('d');
          if (d != null && d.trim().isNotEmpty && roleText != null) {
            try {
              final path = parseSvgPathData(d);
              final style = elementStyle;
              final regionId = element.getAttribute('id');
              final role = roleText == 'colorable'
                  ? SvgElementRole.colorable
                  : SvgElementRole.staticElement;

              drawElements.add(
                SvgDrawElement(
                  path: path,
                  role: role,
                  style: style,
                  regionId: regionId,
                  drawOrder: drawOrder++,
                ),
              );

              if (role == SvgElementRole.colorable) {
                if (regionId == null || regionId.isEmpty) {
                  metadataErrors.add('Colorable path missing id attribute.');
                } else {
                  if (seenIds.contains(regionId)) {
                    duplicateIds.add(regionId);
                  }
                  seenIds.add(regionId);
                }

                colorableRegions.add(
                  SvgColorableRegion(
                    id: regionId ?? '',
                    path: path,
                    style: style,
                    drawOrder: drawOrder - 1,
                    name: element.getAttribute('data-region-name'),
                  ),
                );
              }
            } catch (_) {
              metadataErrors.add('Invalid path geometry in element id="${element.getAttribute('id') ?? 'unknown'}".');
            }
          }
        }

        for (final child in element.childElements) {
          walk(child, elementRole, elementStyle);
        }
      }

      walk(svgRoot, svgRoot.getAttribute('data-role'), rootStyle);

      final nonEmptyColorable = colorableRegions.where((r) => r.id.isNotEmpty).toList();
      final asset = SvgColoringAsset(
        viewBox: viewBox,
        drawElements: drawElements,
        colorableRegions: nonEmptyColorable,
      );

      final modelIds = page.regions.map((region) => region.id).toSet();
      final svgIds = nonEmptyColorable.map((region) => region.id).toSet();

      final missingModelIds = modelIds.difference(svgIds).toList()..sort();
      final unexpectedSvgIds = svgIds.difference(modelIds).toList()..sort();

      final isValid = missingModelIds.isEmpty &&
          unexpectedSvgIds.isEmpty &&
          duplicateIds.isEmpty &&
          metadataErrors.isEmpty;

      if (!isValid) {
        return SvgColoringLoadResult.invalid(
          validation: SvgAssetValidationResult(
            isValid: false,
            errorMessage: 'SVG region validation failed.',
            missingModelRegionIds: missingModelIds,
            unexpectedSvgRegionIds: unexpectedSvgIds,
            duplicateSvgRegionIds: duplicateIds,
            metadataErrors: metadataErrors,
          ),
        );
      }

      return SvgColoringLoadResult.valid(asset);
    } catch (error) {
      return SvgColoringLoadResult.invalid(
        validation: SvgAssetValidationResult(
          isValid: false,
          errorMessage: 'Failed to parse SVG: $error',
        ),
      );
    }
  }

  Rect? _parseViewBox(XmlElement svgRoot) {
    final viewBoxRaw = svgRoot.getAttribute('viewBox');
    if (viewBoxRaw == null) {
      return null;
    }

    final parts = viewBoxRaw
        .split(RegExp(r'[\s,]+'))
        .where((part) => part.isNotEmpty)
        .toList();
    if (parts.length != 4) {
      return null;
    }

    final minX = double.tryParse(parts[0]);
    final minY = double.tryParse(parts[1]);
    final width = double.tryParse(parts[2]);
    final height = double.tryParse(parts[3]);

    if (minX == null || minY == null || width == null || height == null) {
      return null;
    }
    if (width <= 0 || height <= 0) {
      return null;
    }

    return Rect.fromLTWH(minX, minY, width, height);
  }

  SvgPaintStyle _parseStyle(
    XmlElement element, {
    required SvgPaintStyle inherited,
  }) {
    final styleMap = _parseStyleAttribute(element.getAttribute('style'));

    final fillRaw = element.getAttribute('fill') ?? styleMap['fill'];
    final strokeRaw = element.getAttribute('stroke') ?? styleMap['stroke'];

    final fill = fillRaw == null ? inherited.fill : _parseColor(fillRaw);
    final stroke = strokeRaw == null ? inherited.stroke : _parseColor(strokeRaw);

    final strokeWidthRaw = element.getAttribute('stroke-width') ?? styleMap['stroke-width'];
    final strokeWidth = strokeWidthRaw == null
        ? inherited.strokeWidth
        : double.tryParse(strokeWidthRaw.replaceAll('px', '')) ?? inherited.strokeWidth;

    return SvgPaintStyle(
      fill: fill,
      stroke: stroke,
      strokeWidth: strokeWidth,
    );
  }

  Map<String, String> _parseStyleAttribute(String? styleRaw) {
    if (styleRaw == null || styleRaw.trim().isEmpty) {
      return const {};
    }

    final out = <String, String>{};
    final entries = styleRaw.split(';');
    for (final entry in entries) {
      final pair = entry.split(':');
      if (pair.length != 2) {
        continue;
      }
      out[pair[0].trim()] = pair[1].trim();
    }
    return out;
  }

  Color? _parseColor(String? value) {
    if (value == null) {
      return null;
    }

    final normalized = value.trim().toLowerCase();
    if (normalized.isEmpty || normalized == 'none' || normalized == 'transparent') {
      return Colors.transparent;
    }

    if (normalized.startsWith('#')) {
      final hex = normalized.substring(1);
      if (hex.length == 3) {
        final r = hex[0] * 2;
        final g = hex[1] * 2;
        final b = hex[2] * 2;
        final full = 'ff$r$g$b';
        return Color(int.parse(full, radix: 16));
      }
      if (hex.length == 6) {
        return Color(int.parse('ff$hex', radix: 16));
      }
      if (hex.length == 8) {
        return Color(int.parse(hex, radix: 16));
      }
    }

    if (normalized.startsWith('rgb(') && normalized.endsWith(')')) {
      final values = normalized
          .substring(4, normalized.length - 1)
          .split(',')
          .map((part) => int.tryParse(part.trim()))
          .toList();
      if (values.length == 3 && values.every((value) => value != null)) {
        return Color.fromARGB(255, values[0]!, values[1]!, values[2]!);
      }
    }

    return null;
  }
}
