import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/router/app_router.dart';
import '../../../app/theme/app_spacing.dart';
import '../../categories/models/category.dart';
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
    final categoriesAsync = ref.watch(availableCategoriesProvider);
    final controller = ref.read(coloringControllerProvider.notifier);

    final title = state.page?.title ?? 'Coloring';
    final backDestination = _resolveBackDestination(state, categoriesAsync);

    return Scaffold(
      appBar: AppBar(
        leading: backDestination == null
            ? null
            : IconButton(
                icon: const Icon(Icons.arrow_back),
                tooltip: 'Back to ${backDestination.categoryTitle}',
                onPressed: () {
                  context.goNamed(
                    AppRouteName.category,
                    pathParameters: <String, String>{
                      'categoryId': backDestination.categoryId,
                    },
                  );
                },
              ),
        title: Text(title),
        actions: [
          if (backDestination != null)
            Padding(
              padding: const EdgeInsets.only(right: AppSpacing.sm),
              child: TextButton(
                onPressed: () {
                  context.goNamed(
                    AppRouteName.category,
                    pathParameters: <String, String>{
                      'categoryId': backDestination.categoryId,
                    },
                  );
                },
                child: Text('Back to ${backDestination.categoryTitle}'),
              ),
            ),
        ],
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

  _CategoryBackDestination? _resolveBackDestination(
    ColoringState state,
    AsyncValue<List<Category>> categoriesAsync,
  ) {
    if (state.status != ColoringLoadStatus.ready || state.page == null) {
      return null;
    }

    final categoryId = state.page!.categoryId.trim();
    if (categoryId.isEmpty) {
      return null;
    }

    final categoryTitle = categoriesAsync.when(
      data: (categories) {
        for (final category in categories) {
          if (category.categoryId == categoryId) {
            return category.title;
          }
        }
        return _formatCategoryId(categoryId);
      },
      loading: () => _formatCategoryId(categoryId),
      error: (_, stackTrace) => _formatCategoryId(categoryId),
    );

    return _CategoryBackDestination(
      categoryId: categoryId,
      categoryTitle: categoryTitle,
    );
  }
}

class _CategoryBackDestination {
  const _CategoryBackDestination({
    required this.categoryId,
    required this.categoryTitle,
  });

  final String categoryId;
  final String categoryTitle;
}

String _formatCategoryId(String categoryId) {
  final words = categoryId
      .replaceAll('_', ' ')
      .replaceAll('-', ' ')
      .split(' ')
      .where((word) => word.isNotEmpty)
      .map((word) => word[0].toUpperCase() + word.substring(1).toLowerCase())
      .toList(growable: false);

  if (words.isEmpty) {
    return categoryId;
  }

  return words.join(' ');
}
