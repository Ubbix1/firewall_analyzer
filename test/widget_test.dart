import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:firewall_log_analyzer/screens/home_screen.dart';

void main() {
  testWidgets('Home screen loads correctly', (WidgetTester tester) async {
    // Build the HomeScreen widget and trigger a frame.
    await tester.pumpWidget(
      const MaterialApp(
        home: HomeScreen(skipInitialLoad: true),
      ),
    );

    // Verify if the upload button is present.
    expect(find.text('Upload Logs'), findsOneWidget);
  });
}
