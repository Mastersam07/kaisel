import 'package:meta/meta.dart';

import 'kaisel_config.dart';
import 'kaisel_route.dart';

/// Type-erased view of [ModuleStackCodec]. Module authors implement
/// the typed [ModuleStackCodec] subclass; the composer
/// ([ConfigCodecWithModules]) uses this untyped interface so a single
/// `List<ModuleMount>` can hold codecs for modules with different
/// internal route types.
///
/// Most app code doesn't reference this directly. It's the seam
/// between the generic-typed module side and the heterogeneous
/// host side.
abstract class UntypedModuleStackCodec {
  /// Const constructor so subclasses can be `const`.
  const UntypedModuleStackCodec();

  /// Encode any stack of routes to URL segments. Implementations
  /// downcast to their module's specific route type internally.
  List<String> encodeAny(List<KaiselRoute> stack);

  /// Decode URL segments to a stack of routes, or `null` if the
  /// segments don't match any known route in this module.
  /// Implementations upcast their specific route subtype to
  /// [KaiselRoute] for the composer.
  List<KaiselRoute>? decodeAny(List<String> segments);
}

/// Codec for a module's URL structure, relative to whatever prefix
/// the host mounts the module at.
///
/// Module authors implement this to make their module
/// URL-addressable. The host composes it via
/// [ConfigCodecWithModules] without needing to know the module's
/// internal route types. The module ships as a self-contained unit.
///
/// ```dart
/// class CheckoutModuleCodec extends ModuleStackCodec<CheckoutRoute> {
///   const CheckoutModuleCodec();
///
///   @override
///   List<String> encode(List<CheckoutRoute> stack) => switch (stack.last) {
///     CheckoutCart() => const [],
///     CheckoutShipping() => const ['shipping'],
///     CheckoutConfirm() => const ['confirm'],
///   };
///
///   @override
///   List<CheckoutRoute>? decode(List<String> segments) => switch (segments) {
///     [] => const [CheckoutCart()],
///     ['shipping'] => const [CheckoutCart(), CheckoutShipping()],
///     ['confirm'] => const [
///       CheckoutCart(), CheckoutShipping(), CheckoutConfirm(),
///     ],
///     _ => null,
///   };
/// }
/// ```
///
/// Conventions:
///
/// * `encode` of the module's root state returns `const []`. The
///   mount prefix alone (e.g. `/checkout`) is enough.
/// * `decode` of `const []` should return the module's root stack
///   (typically `initialStack`), so visiting just the prefix lands
///   the module at its starting position.
/// * Return `null` from `decode` for unknown segment patterns. The
///   parser falls back to its configured fallback stack.
abstract class ModuleStackCodec<R extends KaiselRoute>
    implements UntypedModuleStackCodec {
  /// Const constructor so subclasses can be `const`.
  const ModuleStackCodec();

  /// Encode the module's stack to URL segments. The result is
  /// appended to the host's mount prefix to produce the full URL.
  /// Return `const []` for the module's root state.
  List<String> encode(List<R> stack);

  /// Decode URL segments (relative to the mount prefix) into a
  /// module stack. Return `null` if the segments don't match any
  /// known route in this module.
  List<R>? decode(List<String> segments);

  @override
  List<String> encodeAny(List<KaiselRoute> stack) => encode(stack.cast<R>());

  @override
  List<KaiselRoute>? decodeAny(List<String> segments) {
    final result = decode(segments);
    return result?.cast<KaiselRoute>();
  }
}

/// A module mount declaration: the host's marker route, the URL
/// prefix the module answers to, and the module's URL codec.
///
/// Used inside [ConfigCodecWithModules.modules] to wire URL routing
/// across module boundaries.
@immutable
class ModuleMount<HostR extends KaiselRoute> {
  /// Create a mount declaration.
  ///
  /// [mountRoute] is the marker route in the host's `AppRoute` that
  /// puts the module's [KaiselModuleMount] on the main stack.
  /// [prefix] is the URL prefix this module answers to. Leading
  /// slash is optional; `/checkout` and `checkout` produce the same
  /// segments. [codec] is the module's URL codec, typically a typed
  /// [ModuleStackCodec] subclass.
  const ModuleMount({
    required this.mountRoute,
    required this.prefix,
    required this.codec,
  });

  /// The marker route on the host's main stack. When the URL matches
  /// this mount's prefix, the composer produces a configuration
  /// whose `mainStack` ends with [mountRoute] and whose `nestedState`
  /// is a [KaiselModuleConfig] holding the module's decoded stack.
  final HostR mountRoute;

  /// URL prefix this module answers to. Leading slash optional.
  final String prefix;

  /// The module's own codec for URLs under [prefix].
  final UntypedModuleStackCodec codec;

  /// Internal: split [prefix] into segments, dropping empties.
  /// Recomputed on each call. Call sites are cold (navigation
  /// events only).
  List<String> _prefixSegments() {
    return prefix.split('/').where((s) => s.isNotEmpty).toList(growable: false);
  }
}

/// A [KaiselConfigCodec] that composes a base codec with one or more
/// module mounts.
///
/// URLs whose path starts with a mount's prefix are routed to the
/// module's codec; everything else goes to [baseCodec]. The host's
/// main codec doesn't need to know the module's internal URL
/// structure; modules ship that themselves.
///
/// ```dart
/// final codec = ConfigCodecWithModules<AppRoute>(
///   baseCodec: const _MainAppCodec(),
///   modules: const [
///     ModuleMount(
///       mountRoute: CheckoutMount(),
///       prefix: '/checkout',
///       codec: CheckoutModuleCodec(),
///     ),
///   ],
/// );
/// ```
///
/// On `encode`, the composer inspects the top of the main stack: if
/// it matches a mount's `mountRoute`, it uses that mount's codec to
/// produce the segments after the prefix. Otherwise it delegates to
/// [baseCodec].
///
/// On `decode`, the composer walks [modules] in order, looking for
/// the first whose prefix matches the URL's leading segments. If a
/// match is found, the module codec gets the relative segments. If
/// the module codec returns `null` (URL inside the prefix but
/// unrecognised), the composer returns `null` directly. It does NOT
/// fall through to [baseCodec], because the URL clearly belongs to
/// this module's namespace.
class ConfigCodecWithModules<R extends KaiselRoute>
    implements KaiselConfigCodec<R> {
  /// Create a composer.
  ///
  /// [modules] are tried in order during decode; if multiple mounts
  /// could match (e.g. `/checkout` and `/checkout/v2`), list the
  /// longer prefix first to avoid partial matches.
  const ConfigCodecWithModules({
    required this.baseCodec,
    required this.modules,
  });

  /// Codec for routes outside any module. Receives configurations
  /// whose top route is NOT a registered mount route.
  final KaiselConfigCodec<R> baseCodec;

  /// Module mount declarations. Order matters: longer prefixes
  /// should come first.
  final List<ModuleMount<R>> modules;

  @override
  Uri encode(KaiselConfig<R> config) {
    final top = config.mainStack.last;
    final mount = _mountForRoute(top);
    if (mount != null) {
      final nested = config.nestedState;
      if (nested is KaiselModuleConfig) {
        final segments = mount.codec.encodeAny(nested.stack);
        return Uri(pathSegments: ['', ...mount._prefixSegments(), ...segments]);
      }
      // Mount route is on top but no module state yet (the mount has
      // been pushed but the module widget hasn't registered yet, or a
      // codec produced this state). Encode just the prefix.
      return Uri(pathSegments: ['', ...mount._prefixSegments()]);
    }
    return baseCodec.encode(config);
  }

  @override
  KaiselConfig<R>? decode(Uri uri) {
    final segments = uri.pathSegments
        .where((s) => s.isNotEmpty)
        .toList(growable: false);

    for (final mount in modules) {
      final prefix = mount._prefixSegments();
      if (_segmentsStartWith(segments, prefix)) {
        final relative = segments.sublist(prefix.length);
        final moduleStack = mount.codec.decodeAny(relative);
        if (moduleStack != null && moduleStack.isNotEmpty) {
          return KaiselConfig<R>(
            mainStack: [mount.mountRoute],
            nestedState: KaiselModuleConfig(stack: moduleStack),
          );
        }
        // Prefix matched but the module codec rejected the relative
        // segments. The URL clearly belongs to this module's
        // namespace; don't silently fall through to baseCodec.
        return null;
      }
    }

    return baseCodec.decode(uri);
  }

  ModuleMount<R>? _mountForRoute(R route) {
    for (final mount in modules) {
      if (mount.mountRoute == route) return mount;
    }
    return null;
  }

  static bool _segmentsStartWith(List<String> uri, List<String> prefix) {
    if (uri.length < prefix.length) return false;
    for (var i = 0; i < prefix.length; i++) {
      if (uri[i] != prefix[i]) return false;
    }
    return true;
  }
}
