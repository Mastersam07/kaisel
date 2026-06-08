import 'package:flutter/foundation.dart' show listEquals;
import 'package:flutter/widgets.dart';

/// Caches its [child], rebuilding it only when [value] changes (value equality,
/// list-aware) so an unchanged panel keeps its subtree and state.
class Memo extends StatefulWidget {
  /// Create a memo wrapper over [child], keyed on [value].
  const Memo({super.key, required this.value, required this.child});

  /// The slice this child depends on. When it stays value-equal across a
  /// rebuild, [child] is not rebuilt.
  final Object? value;

  /// The widget to cache.
  final Widget child;

  @override
  State<Memo> createState() => _MemoState();
}

class _MemoState extends State<Memo> {
  late Widget _child = widget.child;

  @override
  void didUpdateWidget(Memo oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!memoEquals(oldWidget.value, widget.value)) _child = widget.child;
  }

  @override
  Widget build(BuildContext context) => _child;
}

/// Equality used by [Memo]: structural over a 2-tuple or a list, otherwise `==`.
bool memoEquals(Object? a, Object? b) {
  if (a is (Object?, Object?) && b is (Object?, Object?)) {
    return a.$1 == b.$1 && a.$2 == b.$2;
  }
  if (a is List && b is List) return listEquals(a, b);
  return a == b;
}
