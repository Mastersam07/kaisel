import 'package:meta/meta.dart';

import 'kaisel_browser_history_stub.dart'
    if (dart.library.js_interop) 'kaisel_browser_history_web.dart'
    as impl;

/// A thin seam over the browser's session history, used by
/// `context.historyBack` / `context.historyGo` for history-aligned back
/// navigation on the web. Off the web every member is inert.
///
/// The real implementation is selected by conditional import, so `kaisel_core`
/// (and every non-web build) never references `package:web`.
abstract interface class KaiselBrowserHistory {
  /// Whether the running platform is the web, where browser history exists.
  bool get isWeb;

  /// How many app history entries sit behind the current one — the engine's
  /// `serialCount`. `0` means the current entry is the first the app created
  /// (e.g. a cold deep link), so there is nothing to go back to. Always `0`
  /// off the web.
  int get depth;

  /// Move the history pointer by [delta] (negative goes back, positive
  /// forward), like `window.history.go`. A no-op off the web.
  void go(int delta);

  /// The active implementation. Web on the web, an inert stub elsewhere.
  static KaiselBrowserHistory instance = impl.createBrowserHistory();

  /// Swap [instance] for a test double, returning a callback that restores the
  /// real one (pass it to `addTearDown`).
  @visibleForTesting
  static void Function() debugOverride(KaiselBrowserHistory value) {
    final previous = instance;
    instance = value;
    return () => instance = previous;
  }
}
