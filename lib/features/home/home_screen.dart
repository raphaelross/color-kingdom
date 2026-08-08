import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../app/router/app_router.dart';
import '../../app/theme/app_colors.dart';
import '../../app/theme/app_spacing.dart';
import 'widgets/category_card.dart';

class _CategoryItem {
  const _CategoryItem({
    required this.emoji,
    required this.title,
    required this.routeName,
    this.pathParameters = const <String, String>{},
  });

  final String emoji;
  final String title;
  final String routeName;
  final Map<String, String> pathParameters;
}

const List<_CategoryItem> _categories = [
  _CategoryItem(
    emoji: '🐶',
    title: 'Animals',
    routeName: AppRouteName.category,
    pathParameters: <String, String>{'category': 'animals'},
  ),
  _CategoryItem(
    emoji: '🦖',
    title: 'Dinosaurs',
    routeName: AppRouteName.category,
    pathParameters: <String, String>{'category': 'dinosaurs'},
  ),
  _CategoryItem(
    emoji: '🚀',
    title: 'Space',
    routeName: AppRouteName.category,
    pathParameters: <String, String>{'category': 'space'},
  ),
  _CategoryItem(
    emoji: '🚒',
    title: 'Vehicles',
    routeName: AppRouteName.category,
    pathParameters: <String, String>{'category': 'vehicles'},
  ),
  _CategoryItem(
    emoji: '🦄',
    title: 'Unicorns',
    routeName: AppRouteName.category,
    pathParameters: <String, String>{'category': 'unicorns'},
  ),
  _CategoryItem(
    emoji: '🎄',
    title: 'Holidays',
    routeName: AppRouteName.category,
    pathParameters: <String, String>{'category': 'holidays'},
  ),
  _CategoryItem(
    emoji: '⭐',
    title: 'Favorites',
    routeName: AppRouteName.gallery,
  ),
  _CategoryItem(
    emoji: '⚙',
    title: 'Parent Zone',
    routeName: AppRouteName.parentZone,
  ),
];

class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
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
                  itemCount: _categories.length,
                  gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: 2,
                    mainAxisSpacing: AppSpacing.md,
                    crossAxisSpacing: AppSpacing.md,
                    childAspectRatio: 1.25,
                  ),
                  itemBuilder: (context, index) {
                    final category = _categories[index];
                    return CategoryCard(
                      emoji: category.emoji,
                      title: category.title,
                      onTap: () {
                        context.goNamed(
                          category.routeName,
                          pathParameters: category.pathParameters,
                        );
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
