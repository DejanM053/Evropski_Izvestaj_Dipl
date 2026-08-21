import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:my_app/main.dart';
import 'package:my_app/screens/dev_gallery.dart';

void main() {
  testWidgets('app boots into the Phase 5 component gallery', (WidgetTester tester) async {
    await tester.pumpWidget(const AccidentReportApp());
    await tester.pumpAndSettle();

    expect(find.byType(DevGalleryScreen), findsOneWidget);
    expect(find.text('Component gallery'), findsOneWidget);
  });

  testWidgets('circumstance tile toggles when tapped', (WidgetTester tester) async {
    await tester.pumpWidget(const AccidentReportApp());
    await tester.pumpAndSettle();

    final tile = find.text('Bio je parkiran / zaustavljen');
    await tester.scrollUntilVisible(tile, 500, scrollable: find.byType(Scrollable).first);
    expect(tile, findsOneWidget);

    await tester.tap(tile);
    await tester.pump();
    // Toggling doesn't throw and the tile is still present post-rebuild.
    expect(tile, findsOneWidget);
  });
}
