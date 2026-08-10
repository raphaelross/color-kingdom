import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../app/router/app_router.dart';
import '../../app/theme/app_colors.dart';
import '../../app/theme/app_spacing.dart';
import '../categories/data/local_categories.dart';
import '../categories/models/category.dart';
import 'widgets/category_card.dart';

class _ActionItem {
  const _ActionItem({
    required this.emoji,
    required this.title,
    required this.routeName,
  });

  final String emoji;
  final String title;
  final String routeName;
}

const List<_ActionItem> _actions = [
  _ActionItem(
    emoji: '⭐',
    title: 'My Creations',
    routeName: AppRouteName.gallery,
  ),
  _ActionItem(
    emoji: '⚙',
    title: 'Parent Zone',
    routeName: AppRouteName.parentZone,
  ),
];

class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final categories = [...localCategories]
      ..sort((a, b) => a.sortOrder.compareTo(b.sortOrder));
    final items = [
      ...categories.map(_HomeGridItem.fromCategory),
      ..._actions.map(_HomeGridItem.fromAction),
    ];

    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(
            AppSpacing.xl,
            AppSpacing.xl,
            AppSpacing.xl,
            AppSpacing.md,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '🌈 Color Kingdom',
                style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                  color: AppColors.onSurface,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: AppSpacing.xs),
              Text(
                'Choose an Adventure',
                style: Theme.of(context).textTheme.titleLarge?.copyWith(
                  color: AppColors.onSurfaceMuted,
                ),
              ),
              const SizedBox(height: AppSpacing.lg),
              Expanded(
                child: GridView.builder(
                  itemCount: items.length,
                  gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: 2,
                    mainAxisSpacing: AppSpacing.md,
                    crossAxisSpacing: AppSpacing.md,
                    childAspectRatio: 1.25,
                  ),
                  itemBuilder: (context, index) {
                    final item = items[index];
                    return CategoryCard(
                      emoji: item.emoji,
                      title: item.title,
                      onTap: () {
                        if (item.isCategory) {
                          context.goNamed(
                            AppRouteName.category,
                            pathParameters: <String, String>{
                              'categoryId': item.categoryId!,
                            },
                          );
                          return;
                        }

                        context.goNamed(item.routeName!);
                      },
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _HomeGridItem {
  const _HomeGridItem.category({
    required this.emoji,
    required this.title,
    required this.categoryId,
  })  : isCategory = true,
        routeName = null;

  const _HomeGridItem.action({
    required this.emoji,
    required this.title,
    required this.routeName,
  })  : isCategory = false,
        categoryId = null;

  factory _HomeGridItem.fromCategory(Category category) {
    return _HomeGridItem.category(
      emoji: category.emoji ?? '📘',
      title: category.title,
      categoryId: category.categoryId,
    );
  }

  factory _HomeGridItem.fromAction(_ActionItem action) {
    return _HomeGridItem.action(
      emoji: action.emoji,
      title: action.title,
      routeName: action.routeName,
    );
  }

  final String emoji;
  final String title;
  final bool isCategory;
  final String? categoryId;
  final String? routeName;
}
