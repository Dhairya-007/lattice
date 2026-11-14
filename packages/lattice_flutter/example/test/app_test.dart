// Proves the demo survives the sizes it will actually be opened at.
//
// A RenderFlex overflow throws in a widget test, so "does it break on a
// narrow window" is a question tests can answer — which matters here,
// because the machine this was written on cannot run the app.
import 'package:flutter_test/flutter_test.dart';
import 'package:lattice_example/main.dart';
import 'package:material_ui/material_ui.dart';

/// Pumps the app at a given window size.
Future<void> pumpAt(WidgetTester tester, Size size) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(const LatticeExampleApp());
  await tester.pump(const Duration(milliseconds: 50));
}

void main() {
  const sizes = <String, Size>{
    'desktop': Size(1680, 1000),
    'laptop': Size(1280, 800),
    'small laptop': Size(1024, 700),
    'tablet landscape': Size(900, 620),
    'tablet portrait': Size(768, 1024),
    'narrow': Size(600, 800),
    'phone': Size(420, 860),
  };

  for (final entry in sizes.entries) {
    testWidgets('lays out without overflowing at ${entry.key}', (tester) async {
      await pumpAt(tester, entry.value);
      // Any RenderFlex overflow, assertion or layout error lands here.
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('the grid and its chrome are all present', (tester) async {
    await pumpAt(tester, const Size(1440, 900));
    expect(find.text('Lattice'), findsOneWidget);
    expect(find.text('Search 50,000 lines'), findsOneWidget);
    expect(find.text('Group'), findsOneWidget);
    expect(find.text('Live'), findsOneWidget);
    // Stacked header bands, column titles, and rows.
    expect(find.text('Event'), findsOneWidget);
    expect(find.text('Latency'), findsOneWidget);
    expect(find.byType(Checkbox), findsWidgets);
    expect(tester.takeException(), isNull);
  });

  testWidgets('searching narrows the grid and the stat tile', (tester) async {
    await pumpAt(tester, const Size(1440, 900));
    expect(find.text('50.0k'), findsOneWidget);

    final fields = tester.widgetList<TextField>(find.byType(TextField));
    debugPrint(
      'DIAG textFields=${fields.length} '
      'hints=${fields.map((f) => f.decoration?.hintText).toList()}',
    );

    await tester.enterText(find.byType(TextField).first, 'circuit breaker');
    await tester.pump(const Duration(milliseconds: 50));
    debugPrint(
      'DIAG after search, texts='
      '${tester.widgetList<Text>(find.byType(Text)).map((t) => t.data).where((t) => t != null && t.length < 12).take(40).toList()}',
    );

    expect(find.text('50.0k'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('grouping and ungrouping leave the grid intact', (tester) async {
    await pumpAt(tester, const Size(1440, 900));
    await tester.tap(find.text('Group'));
    await tester.pump(const Duration(milliseconds: 50));
    debugPrint(
      'DIAG after group, texts='
      '${tester.widgetList<Text>(find.byType(Text)).map((t) => t.data).whereType<String>().take(40).toList()}',
    );
    expect(find.textContaining('service:'), findsWidgets);

    await tester.tap(find.text('Group'));
    await tester.pump(const Duration(milliseconds: 50));
    expect(find.textContaining('service:'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('the density control changes the row pitch', (tester) async {
    await pumpAt(tester, const Size(1440, 900));
    double pitch() {
      final rows = tester
          .widgetList<Text>(find.byType(Text))
          .map((t) => t.data)
          .whereType<String>()
          .where((t) => t.endsWith(' ms'))
          .length;
      return rows.toDouble();
    }

    final standard = pitch();
    await tester.tap(find.byIcon(Icons.density_small_rounded));
    await tester.pump(const Duration(milliseconds: 200));
    // Compact fits more rows in the same viewport.
    expect(pitch(), greaterThan(standard));
    expect(tester.takeException(), isNull);
  });

  testWidgets('live mode stops cleanly when the app goes away', (tester) async {
    await pumpAt(tester, const Size(1440, 900));
    await tester.tap(find.text('Live'));
    await tester.pump(const Duration(milliseconds: 950));
    expect(tester.takeException(), isNull);

    // Disposing with the timer running must not leave it behind.
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(seconds: 2));
    expect(tester.takeException(), isNull);
  });

  testWidgets('errors filter and reset round-trip', (tester) async {
    await pumpAt(tester, const Size(1440, 900));
    await tester.tap(find.text('Errors'));
    await tester.pump(const Duration(milliseconds: 50));
    debugPrint(
      'DIAG after errors, texts='
      '${tester.widgetList<Text>(find.byType(Text)).map((t) => t.data).whereType<String>().take(24).toList()}',
    );
    expect(find.text('50.0k'), findsNothing);

    await tester.tap(find.text('Reset'));
    await tester.pump(const Duration(milliseconds: 50));
    expect(find.text('50.0k'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
