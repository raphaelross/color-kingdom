import 'package:flutter/material.dart';

import '../../app/theme/app_spacing.dart';

class CategoryScreen extends StatelessWidget {
  const CategoryScreen({required this.categoryName, super.key});

  final String categoryName;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(categoryName)),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.xl),
          child: Text(
            '$categoryName category is ready for content.',
            style: Theme.of(context).textTheme.titleLarge,
            textAlign: TextAlign.center,
          ),
        ),
      ),
    );
  }
}
