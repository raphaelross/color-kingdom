import 'package:flutter/material.dart';

enum SvgElementRole { colorable, staticElement }

@immutable
class SvgPaintStyle {
  const SvgPaintStyle({
    this.fill,
    this.stroke,
    this.strokeWidth = 1,
  });

  final Color? fill;
  final Color? stroke;
  final double strokeWidth;
}

@immutable
class SvgDrawElement {
  const SvgDrawElement({
    required this.path,
    required this.role,
    required this.style,
    this.regionId,
    required this.drawOrder,
  });

  final Path path;
  final SvgElementRole role;
  final SvgPaintStyle style;
  final String? regionId;
  final int drawOrder;
}

@immutable
class SvgColorableRegion {
  const SvgColorableRegion({
    required this.id,
    required this.path,
    required this.style,
    required this.drawOrder,
    this.name,
  });

  final String id;
  final Path path;
  final SvgPaintStyle style;
  final int drawOrder;
  final String? name;
}

@immutable
class SvgColoringAsset {
  const SvgColoringAsset({
    required this.viewBox,
    required this.drawElements,
    required this.colorableRegions,
  });

  final Rect viewBox;
  final List<SvgDrawElement> drawElements;
  final List<SvgColorableRegion> colorableRegions;

  Map<String, SvgColorableRegion> get colorableById => {
        for (final region in colorableRegions) region.id: region,
      };
}

@immutable
class SvgAssetValidationResult {
  const SvgAssetValidationResult({
    required this.isValid,
    this.errorMessage,
    this.missingModelRegionIds = const [],
    this.unexpectedSvgRegionIds = const [],
    this.duplicateSvgRegionIds = const [],
    this.metadataErrors = const [],
  });

  final bool isValid;
  final String? errorMessage;
  final List<String> missingModelRegionIds;
  final List<String> unexpectedSvgRegionIds;
  final List<String> duplicateSvgRegionIds;
  final List<String> metadataErrors;

  String diagnosticsSummary() {
    final messages = <String>[];
    if (errorMessage != null && errorMessage!.isNotEmpty) {
      messages.add(errorMessage!);
    }
    if (missingModelRegionIds.isNotEmpty) {
      messages.add('Missing model regions in SVG: ${missingModelRegionIds.join(', ')}');
    }
    if (unexpectedSvgRegionIds.isNotEmpty) {
      messages.add('Unexpected SVG colorable regions: ${unexpectedSvgRegionIds.join(', ')}');
    }
    if (duplicateSvgRegionIds.isNotEmpty) {
      messages.add('Duplicate SVG region IDs: ${duplicateSvgRegionIds.join(', ')}');
    }
    if (metadataErrors.isNotEmpty) {
      messages.add('Metadata errors: ${metadataErrors.join(' | ')}');
    }
    if (messages.isEmpty) {
      return 'No diagnostics.';
    }
    return messages.join('\n');
  }
}

@immutable
class SvgColoringLoadResult {
  const SvgColoringLoadResult._({
    required this.asset,
    required this.validation,
  });

  factory SvgColoringLoadResult.valid(SvgColoringAsset asset) {
    return SvgColoringLoadResult._(
      asset: asset,
      validation: const SvgAssetValidationResult(isValid: true),
    );
  }

  factory SvgColoringLoadResult.invalid({
    required SvgAssetValidationResult validation,
  }) {
    return SvgColoringLoadResult._(asset: null, validation: validation);
  }

  final SvgColoringAsset? asset;
  final SvgAssetValidationResult validation;

  bool get isValid => validation.isValid && asset != null;
}
