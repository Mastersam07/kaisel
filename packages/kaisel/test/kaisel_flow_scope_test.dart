import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kaisel/kaisel.dart';

// FlowScope.updateShouldNotify in isolation — a flow's scope is built once
// under flows-as-routes, so this exercises it directly.

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

    // The const child only rebuilds via the inherited-widget dependency, so
    // these assertions isolate updateShouldNotify: true on a changed callback,
    // false on the same one.
    await tester.pumpWidget(tree(_noop));
    expect(_dependentBuilds, 2);

    await tester.pumpWidget(tree(_noop));
    expect(_dependentBuilds, 2);
  });
}
