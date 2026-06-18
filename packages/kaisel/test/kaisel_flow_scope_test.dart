import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kaisel/kaisel.dart';

// FlowScope.updateShouldNotify in isolation: under the flows-as-routes model a
// flow's scope is built once, so this exercises the InheritedWidget contract
// directly rather than through a live flow.

int _dependentBuilds = 0;

void _noop(Object? value) {}

class _Dependent extends StatelessWidget {
  const _Dependent();

  @override
  Widget build(BuildContext context) {
    FlowScope.of(context); // depend on the scope
    _dependentBuilds++;
    return const SizedBox.shrink();
  }
}

void main() {
  testWidgets('FlowScope rebuilds dependents only when the completion '
      'callback changes', (tester) async {
    _dependentBuilds = 0;
    Widget tree(void Function(Object?) onComplete) => Directionality(
      textDirection: TextDirection.ltr,
      child: FlowScope(onComplete: onComplete, child: const _Dependent()),
    );

    await tester.pumpWidget(tree((_) {}));
    expect(_dependentBuilds, 1);

    // A different callback instance → updateShouldNotify returns true → the
    // dependent rebuilds. (The child is a const instance, so it only rebuilds
    // via the inherited-widget dependency, not the parent.)
    await tester.pumpWidget(tree(_noop));
    expect(_dependentBuilds, 2);

    // The same callback instance → updateShouldNotify returns false → no
    // rebuild.
    await tester.pumpWidget(tree(_noop));
    expect(_dependentBuilds, 2);
  });
}
