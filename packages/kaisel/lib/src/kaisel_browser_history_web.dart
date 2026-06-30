import 'dart:js_interop';

import 'package:web/web.dart' as web;

import 'kaisel_browser_history.dart';

/// Web implementation backed by `window.history`.
KaiselBrowserHistory createBrowserHistory() => const _WebBrowserHistory();

class _WebBrowserHistory implements KaiselBrowserHistory {
  const _WebBrowserHistory();

  @override
  bool get isWeb => true;

  @override
  int get depth {
    // The Flutter web engine tags each multi-entry history state with a
    // `serialCount` — the current entry's index in the app's own history.
    final state = web.window.history.state.dartify();
    if (state is Map && state['serialCount'] is num) {
      return (state['serialCount'] as num).toInt();
    }
    return 0;
  }

  @override
  void go(int delta) => web.window.history.go(delta);
}
