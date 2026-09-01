import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../lib/widgets/responsive_card_grid.dart';
import '../lib/widgets/responsive_page_frame.dart';

void main() {
  testWidgets('frame constrains wide content to 1320 pixels', (tester) async {
    await tester.binding.setSurfaceSize(const Size(1600, 600));
    await tester.pumpWidget(
      const MaterialApp(
        home: SizedBox(
          width: 1600,
          child: ResponsivePageFrame(child: SizedBox(key: Key('content'))),
        ),
      ),
    );

    final frame = tester.getSize(
      find.byKey(const Key('responsive-page-frame')),
    );
    expect(frame.width, lessThanOrEqualTo(1320));
    addTearDown(() => tester.binding.setSurfaceSize(null));
  });

  testWidgets('grid gives desktop cards equal widths and row heights', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: SizedBox(
          width: 1000,
          child: ResponsiveCardGrid(
            children: [
              SizedBox(height: 40, child: Text('one')),
              SizedBox(height: 70, child: Text('two')),
              SizedBox(height: 30, child: Text('three')),
            ],
          ),
        ),
      ),
    );

    final first = tester.getSize(
      find.byKey(const Key('responsive-card-grid-item-0')),
    );
    final second = tester.getSize(
      find.byKey(const Key('responsive-card-grid-item-1')),
    );
    final third = tester.getSize(
      find.byKey(const Key('responsive-card-grid-item-2')),
    );
    expect(first.width, second.width);
    expect(first.height, second.height);
    expect(third.height, 30);
  });

  testWidgets('grid becomes a single column below 720 pixels', (tester) async {
    await tester.binding.setSurfaceSize(const Size(600, 600));
    await tester.pumpWidget(
      const MaterialApp(
        home: SizedBox(
          width: 600,
          child: ResponsiveCardGrid(
            children: [SizedBox(height: 20), SizedBox(height: 30)],
          ),
        ),
      ),
    );

    final first = tester.getTopLeft(
      find.byKey(const Key('responsive-card-grid-item-0')),
    );
    final second = tester.getTopLeft(
      find.byKey(const Key('responsive-card-grid-item-1')),
    );
    expect(second.dy, greaterThan(first.dy));
    expect(
      tester
          .getSize(find.byKey(const Key('responsive-card-grid-item-0')))
          .width,
      600,
    );
    addTearDown(() => tester.binding.setSurfaceSize(null));
  });
}
