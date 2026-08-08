import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/theme/app_spacing.dart';
import '../providers/coloring_provider.dart';
import '../widgets/color_palette.dart';
import '../widgets/coloring_canvas.dart';
import '../widgets/coloring_toolbar.dart';

class ColoringScreen extends ConsumerWidget {
  const ColoringScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(coloringControllerProvider);
    final controller = ref.read(coloringControllerProvider.notifier);

    return Scaffold(
      appBar: AppBar(
        title: Text(state.page.title),
      ),
      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, constraints) {
            final isTablet = constraints.maxWidth >= 700;

            final canvas = Expanded(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
                child: ColoringCanvas(
                  page: state.page,
                  regionColors: state.regionColors,
                  onRegionTap: controller.fillRegion,
                ),
              ),
            );

            final palette = Padding(
              padding: const EdgeInsets.fromLTRB(
                AppSpacing.md,
                0,
                AppSpacing.md,
                AppSpacing.md,
              ),
              child: ColorPalette(
                selectedColor: state.selectedColor,
                onColorSelected: controller.selectColor,
              ),
            );

            if (isTablet) {
              return Column(
                children: [
                  const SizedBox(height: AppSpacing.sm),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
                    child: ColoringToolbar(
                      canUndo: state.undoStack.isNotEmpty,
                      canRedo: state.redoStack.isNotEmpty,
                      onUndo: controller.undo,
                      onRedo: controller.redo,
                      onClear: controller.clear,
                    ),
                  ),
                  const SizedBox(height: AppSpacing.sm),
                  canvas,
                  const SizedBox(height: AppSpacing.sm),
                  palette,
                ],
              );
            }

            return Column(
              children: [
                const SizedBox(height: AppSpacing.sm),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
                  child: ColoringToolbar(
                    canUndo: state.undoStack.isNotEmpty,
                    canRedo: state.redoStack.isNotEmpty,
                    onUndo: controller.undo,
                    onRedo: controller.redo,
                    onClear: controller.clear,
                  ),
                ),
                const SizedBox(height: AppSpacing.sm),
                canvas,
                const SizedBox(height: AppSpacing.sm),
                palette,
              ],
            );
          },
        ),
      ),
    );
  }
}
