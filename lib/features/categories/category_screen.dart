import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/router/app_router.dart';
import '../../app/theme/app_spacing.dart';
import '../coloring/providers/coloring_provider.dart';

class CategoryScreen extends ConsumerWidget {
  const CategoryScreen({required this.categoryName, super.key});

  final String categoryName;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final title = _toTitleCase(categoryName);
    final pagesAsync = ref.watch(availableColoringPagesProvider);

    return Scaffold(
      appBar: AppBar(title: Text(title)),
      body: pagesAsync.when(
        data: (pages) {
          final categoryPages = pages
              .where(
                (page) =>
                    page.category.toLowerCase() == categoryName.toLowerCase(),
              )
              .toList(growable: false);

          if (categoryPages.isEmpty) {
            return _EmptyCategoryMessage(categoryName: title);
          }

          return ListView.separated(
            padding: const EdgeInsets.all(AppSpacing.md),
            itemBuilder: (context, index) {
              final page = categoryPages[index];
              return Card(
                child: ListTile(
                  title: Text(page.title),
                  subtitle: Text(page.category),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () {
                    context.goNamed(
                      AppRouteName.coloring,
                      queryParameters: <String, String>{'pageId': page.id},
                    );
                  },
                ),
              );
            },
            separatorBuilder: (_, _) => const SizedBox(height: AppSpacing.sm),
            itemCount: categoryPages.length,
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
