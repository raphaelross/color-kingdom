import 'package:flutter/foundation.dart';

@immutable
class Category {
  const Category({
    required this.categoryId,
    required this.title,
    required this.sortOrder,
    this.emoji,
  });

  final String categoryId;
  final String title;
  final int sortOrder;
  final String? emoji;
}
