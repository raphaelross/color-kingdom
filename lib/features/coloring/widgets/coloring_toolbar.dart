import 'package:flutter/material.dart';

import '../../../app/theme/app_spacing.dart';

class ColoringToolbar extends StatelessWidget {
  const ColoringToolbar({
    required this.canUndo,
    required this.canRedo,
    required this.onUndo,
    required this.onRedo,
    required this.onClear,
    super.key,
  });

  final bool canUndo;
  final bool canRedo;
  final VoidCallback onUndo;
  final VoidCallback onRedo;
  final VoidCallback onClear;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: ElevatedButton.icon(
            onPressed: canUndo ? onUndo : null,
            icon: const Icon(Icons.undo_rounded),
            label: const Text('Undo'),
          ),
        ),
        const SizedBox(width: AppSpacing.sm),
        Expanded(
          child: ElevatedButton.icon(
            onPressed: canRedo ? onRedo : null,
            icon: const Icon(Icons.redo_rounded),
            label: const Text('Redo'),
          ),
        ),
        const SizedBox(width: AppSpacing.sm),
        Expanded(
          child: OutlinedButton.icon(
            onPressed: onClear,
            icon: const Icon(Icons.delete_outline_rounded),
            label: const Text('Clear'),
          ),
        ),
      ],
    );
  }
}
