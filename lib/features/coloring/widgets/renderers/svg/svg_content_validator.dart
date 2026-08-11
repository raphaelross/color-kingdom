import 'package:flutter/material.dart';
import 'package:xml/xml.dart';

import '../../../models/coloring_page.dart';
import 'svg_coloring_parser.dart';

enum SvgValidationSeverity { error, warning }

@immutable
class SvgValidationIssue {
  const SvgValidationIssue({
    required this.severity,
    required this.code,
    required this.message,
  });

  final SvgValidationSeverity severity;
  final String code;
  final String message;
}

@immutable
class SvgContentValidationReport {
  const SvgContentValidationReport({
    required this.issues,
    required this.colorableRegionCount,
    required this.totalPathCount,
    required this.staticPathCount,
    required this.colorableRegionIds,
  });

  final List<SvgValidationIssue> issues;
  final int colorableRegionCount;
  final int totalPathCount;
  final int staticPathCount;
  final Set<String> colorableRegionIds;

  List<SvgValidationIssue> get errors =>
      issues.where((issue) => issue.severity == SvgValidationSeverity.error).toList(growable: false);

  List<SvgValidationIssue> get warnings =>
      issues.where((issue) => issue.severity == SvgValidationSeverity.warning).toList(growable: false);

  bool get isValid => errors.isEmpty;
}

class SvgContentValidator {
  SvgContentValidator({SvgColoringParser? parser}) : _parser = parser ?? SvgColoringParser();

  final SvgColoringParser _parser;

  static const Set<String> _unsupportedElements = {
    'circle',
    'ellipse',
    'rect',
    'polygon',
    'polyline',
    'line',
    'clippath',
    'mask',
  };

  SvgContentValidationReport validate({
    required String svgXml,
    required ColoringPage page,
    double minTapTargetWidth = 18,
    double minTapTargetHeight = 18,
  }) {
    final issues = <SvgValidationIssue>[];

    XmlDocument document;
    try {
      document = XmlDocument.parse(svgXml);
    } catch (error) {
      return SvgContentValidationReport(
        issues: [
          SvgValidationIssue(
            severity: SvgValidationSeverity.error,
            code: 'svg-parse-failed',
            message: 'Failed to parse SVG XML: $error',
          ),
        ],
        colorableRegionCount: 0,
        totalPathCount: 0,
        staticPathCount: 0,
        colorableRegionIds: const <String>{},
      );
    }

    final allElements = document.descendants.whereType<XmlElement>();
    final allPaths = allElements.where((element) => element.name.local == 'path').toList(growable: false);

    final idOwnerById = <String, String>{};
    final duplicateIds = <String>{};
    for (final element in allElements) {
      final id = element.getAttribute('id');
      if (id == null || id.trim().isEmpty) {
        continue;
      }

      final existingOwner = idOwnerById[id];
      if (existingOwner != null) {
        duplicateIds.add(id);
      } else {
        idOwnerById[id] = element.name.local;
      }
    }
    for (final duplicateId in duplicateIds) {
      issues.add(
        SvgValidationIssue(
          severity: SvgValidationSeverity.error,
          code: 'duplicate-id',
          message: 'Duplicate id attribute found: "$duplicateId".',
        ),
      );
    }

    for (final element in allElements) {
      final localName = element.name.local.toLowerCase();
      if (_unsupportedElements.contains(localName)) {
        issues.add(
          SvgValidationIssue(
            severity: SvgValidationSeverity.error,
            code: 'unsupported-element',
            message: 'Unsupported SVG element <${element.name.local}> detected.',
          ),
        );
      }

      final hasTransform = element.getAttribute('transform')?.trim().isNotEmpty ?? false;
      if (hasTransform) {
        issues.add(
          SvgValidationIssue(
            severity: SvgValidationSeverity.error,
            code: 'transform-not-allowed',
            message: 'Transform attribute is not allowed on <${element.name.local}>.',
          ),
        );
      }
    }

    final colorablePathElements = <XmlElement>[];
    var staticPathCount = 0;

    void validatePathWithInheritedRole(XmlElement element, String? inheritedRole) {
      final role = element.getAttribute('data-role') ?? inheritedRole;

      if (element.name.local == 'path') {
        if (role == null) {
          issues.add(
            const SvgValidationIssue(
              severity: SvgValidationSeverity.error,
              code: 'missing-data-role',
              message: 'Path element is missing data-role attribute.',
            ),
          );
          return;
        }

        if (role != 'colorable' && role != 'static') {
          issues.add(
            SvgValidationIssue(
              severity: SvgValidationSeverity.error,
              code: 'invalid-data-role',
              message: 'Path element has invalid data-role "$role".',
            ),
          );
        }

        if (role == 'static') {
          staticPathCount += 1;
        }

        if (role != 'colorable') {
          return;
        }

        final id = element.getAttribute('id');
        if (id == null) {
          issues.add(
            const SvgValidationIssue(
              severity: SvgValidationSeverity.error,
              code: 'missing-colorable-id',
              message: 'Colorable path is missing id attribute.',
            ),
          );
        } else if (id.trim().isEmpty) {
          issues.add(
            const SvgValidationIssue(
              severity: SvgValidationSeverity.error,
              code: 'empty-colorable-id',
              message: 'Colorable path has an empty id attribute.',
            ),
          );
        }

        colorablePathElements.add(element);

        final d = element.getAttribute('d') ?? '';
        if (d.trim().isEmpty) {
          issues.add(
            SvgValidationIssue(
              severity: SvgValidationSeverity.error,
              code: 'missing-path-data',
              message: 'Colorable path "$id" is missing d path data.',
            ),
          );
        }

        final moveCount = RegExp(r'[mM]').allMatches(d).length;
        if (moveCount > 1) {
          issues.add(
            SvgValidationIssue(
              severity: SvgValidationSeverity.warning,
              code: 'compound-path',
              message: 'Colorable path "$id" appears to contain multiple sub-paths.',
            ),
          );
        }

        final hasEvenOdd = (element.getAttribute('fill-rule') ?? '').trim().toLowerCase() == 'evenodd';
        if (hasEvenOdd) {
          issues.add(
            SvgValidationIssue(
              severity: SvgValidationSeverity.warning,
              code: 'fill-rule-evenodd',
              message: 'Colorable path "$id" uses fill-rule=evenodd; avoid hole-dependent geometry.',
            ),
          );
        }
      }

      for (final child in element.childElements) {
        validatePathWithInheritedRole(child, role);
      }
    }

    validatePathWithInheritedRole(document.rootElement, document.rootElement.getAttribute('data-role'));

    for (final path in colorablePathElements) {
      final id = path.getAttribute('id');
      if (id == null) {
        issues.add(
          const SvgValidationIssue(
            severity: SvgValidationSeverity.error,
            code: 'missing-colorable-id',
            message: 'Colorable path is missing id attribute.',
          ),
        );
      } else if (id.trim().isEmpty) {
        issues.add(
          const SvgValidationIssue(
            severity: SvgValidationSeverity.error,
            code: 'empty-colorable-id',
            message: 'Colorable path has an empty id attribute.',
          ),
        );
      }
    }

    final parsed = _parser.parseAndValidate(svgXml: svgXml, page: page);
    if (!parsed.isValid || parsed.asset == null) {
      final validation = parsed.validation;
      if (validation.errorMessage != null && validation.errorMessage!.isNotEmpty) {
        issues.add(
          SvgValidationIssue(
            severity: SvgValidationSeverity.error,
            code: 'parser-validation-failed',
            message: validation.errorMessage!,
          ),
        );
      }

      for (final id in validation.missingModelRegionIds) {
        issues.add(
          SvgValidationIssue(
            severity: SvgValidationSeverity.error,
            code: 'missing-model-region',
            message: 'Model region id "$id" is missing in SVG colorable regions.',
          ),
        );
      }

      for (final id in validation.unexpectedSvgRegionIds) {
        issues.add(
          SvgValidationIssue(
            severity: SvgValidationSeverity.error,
            code: 'unexpected-svg-region',
            message: 'SVG has colorable region "$id" that is absent from page model.',
          ),
        );
      }

      for (final id in validation.duplicateSvgRegionIds) {
        issues.add(
          SvgValidationIssue(
            severity: SvgValidationSeverity.error,
            code: 'duplicate-colorable-region-id',
            message: 'Duplicate colorable region id detected: "$id".',
          ),
        );
      }

      for (final metadataError in validation.metadataErrors) {
        issues.add(
          SvgValidationIssue(
            severity: SvgValidationSeverity.error,
            code: 'metadata-error',
            message: metadataError,
          ),
        );
      }

      return SvgContentValidationReport(
        issues: _dedupeIssues(issues),
        colorableRegionCount: colorablePathElements.length,
        totalPathCount: allPaths.length,
        staticPathCount: staticPathCount,
        colorableRegionIds: {
          for (final element in colorablePathElements)
            if ((element.getAttribute('id') ?? '').trim().isNotEmpty) element.getAttribute('id')!,
        },
      );
    }

    final asset = parsed.asset!;
    final byId = asset.colorableById;
    final colorableIds = byId.keys.toSet();

    for (final region in byId.values) {
      final bounds = region.path.getBounds();
      if (bounds.width <= 0 || bounds.height <= 0) {
        issues.add(
          SvgValidationIssue(
            severity: SvgValidationSeverity.error,
            code: 'invalid-hit-test-path',
            message: 'Colorable region "${region.id}" has empty path bounds.',
          ),
        );
        continue;
      }

      if (bounds.width < minTapTargetWidth || bounds.height < minTapTargetHeight) {
        issues.add(
          SvgValidationIssue(
            severity: SvgValidationSeverity.warning,
            code: 'small-region',
            message:
                'Colorable region "${region.id}" is small (${bounds.width.toStringAsFixed(1)} x ${bounds.height.toStringAsFixed(1)}).',
          ),
        );
      }

      final center = bounds.center;
      final centerContained = region.path.contains(center);
      if (!centerContained) {
        var anyContained = false;
        final sampleOffsets = <Offset>[
          const Offset(0.25, 0.25),
          const Offset(0.5, 0.25),
          const Offset(0.75, 0.25),
          const Offset(0.25, 0.5),
          const Offset(0.75, 0.5),
          const Offset(0.25, 0.75),
          const Offset(0.5, 0.75),
          const Offset(0.75, 0.75),
        ];
        for (final sample in sampleOffsets) {
          final point = Offset(
            bounds.left + bounds.width * sample.dx,
            bounds.top + bounds.height * sample.dy,
          );
          if (region.path.contains(point)) {
            anyContained = true;
            break;
          }
        }

        if (!anyContained) {
          issues.add(
            SvgValidationIssue(
              severity: SvgValidationSeverity.error,
              code: 'unhittable-region',
              message: 'Colorable region "${region.id}" has no detectable hit-testable area.',
            ),
          );
        } else {
          issues.add(
            SvgValidationIssue(
              severity: SvgValidationSeverity.warning,
              code: 'center-miss',
              message: 'Colorable region "${region.id}" center point is not contained by the path.',
            ),
          );
        }
      }
    }

    final regions = byId.values.toList(growable: false);
    for (var i = 0; i < regions.length; i++) {
      for (var j = i + 1; j < regions.length; j++) {
        final a = regions[i];
        final b = regions[j];
        final aBounds = a.path.getBounds();
        final bBounds = b.path.getBounds();
        if (!aBounds.overlaps(bBounds)) {
          continue;
        }

        final intersectionRect = aBounds.intersect(bBounds);
        final intersectionArea = intersectionRect.width * intersectionRect.height;
        if (intersectionArea <= 0) {
          continue;
        }

        issues.add(
          SvgValidationIssue(
            severity: SvgValidationSeverity.warning,
            code: 'overlap-warning',
            message: 'Colorable regions "${a.id}" and "${b.id}" have overlapping bounds.',
          ),
        );
      }
    }

    return SvgContentValidationReport(
      issues: _dedupeIssues(issues),
      colorableRegionCount: colorableIds.length,
      totalPathCount: allPaths.length,
      staticPathCount: staticPathCount,
      colorableRegionIds: colorableIds,
    );
  }

  List<SvgValidationIssue> _dedupeIssues(List<SvgValidationIssue> issues) {
    final seen = <String>{};
    final output = <SvgValidationIssue>[];
    for (final issue in issues) {
      final key = '${issue.severity.name}|${issue.code}|${issue.message}';
      if (seen.add(key)) {
        output.add(issue);
      }
    }
    return output;
  }
}
