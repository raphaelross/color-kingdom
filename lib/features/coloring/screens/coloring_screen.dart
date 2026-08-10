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
  const ColoringScreen({
    this.navigationSource,
    this.sourceCategoryId,
    super.key,
  });

  final String? navigationSource;
  final String? sourceCategoryId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(coloringControllerProvider);
    final categoriesAsync = ref.watch(availableCategoriesProvider);
    final controller = ref.read(coloringControllerProvider.notifier);

    final title = state.page?.title ?? 'Coloring';
    final backDestination = _resolveBackDestination(
      state,
      categoriesAsync,
    );

    return Scaffold(
      appBar: AppBar(
        leading: backDestination == null
            ? null
            : IconButton(
                icon: const Icon(Icons.arrow_back),
                tooltip: 'Back to ${backDestination.destinationTitle}',
                onPressed: () async {
                  await controller.waitForPendingPersistence();
                  if (!context.mounted) {
                    return;
                  }
                  context.goNamed(
                    backDestination.routeName,
                    pathParameters: backDestination.pathParameters,
                  );
                },
              ),
        title: Text(title),
        actions: [
          IconButton(
            icon: const Icon(Icons.home_rounded),
            tooltip: 'Home',
            onPressed: () async {
              await controller.waitForPendingPersistence();
              if (!context.mounted) {
                return;
              }
              context.goNamed(AppRouteName.home);
            },
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

  _BackDestination? _resolveBackDestination(
    ColoringState state,
    AsyncValue<List<Category>> categoriesAsync,
  ) {
    if (navigationSource == ColoringRouteQuery.sourceMyCreations) {
      return const _BackDestination(
        routeName: AppRouteName.gallery,
        pathParameters: <String, String>{},
        destinationTitle: 'My Creations',
      );
    }

    if (navigationSource == ColoringRouteQuery.sourceCategory) {
      final originCategoryId = sourceCategoryId?.trim() ?? '';
      if (originCategoryId.isNotEmpty) {
        return _BackDestination(
          routeName: AppRouteName.category,
          pathParameters: <String, String>{'categoryId': originCategoryId},
          destinationTitle: _resolveCategoryTitle(
            categoryId: originCategoryId,
            categoriesAsync: categoriesAsync,
          ),
        );
      }
    }

    if (state.page != null) {
      final categoryId = state.page!.categoryId.trim();
      if (categoryId.isNotEmpty) {
        return _BackDestination(
          routeName: AppRouteName.category,
          pathParameters: <String, String>{'categoryId': categoryId},
          destinationTitle: _resolveCategoryTitle(
            categoryId: categoryId,
            categoriesAsync: categoriesAsync,
          ),
        );
      }
    }

    return const _BackDestination(
      routeName: AppRouteName.home,
      pathParameters: <String, String>{},
      destinationTitle: 'Home',
    );
  }

  String _resolveCategoryTitle({
    required String categoryId,
    required AsyncValue<List<Category>> categoriesAsync,
  }) {
    return categoriesAsync.when(
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
  }
}

class _BackDestination {
  const _BackDestination({
    required this.routeName,
    required this.pathParameters,
    required this.destinationTitle,
  });

  final String routeName;
  final Map<String, String> pathParameters;
  final String destinationTitle;
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
