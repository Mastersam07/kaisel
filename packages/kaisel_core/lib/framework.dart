/// Framework-facing internals that kaisel_core exposes to the `kaisel` Flutter
/// package.
///
/// **Not part of the public API.** Application code should import
/// `package:kaisel_core/kaisel_core.dart` (or `package:kaisel/kaisel.dart`) instead.
/// These symbols — the identity-keyed stack entries, the nested-router host
/// contracts, and the pure-Dart change-notifier — are the seam the kaisel
/// widgets build on; they live here, rather than in the public barrel, so the
/// app-facing surface stays small.
library;

export 'kaisel_core.dart';
export 'src/kaisel_config.dart' show KaiselNestedHandle, KaiselNestedHost;
export 'src/kaisel_inspector.dart';
export 'src/kaisel_notifier.dart' show KaiselChangeNotifier, KaiselListenable;
export 'src/kaisel_router.dart'
    show
        KaiselGuardRun,
        KaiselGuardStep,
        KaiselNoOp,
        KaiselStackEntry,
        kaiselNextOriginSeq,
        kaiselOriginFrames;
