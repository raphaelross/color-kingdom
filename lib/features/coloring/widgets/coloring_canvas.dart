import 'package:flutter/material.dart';

import '../../../app/theme/app_colors.dart';
import '../../../app/theme/app_spacing.dart';
import '../models/coloring_page.dart';
import 'coloring_renderer.dart';

class ColoringCanvas extends StatelessWidget {
  const ColoringCanvas({
    required this.page,
    required this.regionColors,
    required this.selectedColor,
    required this.renderer,
    required this.onRegionTap,
    super.key,
  });

  final ColoringPage page;
  final Map<String, Color> regionColors;
  final Color selectedColor;
  final ColoringRenderer renderer;
  final ValueChanged<String> onRegionTap;

  @override
  Widget build(BuildContext context) {
    final validation = renderer.validate(page);

    return LayoutBuilder(
      builder: (context, constraints) {
        if (!validation.isValid) {
          return Card(
            child: Padding(
              padding: const EdgeInsets.all(AppSpacing.xl),
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Icon(Icons.warning_amber_rounded, size: 40),
                    const SizedBox(height: AppSpacing.md),
                    Text(
                      'Renderer/page mismatch',
                      style: Theme.of(context).textTheme.titleLarge,
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: AppSpacing.sm),
                    Text(
                      'Renderer "${renderer.id}" is missing region IDs: '
                      '${validation.missingRegionIds.join(', ')}',
                      style: Theme.of(context).textTheme.bodyMedium,
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: AppSpacing.sm),
                    Text(
                      'Page: ${page.id}',
                      style: Theme.of(context).textTheme.bodySmall,
                      textAlign: TextAlign.center,
                    ),
                  ],
                ),
              ),
            ),
          );
        }

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
                      child: renderer.build(
                        context: context,
                        page: page,
                        regionColors: regionColors,
                        selectedColor: selectedColor,
                        onRegionTap: onRegionTap,
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
