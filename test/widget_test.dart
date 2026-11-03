
import 'package:flutter_test/flutter_test.dart';
import 'package:free_campus_map/main.dart';

void main() {
  testWidgets('Campus Navigator app starts successfully',
          (WidgetTester tester) async {
        await tester.pumpWidget(const CampusNavigatorApp());

        expect(find.text('Campus Navigator'), findsOneWidget);
      });
}
