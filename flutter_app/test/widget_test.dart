import 'package:flutter_test/flutter_test.dart';
import 'package:siagenda_app/main.dart';

void main() {
  testWidgets('App starts with MonaApp', (WidgetTester tester) async {
    await tester.pumpWidget(const MonaApp());
    // Splash screen should render MONA
    expect(find.text('MONA'), findsOneWidget);
  });
}

