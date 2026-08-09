import 'package:go_router/go_router.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../features/categories/category_screen.dart';
import '../../features/coloring/coloring_screen.dart';
import '../../features/coloring/providers/coloring_provider.dart';
import '../../features/gallery/gallery_screen.dart';
import '../../features/home/home_screen.dart';
import '../../features/parent/parent_zone_screen.dart';
import '../../features/settings/settings_screen.dart';
import '../../features/splash/splash_screen.dart';

class AppRoute {
  AppRoute._();

  static const String root = '/';
  static const String home = '/home';
  static const String category = '/category/:category';
  static const String coloring = '/coloring';
  static const String gallery = '/gallery';
  static const String parentZone = '/parent-zone';
  static const String settings = '/settings';
}

class AppRouteName {
  AppRouteName._();

  static const String root = 'root';
  static const String home = 'home';
  static const String category = 'category';
  static const String coloring = 'coloring';
  static const String gallery = 'gallery';
  static const String parentZone = 'parent-zone';
  static const String settings = 'settings';
}

class AppRouter {
  AppRouter._();

  static final GoRouter router = GoRouter(
    initialLocation: AppRoute.root,
    routes: [
      GoRoute(
        path: AppRoute.root,
        name: AppRouteName.root,
        builder: (context, state) => const SplashScreen(),
      ),
      GoRoute(
        path: AppRoute.home,
        name: AppRouteName.home,
        builder: (context, state) => const HomeScreen(),
      ),
      GoRoute(
        path: AppRoute.category,
        name: AppRouteName.category,
        builder: (_, state) => CategoryScreen(
          categoryName: state.pathParameters['category'] ?? 'Adventure',
        ),
      ),
      GoRoute(
        path: AppRoute.coloring,
        name: AppRouteName.coloring,
        builder: (context, state) {
          final pageId = state.uri.queryParameters['pageId'];
          if (pageId == null || pageId.isEmpty) {
            return const ColoringScreen();
          }

          return ProviderScope(
            overrides: [
              coloringInitialPageIdProvider.overrideWithValue(pageId),
            ],
            child: const ColoringScreen(),
          );
        },
      ),
      GoRoute(
        path: AppRoute.gallery,
        name: AppRouteName.gallery,
        builder: (context, state) => const GalleryScreen(),
      ),
      GoRoute(
        path: AppRoute.parentZone,
        name: AppRouteName.parentZone,
        builder: (context, state) => const ParentZoneScreen(),
      ),
      GoRoute(
        path: AppRoute.settings,
        name: AppRouteName.settings,
        builder: (context, state) => const SettingsScreen(),
      ),
    ],
  );
}
