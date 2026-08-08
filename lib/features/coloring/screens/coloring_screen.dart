import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/theme/app_spacing.dart';
import '../models/coloring_state.dart';
import '../providers/coloring_provider.dart';
import '../widgets/color_palette.dart';
import '../widgets/coloring_canvas.dart';
import '../widgets/coloring_renderer_registry.dart';
import '../widgets/coloring_toolbar.dart';

class ColoringScreen extends ConsumerWidget {
  const ColoringScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(coloringControllerProvider);
    final controller = ref.read(coloringControllerProvider.notifier);

    final title = state.page?.title ?? 'Coloring';

    return Scaffold(
      appBar: AppBar(
        title: Text(title),
      ),
      body: SafeArea(
        child: switch (state.status) {
          ColoringLoadStatus.loading => const Center(
              child: CircularProgressIndicator(),
            ),
          ColoringLoadStatus.error => Center(
              child: Padding(
                padding: const EdgeInsets.all(AppSpacing.xl),
                child: Text(
                  state.errorMessage ?? 'Unable to load coloring page.',
                  textAlign: TextAlign.center,
                ),
              ),
            ),
          ColoringLoadStatus.ready => LayoutBuilder(
              builder: (context, constraints) {
                final page = state.page;
                if (page == null) {
                  return const SizedBox.shrink();
                }

                final renderer = ColoringRendererRegistry.resolve(page);
                final canUndo = state.undoStack.isNotEmpty;
                final canRedo = state.redoStack.isNotEmpty;

                final canvas = Expanded(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
                    child: ColoringCanvas(
                      page: page,
                      regionColors: state.regionColors,
                      selectedColor: state.selectedColor,
                      renderer: renderer,
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

                return Column(
                  children: [
                    const SizedBox(height: AppSpacing.sm),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
                      child: ColoringToolbar(
                        canUndo: canUndo,
                        canRedo: canRedo,
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
        },
      ),
    );
  }
}
