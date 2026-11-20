import 'package:flutter_test/flutter_test.dart';
import 'package:glass_nav_dummy/main.dart';

void main() {
  testWidgets('LiquidGlassApp smoke test', (WidgetTester tester) async {
    await tester.pumpWidget(const LiquidGlassApp());
    expect(find.text('Alarm'), findsAtLeastNWidgets(1));
  });
}
