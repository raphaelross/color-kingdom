import 'package:flutter/material.dart';

import '../../../../app/theme/app_colors.dart';
import '../../../../app/theme/app_spacing.dart';
import '../../models/coloring_page.dart';
import '../coloring_renderer.dart';

class HappyCatRenderer extends ColoringRenderer {
  const HappyCatRenderer();

  static const List<String> _requiredRegionIds = [
    'cat-head',
    'cat-ear-left',
    'cat-ear-right',
    'cat-eye-left',
    'cat-eye-right',
    'cat-body',
    'cat-tail',
    'cat-nose',
    'cat-collar',
  ];

  @override
  String get id => 'happy-cat-renderer';

  @override
  List<String> get requiredRegionIds => _requiredRegionIds;

  @override
  Widget build({
    required BuildContext context,
    required ColoringPage page,
    required Map<String, Color> regionColors,
    required Color selectedColor,
    required ValueChanged<String> onRegionTap,
  }) {
    Color regionColor(String id) => regionColors[id] ?? Colors.transparent;

    return Padding(
      padding: const EdgeInsets.all(AppSpacing.lg),
      child: Column(
        children: [
          _CatRegion(
            label: 'Head',
            fillColor: regionColor('cat-head'),
            onTap: () => onRegionTap('cat-head'),
            height: 110,
            alignment: Alignment.topCenter,
            topPadding: 12,
          ),
          const SizedBox(height: AppSpacing.sm),
          Expanded(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Expanded(
                  flex: 2,
                  child: Column(
                    children: [
                      _CatRegion(
                        label: 'Left Ear',
                        fillColor: regionColor('cat-ear-left'),
                        onTap: () => onRegionTap('cat-ear-left'),
                        height: 70,
                      ),
                      const SizedBox(height: AppSpacing.sm),
                      _CatRegion(
                        label: 'Face',
                        fillColor: regionColor('cat-eye-left'),
                        onTap: () => onRegionTap('cat-eye-left'),
                        height: 70,
                      ),
                      const SizedBox(height: AppSpacing.sm),
                      _CatRegion(
                        label: 'Body',
                        fillColor: regionColor('cat-body'),
                        onTap: () => onRegionTap('cat-body'),
                        height: 180,
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: AppSpacing.sm),
                Expanded(
                  flex: 1,
                  child: Column(
                    children: [
                      _CatRegion(
                        label: 'Right Ear',
                        fillColor: regionColor('cat-ear-right'),
                        onTap: () => onRegionTap('cat-ear-right'),
                        height: 70,
                      ),
                      const SizedBox(height: AppSpacing.sm),
                      _CatRegion(
                        label: 'Eye',
                        fillColor: regionColor('cat-eye-right'),
                        onTap: () => onRegionTap('cat-eye-right'),
                        height: 70,
                      ),
                      const SizedBox(height: AppSpacing.sm),
                      _CatRegion(
                        label: 'Tail',
                        fillColor: regionColor('cat-tail'),
                        onTap: () => onRegionTap('cat-tail'),
                        height: 150,
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: AppSpacing.sm),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              _SmallRegion(
                label: 'Nose',
                fillColor: regionColor('cat-nose'),
                onTap: () => onRegionTap('cat-nose'),
              ),
              const SizedBox(width: AppSpacing.sm),
              _SmallRegion(
                label: 'Collar',
                fillColor: regionColor('cat-collar'),
                onTap: () => onRegionTap('cat-collar'),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.sm),
          Text(
            page.title,
            style: Theme.of(context).textTheme.titleMedium,
          ),
        ],
      ),
    );
  }
}

class _CatRegion extends StatelessWidget {
  const _CatRegion({
    required this.label,
    required this.fillColor,
    required this.onTap,
    required this.height,
    this.alignment = Alignment.center,
    this.topPadding = 0,
  });

  final String label;
  final Color fillColor;
  final VoidCallback onTap;
  final double height;
  final Alignment alignment;
  final double topPadding;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Padding(
        padding: EdgeInsets.only(top: topPadding),
        child: GestureDetector(
          onTap: onTap,
          child: Container(
            height: height,
            alignment: alignment,
            decoration: BoxDecoration(
              color: fillColor,
              borderRadius: BorderRadius.circular(22),
              border: Border.all(color: AppColors.onSurface, width: 3),
            ),
            child: Text(
              label,
              style: Theme.of(context).textTheme.labelLarge?.copyWith(
                color: AppColors.onSurface,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _SmallRegion extends StatelessWidget {
  const _SmallRegion({
    required this.label,
    required this.fillColor,
    required this.onTap,
  });

  final String label;
  final Color fillColor;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 110,
        height: 64,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: fillColor,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: AppColors.onSurface, width: 3),
        ),
        child: Text(
          label,
          style: Theme.of(context).textTheme.labelLarge?.copyWith(
            color: AppColors.onSurface,
          ),
        ),
      ),
    );
  }
}
