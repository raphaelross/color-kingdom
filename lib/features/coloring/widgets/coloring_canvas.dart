import 'package:flutter/material.dart';

import '../../../app/theme/app_colors.dart';
import '../../../app/theme/app_spacing.dart';
import '../models/coloring_page.dart';

class ColoringCanvas extends StatelessWidget {
  const ColoringCanvas({
    required this.page,
    required this.regionColors,
    required this.onRegionTap,
    super.key,
  });

  final ColoringPage page;
  final Map<String, Color> regionColors;
  final ValueChanged<String> onRegionTap;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        return Card(
          child: ClipRRect(
            borderRadius: BorderRadius.circular(AppSpacing.radiusCard),
            child: InteractiveViewer(
              minScale: 1,
              maxScale: 3,
              boundaryMargin: const EdgeInsets.all(120),
              child: SizedBox(
                width: constraints.maxWidth,
                height: constraints.maxHeight,
                child: Stack(
                  children: [
                    Positioned.fill(
                      child: Container(
                        color: AppColors.surface,
                      ),
                    ),
                    Positioned.fill(
                      child: Padding(
                        padding: const EdgeInsets.all(AppSpacing.lg),
                        child: Column(
                          children: [
                            _CatRegion(
                              label: 'Head',
                              fillColor: regionColors['cat-head']!,
                              onTap: () => onRegionTap('cat-head'),
                              height: 110,
                              widthFactor: 0.42,
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
                                          fillColor: regionColors['cat-ear-left']!,
                                          onTap: () => onRegionTap('cat-ear-left'),
                                          height: 70,
                                          widthFactor: 0.28,
                                        ),
                                        const SizedBox(height: AppSpacing.sm),
                                        _CatRegion(
                                          label: 'Face',
                                          fillColor: regionColors['cat-eye-left']!,
                                          onTap: () => onRegionTap('cat-eye-left'),
                                          height: 70,
                                          widthFactor: 0.22,
                                        ),
                                        const SizedBox(height: AppSpacing.sm),
                                        _CatRegion(
                                          label: 'Body',
                                          fillColor: regionColors['cat-body']!,
                                          onTap: () => onRegionTap('cat-body'),
                                          height: 180,
                                          widthFactor: 0.62,
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
                                          fillColor: regionColors['cat-ear-right']!,
                                          onTap: () => onRegionTap('cat-ear-right'),
                                          height: 70,
                                          widthFactor: 0.3,
                                        ),
                                        const SizedBox(height: AppSpacing.sm),
                                        _CatRegion(
                                          label: 'Eye',
                                          fillColor: regionColors['cat-eye-right']!,
                                          onTap: () => onRegionTap('cat-eye-right'),
                                          height: 70,
                                          widthFactor: 0.22,
                                        ),
                                        const SizedBox(height: AppSpacing.sm),
                                        _CatRegion(
                                          label: 'Tail',
                                          fillColor: regionColors['cat-tail']!,
                                          onTap: () => onRegionTap('cat-tail'),
                                          height: 150,
                                          widthFactor: 0.18,
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
                                  fillColor: regionColors['cat-nose']!,
                                  onTap: () => onRegionTap('cat-nose'),
                                ),
                                const SizedBox(width: AppSpacing.sm),
                                _SmallRegion(
                                  label: 'Collar',
                                  fillColor: regionColors['cat-collar']!,
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
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

class _CatRegion extends StatelessWidget {
  const _CatRegion({
    required this.label,
    required this.fillColor,
    required this.onTap,
    required this.height,
    required this.widthFactor,
    this.alignment = Alignment.center,
    this.topPadding = 0,
  });

  final String label;
  final Color fillColor;
  final VoidCallback onTap;
  final double height;
  final double widthFactor;
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
