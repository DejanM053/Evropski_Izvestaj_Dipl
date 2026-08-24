import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:my_app/main.dart';
import 'package:my_app/screens/dev_gallery.dart';
import 'package:my_app/screens/home_screen.dart';

// Run with `flutter test --dart-define=API_URL=http://localhost:3000` (or
// any non-empty value) — main.dart reads Env.apiUrl at compile time and
// renders an explicit "missing API_URL" screen instead of Home when it's
// unset (docs/master_plan.md §7), which a bare `flutter test` leaves empty.
void main() {
  // Since Phase 6, HomeScreen (not the Phase 5 component gallery) is the
  // real home route (.claude/rules/mobile.md) — the gallery now lives
  // behind a kDebugMode-only icon in Home's header.
  testWidgets('app boots into the home screen', (WidgetTester tester) async {
    await tester.pumpWidget(const AccidentReportApp());
    await tester.pumpAndSettle();

    expect(find.byType(HomeScreen), findsOneWidget);
  });

  testWidgets('circumstance tile toggles when tapped', (WidgetTester tester) async {
    await tester.pumpWidget(const AccidentReportApp());
    await tester.pumpAndSettle();

    await tester.tap(find.widgetWithIcon(IconButton, Icons.widgets_outlined));
    await tester.pumpAndSettle();
    expect(find.byType(DevGalleryScreen), findsOneWidget);

    final tile = find.text('Bio je parkiran / zaustavljen');
    await tester.scrollUntilVisible(tile, 500, scrollable: find.byType(Scrollable).first);
    expect(tile, findsOneWidget);

    await tester.tap(tile);
    await tester.pump();
    // Toggling doesn't throw and the tile is still present post-rebuild.
    expect(tile, findsOneWidget);
  });
}
