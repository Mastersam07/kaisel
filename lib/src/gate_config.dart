import 'package:flutter/foundation.dart';

import 'gate_route.dart';
import 'gate_stack_codec.dart';

/// The configuration that flows between the URL bar and the router.
///
/// The Flutter `Router` widget asks the delegate for a configuration
/// (to update the browser URL) and hands one back when a URL changes
/// (to restore in-app state). Through v0.4 that configuration was just
/// the main router's stack (`List<R>`). v0.5 enriches it so the URL
/// can address state inside a branched shell, too:
///
/// ```dart
/// // URL  →  GateConfig
/// //   /home/products/sku-42
/// //   ↓
/// //   GateConfig(
/// //     mainStack: [MainShell()],
/// //     shellState: GateShellConfig(
/// //       activeBranch: 0,
/// //       activeBranchStack: [HomeRoot(), ProductDetail('sku-42')],
/// //     ),
/// //   )
/// ```
///
/// The shell state describes only the **active** branch's stack;
/// inactive branches keep whatever in-memory state they already had.
/// Switching to Discover and back to Home preserves Home's stack
/// (and surfaces back through the URL on the next capture).
@immutable
class GateConfig<R extends GateRoute> {
  /// Create a configuration with a main stack and optional shell
  /// state.
  GateConfig({
    required List<R> mainStack,
    this.shellState,
  })  : assert(mainStack.isNotEmpty, 'mainStack must not be empty'),
        mainStack = List<R>.unmodifiable(mainStack);

  /// The main router's stack — the outer navigation history.
  final List<R> mainStack;

  /// State of the currently-mounted shell, if any. `null` if no
  /// shell is on the main stack (or if the codec didn't bother to
  /// describe it).
  final GateShellConfig? shellState;

  /// Convenience for migration: a config with just a stack.
  factory GateConfig.stackOnly(List<R> stack) =>
      GateConfig<R>(mainStack: stack);

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    if (other is! GateConfig<R>) return false;
    return _listEquals(mainStack, other.mainStack) &&
        shellState == other.shellState;
  }

  @override
  int get hashCode => Object.hash(Object.hashAll(mainStack), shellState);

  @override
  String toString() => 'GateConfig(mainStack: $mainStack, '
      'shellState: $shellState)';
}

/// Configuration for a [BranchedShellRouter]. Describes which branch
/// is active and the active branch's stack only.
///
/// Inactive branches are deliberately not described: their state
/// lives in memory for the lifetime of the shell. If the user is on
/// `/home/products/x`, switches to Discover, then switches back, they
/// expect to find Home still showing `products/x`, not the home root.
/// Encoding inactive branches into URLs would make every tab switch
/// either a deep-link to all branches or destroy non-active history.
@immutable
class GateShellConfig {
  /// Create a shell configuration.
  GateShellConfig({
    required this.activeBranch,
    required List<GateRoute> activeBranchStack,
  })  : assert(activeBranch >= 0, 'activeBranch must be non-negative'),
        assert(
          activeBranchStack.isNotEmpty,
          'activeBranchStack must not be empty',
        ),
        activeBranchStack = List<GateRoute>.unmodifiable(activeBranchStack);

  /// Index of the currently-active branch.
  final int activeBranch;

  /// Stack of the active branch. Type-erased to [GateRoute]
  /// because different branches in a [GateBranchedShell] have
  /// different sealed route types.
  final List<GateRoute> activeBranchStack;

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    if (other is! GateShellConfig) return false;
    return activeBranch == other.activeBranch &&
        _listEquals(activeBranchStack, other.activeBranchStack);
  }

  @override
  int get hashCode =>
      Object.hash(activeBranch, Object.hashAll(activeBranchStack));

  @override
  String toString() => 'GateShellConfig(activeBranch: $activeBranch, '
      'activeBranchStack: $activeBranchStack)';
}

/// Maps URLs to and from a full [GateConfig].
///
/// Supersedes [GateStackCodec] when you want URLs to address state
/// inside a branched shell. A `GateConfigCodec` returns / accepts the
/// outer configuration; the codec decides how to flatten the shell
/// state into the URL path (and back).
///
/// If you don't need shell URLs, keep your existing [GateStackCodec]
/// and pass it via [GateRouteInformationParser.fromStackCodec].
///
/// ```dart
/// class AppCodec implements GateConfigCodec<AppRoute> {
///   const AppCodec();
///
///   @override
///   Uri encode(GateConfig<AppRoute> config) {
///     final shell = config.shellState;
///     if (shell != null && config.mainStack.last is MainShell) {
///       return _encodeShell(shell);
///     }
///     return switch (config.mainStack.last) {
///       Splash() => Uri(path: '/'),
///       Login()  => Uri(path: '/login'),
///       Settings() => Uri(path: '/settings'),
///       _ => Uri(path: '/'),
///     };
///   }
///
///   Uri _encodeShell(GateShellConfig shell) => switch (shell.activeBranch) {
///         0 => switch (shell.activeBranchStack) {
///               [HomeRoot()] => Uri(path: '/home'),
///               [HomeRoot(), ProductDetail(:final id)] =>
///                 Uri(path: '/home/products/$id'),
///               _ => Uri(path: '/home'),
///             },
///         1 => Uri(path: '/discover'),
///         2 => Uri(path: '/profile'),
///         _ => Uri(path: '/'),
///       };
///
///   @override
///   GateConfig<AppRoute>? decode(Uri uri) => switch (uri.pathSegments) {
///         [] || [''] => GateConfig(mainStack: const [Splash()]),
///         ['home'] => GateConfig(
///               mainStack: const [MainShell()],
///               shellState: GateShellConfig(
///                 activeBranch: 0,
///                 activeBranchStack: const [HomeRoot()],
///               ),
///             ),
///         ['home', 'products', final id] => GateConfig(
///               mainStack: const [MainShell()],
///               shellState: GateShellConfig(
///                 activeBranch: 0,
///                 activeBranchStack: [const HomeRoot(), ProductDetail(id)],
///               ),
///             ),
///         _ => null,
///       };
/// }
/// ```
abstract class GateConfigCodec<R extends GateRoute> {
  /// Const constructor so subclasses can be `const`.
  const GateConfigCodec();

  /// Encode a configuration into a URL.
  Uri encode(GateConfig<R> config);

  /// Decode a URL into a configuration, or return `null` if
  /// unrecognised (the parser will then use the fallback stack).
  GateConfig<R>? decode(Uri uri);
}

/// Adapter so a v0.4 [GateStackCodec] (stack-only URLs) works wherever
/// a [GateConfigCodec] is required.
///
/// Useful for migrating apps that don't need shell URLs yet — wrap
/// the existing stack codec instead of rewriting it.
class StackToConfigCodec<R extends GateRoute> implements GateConfigCodec<R> {
  /// Wrap [stackCodec]. The resulting config codec ignores
  /// [GateConfig.shellState] entirely; shell state never round-trips
  /// through the URL.
  const StackToConfigCodec(this.stackCodec);

  /// The wrapped stack-only codec.
  final GateStackCodec<R> stackCodec;

  @override
  Uri encode(GateConfig<R> config) => stackCodec.encode(config.mainStack);

  @override
  GateConfig<R>? decode(Uri uri) {
    final stack = stackCodec.decode(uri);
    return stack == null ? null : GateConfig<R>(mainStack: stack);
  }
}

// ─────────────────────────────────────────────────────────────────────
// Shell-host machinery
//
// The delegate is the host. A mounted [GateBranchedShell] registers
// itself with the host as the active "restore handle"; the host calls
// captureConfig when Flutter asks for currentConfiguration, and
// restoreFromConfig when a URL change arrives that includes shell
// state.
//
// These interfaces are public so the delegate and the shell can talk
// across files, but they're not exported from `package:gate/gate.dart`
// — typical apps never name them.
// ─────────────────────────────────────────────────────────────────────

/// Non-generic handle a [GateBranchedShell] exposes to the surrounding
/// [GateRouterDelegate] so the URL can describe the shell's state.
abstract class GateShellRestoreHandle implements Listenable {
  /// Capture the shell's current state for inclusion in the URL.
  GateShellConfig captureConfig();

  /// Apply a shell state from a URL decode. The active branch is
  /// switched and its stack replaced; inactive branches are left alone.
  Future<void> restoreFromConfig(GateShellConfig config);
}

/// Interface implemented by [GateRouterDelegate] so a mounted shell
/// can register itself as the URL-addressable shell.
abstract class GateShellHost {
  /// Register [shell] as the active shell for URL capture/restore.
  /// If a configuration was decoded before any shell was registered,
  /// the host applies it now.
  void registerShell(GateShellRestoreHandle shell);

  /// Unregister [shell]. No-op if [shell] isn't the registered one.
  void unregisterShell(GateShellRestoreHandle shell);
}

// ─── helpers ─────────────────────────────────────────────────────────

bool _listEquals(List<Object?> a, List<Object?> b) {
  if (identical(a, b)) return true;
  if (a.length != b.length) return false;
  for (var i = 0; i < a.length; i++) {
    if (a[i] != b[i]) return false;
  }
  return true;
}
