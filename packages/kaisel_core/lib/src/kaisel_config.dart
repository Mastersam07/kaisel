import 'dart:async';

import 'package:meta/meta.dart';

import 'kaisel_notifier.dart';
import 'kaisel_route.dart';
import 'kaisel_stack_codec.dart';

/// The configuration that flows between the URL bar and the router.
///
/// The Flutter `Router` widget asks the delegate for a configuration
/// (to update the browser URL) and hands one back when a URL changes
/// (to restore in-app state). The configuration describes the main
/// router's stack plus an optional nested-router state — whichever
/// nested router (shell or module) is currently on top of the main
/// stack.
///
/// ```dart
/// // URL  →  KaiselConfig
/// //   /home/products/sku-42
/// //   ↓
/// //   KaiselConfig(
/// //     mainStack: [MainShell()],
/// //     nestedState: KaiselShellConfig(
/// //       activeBranch: 0,
/// //       activeBranchStack: [HomeRoot(), ProductDetail('sku-42')],
/// //     ),
/// //   )
/// //
/// //   /checkout/confirm
/// //   ↓
/// //   KaiselConfig(
/// //     mainStack: [CheckoutMount()],
/// //     nestedState: KaiselModuleConfig(
/// //       stack: [CheckoutCart(), CheckoutShipping(), CheckoutConfirm()],
/// //     ),
/// //   )
/// ```
///
/// Only one nested router can be on top of the main stack at a time,
/// so `nestedState` is a sealed [KaiselNestedConfig] — at most one
/// kind, statically enforced.
@immutable
class KaiselConfig<R extends KaiselRoute> {
  /// Create a configuration with a main stack and optional nested
  /// state (shell or module).
  KaiselConfig({required List<R> mainStack, this.nestedState})
    : assert(mainStack.isNotEmpty, 'mainStack must not be empty'),
      mainStack = List<R>.unmodifiable(mainStack);

  /// The main router's stack — the outer navigation history.
  final List<R> mainStack;

  /// State of the currently-mounted nested router (shell or module),
  /// if any. `null` when no nested router is on top, or when the
  /// codec didn't bother to describe it.
  final KaiselNestedConfig? nestedState;

  /// Convenience for migration: a config with just a stack.
  factory KaiselConfig.stackOnly(List<R> stack) =>
      KaiselConfig<R>(mainStack: stack);

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    if (other is! KaiselConfig<R>) return false;
    return _listEquals(mainStack, other.mainStack) &&
        nestedState == other.nestedState;
  }

  @override
  int get hashCode => Object.hash(Object.hashAll(mainStack), nestedState);

  @override
  String toString() =>
      'KaiselConfig(mainStack: $mainStack, '
      'nestedState: $nestedState)';
}

/// State of a nested router (shell, module, future kinds) at the
/// moment a URL is captured. Sealed so [KaiselConfig.nestedState] can
/// carry at most one kind, statically.
///
/// Pattern-match in your codec:
///
/// ```dart
/// Uri encode(KaiselConfig<AppRoute> config) {
///   return switch ((config.mainStack.last, config.nestedState)) {
///     (MainShell(), final KaiselShellConfig shell)   => _encodeShell(shell),
///     (CheckoutMount(), final KaiselModuleConfig m)  => _encodeCheckout(m),
///     // ...
///   };
/// }
/// ```
sealed class KaiselNestedConfig {
  /// Const constructor so subclasses can be `const`.
  const KaiselNestedConfig();
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
class KaiselShellConfig extends KaiselNestedConfig {
  /// Create a shell configuration.
  KaiselShellConfig({
    required this.activeBranch,
    required List<KaiselRoute> activeBranchStack,
  }) : assert(activeBranch >= 0, 'activeBranch must be non-negative'),
       assert(
         activeBranchStack.isNotEmpty,
         'activeBranchStack must not be empty',
       ),
       activeBranchStack = List<KaiselRoute>.unmodifiable(activeBranchStack);

  /// Index of the currently-active branch.
  final int activeBranch;

  /// Stack of the active branch. Type-erased to [KaiselRoute]
  /// because different branches in a [KaiselBranchedShell] have
  /// different sealed route types.
  final List<KaiselRoute> activeBranchStack;

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    if (other is! KaiselShellConfig) return false;
    return activeBranch == other.activeBranch &&
        _listEquals(activeBranchStack, other.activeBranchStack);
  }

  @override
  int get hashCode =>
      Object.hash(activeBranch, Object.hashAll(activeBranchStack));

  @override
  String toString() =>
      'KaiselShellConfig(activeBranch: $activeBranch, '
      'activeBranchStack: $activeBranchStack)';
}

/// Configuration for a mounted [RouteModule].
///
/// A module is a self-contained routing unit — its own sealed
/// subtype, its own initial stack, its own page builder. Unlike a
/// shell (which aggregates multiple parallel branches), a module is
/// a single nested router rendered as a normal page.
///
/// `KaiselModuleConfig` captures the module's internal stack so a URL
/// like `/checkout/confirm` can be encoded as
/// `mainStack: [CheckoutMount]` plus `nestedState: KaiselModuleConfig(
/// stack: [Cart, Shipping, Confirm])` and round-trip on deep link.
@immutable
class KaiselModuleConfig extends KaiselNestedConfig {
  /// Create a module configuration.
  KaiselModuleConfig({required List<KaiselRoute> stack})
    : assert(stack.isNotEmpty, 'module stack must not be empty'),
      stack = List<KaiselRoute>.unmodifiable(stack);

  /// The module's internal stack. Type-erased to [KaiselRoute]; the
  /// concrete [RouteModule] knows the real subtype.
  final List<KaiselRoute> stack;

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    if (other is! KaiselModuleConfig) return false;
    return _listEquals(stack, other.stack);
  }

  @override
  int get hashCode => Object.hashAll(stack);

  @override
  String toString() => 'KaiselModuleConfig(stack: $stack)';
}

/// Maps URLs to and from a full [KaiselConfig].
///
/// Supersedes [KaiselStackCodec] when you want URLs to address state
/// inside a nested router (shell or module). A `KaiselConfigCodec`
/// returns / accepts the outer configuration; the codec decides how
/// to flatten the nested state into the URL path (and back).
///
/// If you don't need nested URLs, keep your existing [KaiselStackCodec]
/// and pass it via [KaiselRouteInformationParser.fromStackCodec].
///
/// ```dart
/// class AppCodec implements KaiselConfigCodec<AppRoute> {
///   const AppCodec();
///
///   @override
///   Uri encode(KaiselConfig<AppRoute> config) {
///     return switch ((config.mainStack.last, config.nestedState)) {
///       (Splash(), _)   => Uri(path: '/'),
///       (Login(), _)    => Uri(path: '/login'),
///       (Settings(), _) => Uri(path: '/settings'),
///       (MainShell(), final KaiselShellConfig shell) => _encodeShell(shell),
///       (CheckoutMount(), final KaiselModuleConfig m) => _encodeCheckout(m),
///       _ => Uri(path: '/'),
///     };
///   }
///   // ... decode
/// }
/// ```
abstract class KaiselConfigCodec<R extends KaiselRoute> {
  /// Const constructor so subclasses can be `const`.
  const KaiselConfigCodec();

  /// Encode a configuration into a URL.
  Uri encode(KaiselConfig<R> config);

  /// Decode a URL into a configuration, or return `null` if
  /// unrecognised (the parser will then use the fallback stack).
  ///
  /// May be asynchronous: a deep link's destination can depend on state that
  /// has to be read first, such as an entitlement, a feature flag, or a
  /// cached profile.
  /// Returning a plain value stays valid, so synchronous codecs need no
  /// change.
  FutureOr<KaiselConfig<R>?> decode(Uri uri);
}

/// Adapter so a [KaiselStackCodec] (stack-only URLs) works wherever
/// a [KaiselConfigCodec] is required.
///
/// Useful for migrating apps that don't need nested URLs yet — wrap
/// the existing stack codec instead of rewriting it.
class StackToConfigCodec<R extends KaiselRoute>
    implements KaiselConfigCodec<R> {
  /// Wrap [stackCodec]. The resulting config codec ignores
  /// [KaiselConfig.nestedState] entirely; nested state never round-trips
  /// through the URL.
  const StackToConfigCodec(this.stackCodec);

  /// The wrapped stack-only codec.
  final KaiselStackCodec<R> stackCodec;

  @override
  Uri encode(KaiselConfig<R> config) => stackCodec.encode(config.mainStack);

  @override
  FutureOr<KaiselConfig<R>?> decode(Uri uri) {
    final stack = stackCodec.decode(uri);
    return switch (stack) {
      final Future<List<R>?> pending => pending.then(_toConfig),
      _ => _toConfig(stack),
    };
  }

  KaiselConfig<R>? _toConfig(List<R>? stack) =>
      stack == null ? null : KaiselConfig<R>(mainStack: stack);
}

// Nested-router host machinery
//
// The delegate is the host. A mounted nested router (a branched shell
// or a module mount) registers itself with the host as a "nested
// handle"; the host captures and restores the topmost registered
// handle's config when the URL bar asks.
//
// These interfaces are public so the delegate and the nested router
// implementations can talk across files, but they're not exported
// from `package:kaisel/kaisel.dart` — typical apps never name them.

/// Non-generic handle a nested router (branched shell or module
/// mount) exposes to the surrounding [KaiselRouterDelegate] so the URL
/// can describe the nested router's state.
abstract class KaiselNestedHandle implements KaiselListenable {
  /// The runtime type of [KaiselNestedConfig] this handle produces and
  /// accepts. Used by the host to match a decoded URL configuration
  /// to the right registered handle.
  ///
  /// Shell handles return `KaiselShellConfig`; module handles return
  /// `KaiselModuleConfig`.
  Type get configType;

  /// Capture the handle's current state for inclusion in the URL.
  KaiselNestedConfig captureConfig();

  /// Apply a captured config. Implementations should silently ignore
  /// configs whose runtime type doesn't match [configType] — the host
  /// filters before calling, but a defensive check costs nothing.
  Future<void> restoreFromConfig(KaiselNestedConfig config);

  /// Whether the nested router's most recent committed change should overwrite
  /// the browser history entry rather than add one — the nested counterpart of
  /// [KaiselNavigator.replacesHistoryEntry], read by the host when the nested
  /// state drives the URL. Defaults to `false` (a push / branch switch adds an
  /// entry).
  bool get replacesHistoryEntry => false;
}

/// Interface implemented by [KaiselRouterDelegate] so a mounted nested
/// router (shell or module) can register itself as the URL-addressable
/// nested handle.
///
/// Multiple handles may register at once (e.g., a shell mounted under
/// a module that's currently on top). The host treats the most
/// recently registered handle as the **active** one — its config
/// rides the URL.
abstract class KaiselNestedHost {
  /// Register [handle] as a nested-router source. Becomes the active
  /// handle (most recent wins).
  ///
  /// If a configuration was decoded before any matching handle was
  /// registered (cold-start deep link), the host applies it as soon
  /// as a handle whose [KaiselNestedHandle.configType] matches the
  /// pending config's runtime type registers.
  void registerNested(KaiselNestedHandle handle);

  /// Unregister [handle]. The next-most-recently-registered handle
  /// becomes active again (if any).
  void unregisterNested(KaiselNestedHandle handle);
}

bool _listEquals(List<Object?> a, List<Object?> b) {
  if (identical(a, b)) return true;
  if (a.length != b.length) return false;
  for (var i = 0; i < a.length; i++) {
    if (a[i] != b[i]) return false;
  }
  return true;
}
