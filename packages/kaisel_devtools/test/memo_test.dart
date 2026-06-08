import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kaisel_devtools/src/memo.dart';

void main() {
  group('memoEquals', () {
    test('scalars compare by ==', () {
      expect(memoEquals(1, 1), isTrue);
      expect(memoEquals(1, 2), isFalse);
      expect(memoEquals(null, null), isTrue);
      expect(memoEquals('a', 'a'), isTrue);
    });

    test('lists compare structurally', () {
      expect(memoEquals(<int>[1, 2], <int>[1, 2]), isTrue);
      expect(memoEquals(<int>[1, 2], <int>[1, 3]), isFalse);
      expect(memoEquals(<int>[1], <int>[1, 2]), isFalse);
    });

    test('2-tuples compare field-wise', () {
      expect(memoEquals((1, 'x'), (1, 'x')), isTrue);
      expect(memoEquals((1, 'x'), (1, 'y')), isFalse);
      expect(memoEquals((1, 'x'), (2, 'x')), isFalse);
    });
  });

  testWidgets('Memo rebuilds its child only when value changes', (
    tester,
  ) async {
    var builds = 0;
    Widget app(Object? value) => MaterialApp(
      home: Memo(
        value: value,
        child: Builder(
          builder: (_) {
            builds++;
            return const SizedBox();
          },
        ),
      ),
    );

    await tester.pumpWidget(app(1));
    expect(builds, 1);

    await tester.pumpWidget(app(1));
    expect(builds, 1);

    await tester.pumpWidget(app(2));
    expect(builds, 2);

    await tester.pumpWidget(app(<int>[1]));
    expect(builds, 3);
    await tester.pumpWidget(app(<int>[1]));
    expect(builds, 3);
    await tester.pumpWidget(app(<int>[2]));
    expect(builds, 4);
  });

  testWidgets('Memo keeps child state across an unchanged-value rebuild', (
    tester,
  ) async {
    Widget app(Object? value) => MaterialApp(
      home: Material(
        child: Memo(value: value, child: _Counter()),
      ),
    );

    await tester.pumpWidget(app('same'));
    await tester.tap(find.byType(TextButton));
    await tester.pump();
    expect(find.text('1'), findsOneWidget);

    await tester.pumpWidget(app('same'));
    expect(find.text('1'), findsOneWidget);
  });
}

class _Counter extends StatefulWidget {
  @override
  State<_Counter> createState() => _CounterState();
}

class _CounterState extends State<_Counter> {
  int _n = 0;

  @override
  Widget build(BuildContext context) {
    return TextButton(
      onPressed: () => setState(() => _n++),
      child: Text('$_n'),
    );
  }
}
