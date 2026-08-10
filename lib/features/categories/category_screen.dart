import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:go_router/go_router.dart';

import '../../app/router/app_router.dart';
import '../../app/theme/app_spacing.dart';
import '../coloring/providers/coloring_provider.dart';

class CategoryScreen extends ConsumerWidget {
  const CategoryScreen({required this.categoryId, super.key});

  final String categoryId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final pagesAsync = ref.watch(categoryPagesProvider(categoryId));
    final categoriesAsync = ref.watch(availableCategoriesProvider);

    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          tooltip: 'Back',
          onPressed: () => context.goNamed(AppRouteName.home),
        ),
        title: categoriesAsync.when(
          data: (categories) {
            final match = categories.where((c) => c.categoryId == categoryId);
            return Text(match.isEmpty ? _toTitleCase(categoryId) : match.first.title);
          },
          loading: () => Text(_toTitleCase(categoryId)),
          error: (_, _) => Text(_toTitleCase(categoryId)),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.home_rounded),
            tooltip: 'Home',
            onPressed: () => context.goNamed(AppRouteName.home),
          ),
        ],
      ),
      body: pagesAsync.when(
        data: (pages) {
          if (pages.isEmpty) {
            return _EmptyCategoryMessage(categoryName: _toTitleCase(categoryId));
          }

          return ListView.separated(
            padding: const EdgeInsets.all(AppSpacing.md),
            itemBuilder: (context, index) {
              final page = pages[index];
              return Card(
                child: ListTile(
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: AppSpacing.md,
                    vertical: AppSpacing.sm,
                  ),
                  leading: SizedBox(
                    width: 64,
                    height: 64,
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(AppSpacing.radiusCard),
                      child: ColoredBox(
                        color: Colors.white,
                        child: SvgPicture.asset(
                          page.assetPath,
                          fit: BoxFit.contain,
                        ),
                      ),
                    ),
                  ),
                  title: Text(page.title),
                  subtitle: Text(_toTitleCase(page.categoryId)),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () {
                    context.goNamed(
                      AppRouteName.coloring,
                      pathParameters: <String, String>{'pageId': page.id},
                      queryParameters: <String, String>{
                        ColoringRouteQuery.source: ColoringRouteQuery.sourceCategory,
                        ColoringRouteQuery.sourceCategoryId: categoryId,
                      },
                    );
                  },
                ),
              );
            },
            separatorBuilder: (_, _) => const SizedBox(height: AppSpacing.sm),
            itemCount: pages.length,
          );
        },
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, _) => Center(
          child: Padding(
            padding: const EdgeInsets.all(AppSpacing.xl),
            child: Text(
              'Failed to load category pages: $error',
              textAlign: TextAlign.center,
            ),
          ),
        ),
      ),
    );
  }
}

class _EmptyCategoryMessage extends StatelessWidget {
  const _EmptyCategoryMessage({required this.categoryName});

  final String categoryName;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.xl),
        child: Text(
          '$categoryName category is ready for content.',
          style: Theme.of(context).textTheme.titleLarge,
          textAlign: TextAlign.center,
        ),
      ),
    );
  }
}

String _toTitleCase(String text) {
  if (text.isEmpty) {
    return text;
  }

  return text[0].toUpperCase() + text.substring(1).toLowerCase();
}
