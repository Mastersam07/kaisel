/// Framework-facing internals that gate_core exposes to the `gate` Flutter
/// package.
///
/// **Not part of the public API.** Application code should import
/// `package:gate_core/gate_core.dart` (or `package:gate/gate.dart`) instead.
/// These symbols — the identity-keyed stack entries, the nested-router host
/// contracts, and the pure-Dart change-notifier — are the seam the gate
/// widgets build on; they live here, rather than in the public barrel, so the
/// app-facing surface stays small.
library;

export 'gate_core.dart';
export 'src/gate_config.dart' show GateNestedHandle, GateNestedHost;
export 'src/gate_notifier.dart' show GateChangeNotifier, GateListenable;
export 'src/gate_router.dart' show GateStackEntry;
