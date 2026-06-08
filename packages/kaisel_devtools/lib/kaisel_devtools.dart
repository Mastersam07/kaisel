/// The kaisel DevTools extension — a live inspector for kaisel's navigation
/// state (stacks, branches, modules, modal flows, guard traces, and the
/// encoded URL).
///
/// The runtime hook that publishes the data lives in `kaisel` /
/// `kaisel_core` (`KaiselInspector`); this package is the DevTools-side UI,
/// entered from `main.dart`.
library;

export 'src/inspector_view.dart';
