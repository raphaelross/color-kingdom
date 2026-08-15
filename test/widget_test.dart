import 'package:flutter_test/flutter_test.dart';

import 'package:color_kingdom/app/app.dart';

void main() {
  testWidgets('shows splash then navigates to home', (WidgetTester tester) async {
    await tester.pumpWidget(const App());

    expect(find.text('Color Kingdom'), findsWidgets);
    expect(find.text('Where Every Picture Becomes an Adventure.'), findsOneWidget);

    await tester.pump(const Duration(seconds: 3));
    await tester.pumpAndSettle();

    expect(find.text('Choose an Adventure'), findsOneWidget);
    expect(find.text('Animals'), findsOneWidget);
  });
}
