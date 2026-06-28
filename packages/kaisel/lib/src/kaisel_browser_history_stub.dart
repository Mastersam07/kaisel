import 'kaisel_browser_history.dart';

/// Non-web implementation: there is no browser history, so every member is
/// inert and callers fall back to a logical [pop].
KaiselBrowserHistory createBrowserHistory() => const _NoopBrowserHistory();

class _NoopBrowserHistory implements KaiselBrowserHistory {
  const _NoopBrowserHistory();

  @override
  bool get isWeb => false;

  @override
  int get depth => 0;

  @override
  void go(int delta) {}
}
