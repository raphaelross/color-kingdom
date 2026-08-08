import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import 'app_colors.dart';

class AppTextStyles {
  AppTextStyles._();

  static TextTheme get textTheme {
    final base = GoogleFonts.nunitoTextTheme();

    return base.copyWith(
      displayLarge: base.displayLarge?.copyWith(
        color: AppColors.onSurface,
        fontWeight: FontWeight.w800,
      ),
      displayMedium: base.displayMedium?.copyWith(
        color: AppColors.onSurface,
        fontWeight: FontWeight.w800,
      ),
      headlineLarge: base.headlineLarge?.copyWith(
        color: AppColors.onSurface,
        fontWeight: FontWeight.w800,
      ),
      headlineMedium: base.headlineMedium?.copyWith(
        color: AppColors.onSurface,
        fontWeight: FontWeight.w700,
      ),
      titleLarge: base.titleLarge?.copyWith(
        color: AppColors.onSurface,
        fontWeight: FontWeight.w700,
      ),
      titleMedium: base.titleMedium?.copyWith(
        color: AppColors.onSurface,
        fontWeight: FontWeight.w700,
      ),
      bodyLarge: base.bodyLarge?.copyWith(
        color: AppColors.onSurface,
        fontWeight: FontWeight.w600,
      ),
      bodyMedium: base.bodyMedium?.copyWith(
        color: AppColors.onSurfaceMuted,
        fontWeight: FontWeight.w500,
      ),
      bodySmall: base.bodySmall?.copyWith(
        color: AppColors.onSurfaceMuted,
      ),
      labelLarge: base.labelLarge?.copyWith(
        color: AppColors.onPrimary,
        fontWeight: FontWeight.w800,
      ),
    );
  }
}
