import 'package:flutter/material.dart';

import '../../../app/theme/app_colors.dart';
import '../../../app/theme/app_spacing.dart';

class ColorPalette extends StatelessWidget {
  const ColorPalette({
    required this.selectedColor,
    required this.onColorSelected,
    super.key,
  });

  final Color selectedColor;
  final ValueChanged<Color> onColorSelected;

  static const List<Color> colors = [
    Color(0xFFFF4D4D),
    Color(0xFFFF8A3D),
    Color(0xFFFFD54F),
    Color(0xFFB8E986),
    Color(0xFF4FC3F7),
    Color(0xFF7E57C2),
    Color(0xFFFF80AB),
    Color(0xFF8D6E63),
    Color(0xFF212121),
    Color(0xFFF5F5F5),
    Color(0xFF81C784),
    Color(0xFFBA68C8),
    Color(0xFF64B5F6),
    Color(0xFF00ACC1),
    Color(0xFF26A69A),
    Color(0xFF66BB6A),
    Color(0xFFAED581),
    Color(0xFFFFB74D),
    Color(0xFFFFA726),
    Color(0xFFFFCC80),
    Color(0xFFBCAAA4),
    Color(0xFF90A4AE),
    Color(0xFFE57373),
    Color(0xFFFFFFFF),
  ];

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 132,
      child: GridView.builder(
        scrollDirection: Axis.horizontal,
        itemCount: colors.length,
        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: 2,
          mainAxisSpacing: AppSpacing.sm,
          crossAxisSpacing: AppSpacing.sm,
        ),
        itemBuilder: (context, index) {
          final color = colors[index];
          final isSelected = color.toARGB32() == selectedColor.toARGB32();
          return GestureDetector(
            onTap: () => onColorSelected(color),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 120),
              decoration: BoxDecoration(
                color: color,
                shape: BoxShape.circle,
                border: Border.all(
                  color: isSelected ? AppColors.onSurface : Colors.transparent,
                  width: isSelected ? 4 : 1,
                ),
                boxShadow: const [
                  BoxShadow(
                    color: Color(0x14000000),
                    blurRadius: 6,
                    offset: Offset(0, 3),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}
