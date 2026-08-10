import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:color_kingdom/features/coloring/models/coloring_page.dart';
import 'package:color_kingdom/features/coloring/widgets/coloring_canvas.dart';
import 'package:color_kingdom/features/coloring/widgets/coloring_renderer.dart';

class _MismatchedRenderer extends ColoringRenderer {
  const _MismatchedRenderer();

  @override
  String get id => 'mismatch-renderer';

  @override
  List<String> get requiredRegionIds => const ['missing-region'];

  @override
  Widget build({
    required BuildContext context,
    required ColoringPage page,
    required Map<String, Color> regionColors,
    required Color selectedColor,
    required ValueChanged<String> onRegionTap,
  }) {
    return const SizedBox.shrink();
  }
}

void main() {
  testWidgets('shows graceful error when renderer region ids do not match page',
      (tester) async {
    const page = ColoringPage(
      id: 'test-page',
      title: 'Test',
      categoryId: 'test',
      assetPath: 'assets/test.svg',
      sortOrder: 0,
      regions: [
        ColoringRegion(
          id: 'existing-region',
          name: 'Existing',
          defaultColor: Colors.transparent,
        ),
      ],
    );

    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 300,
            height: 300,
            child: ColoringCanvas(
              page: page,
              regionColors: {'existing-region': Colors.transparent},
              selectedColor: Colors.blue,
              renderer: _MismatchedRenderer(),
              onRegionTap: _noop,
            ),
          ),
        ),
      ),
    );

    expect(find.text('Renderer/page mismatch'), findsOneWidget);
    expect(find.textContaining('missing-region'), findsOneWidget);
  });
}

void _noop(String _) {}
