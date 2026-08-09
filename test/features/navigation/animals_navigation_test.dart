import 'package:color_kingdom/app/app.dart';
import 'package:color_kingdom/features/coloring/coloring_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  Future<void> _pumpToHome(WidgetTester tester) async {
    await tester.pumpWidget(const App());
    await tester.pump(const Duration(seconds: 3));
    await tester.pumpAndSettle();
  }

  testWidgets('HomeScreen navigates to Animals category and shows Happy Cat', (
    WidgetTester tester,
  ) async {
    await _pumpToHome(tester);

    expect(find.text('Choose an Adventure'), findsOneWidget);
    expect(find.text('Animals'), findsAtLeastNWidgets(1));

    await tester.tap(find.text('Animals').first);
    await tester.pumpAndSettle();

    expect(
      find.descendant(of: find.byType(AppBar), matching: find.text('Animals')),
      findsOneWidget,
    );
    expect(find.text('Happy Cat'), findsOneWidget);
  });

  testWidgets('tapping Happy Cat opens ColoringScreen with Happy Cat page', (
    WidgetTester tester,
  ) async {
    await _pumpToHome(tester);

    await tester.tap(find.text('Animals').first);
    await tester.pumpAndSettle();

    await tester.tap(find.text('Happy Cat'));
    await tester.pumpAndSettle();

    expect(find.byType(ColoringScreen), findsOneWidget);
    expect(find.byType(InteractiveViewer), findsOneWidget);
    expect(find.text('Happy Cat'), findsOneWidget);
  });
}
