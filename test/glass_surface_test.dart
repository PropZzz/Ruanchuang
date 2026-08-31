import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shixuzhipei/widgets/glass_surface.dart';

void main() {
  testWidgets(
    'GlassSurface composes a blur layer without changing child semantics',
    (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: GlassSurface(child: const Text('timeline slot')),
          ),
        ),
      );

      expect(find.byType(BackdropFilter), findsOneWidget);
      expect(find.text('timeline slot'), findsOneWidget);
      expect(tester.getSize(find.text('timeline slot')), isNot(Size.zero));
    },
  );
}
