/// Shell and module rules — composing per-branch / per-module rule sets into a
/// single [Rule] that produces a [KaiselShellConfig] / [KaiselModuleConfig].
library;

import '../kaisel_config.dart';
import '../kaisel_route.dart';
import 'rule.dart';

/// A branched-shell rule.
///
/// [host] is the main-stack route that renders the shell. [branches] maps a
/// **typed branch token** [B] (e.g. an `enum AppBranch` shared with the shell
/// widget, so the codec index and the shell's order can't drift) to that
/// branch's rule set, and [index] maps a token to the `activeBranch` int the
/// shell uses.
///
/// Decoding a URL that one branch's rules match restores into that branch (and
/// selects it); encoding a config whose nested state is this shell routes
/// through the active branch's rules. Each branch owns its own URLs, so a URL
/// can't be claimed by the wrong branch.
Rule<R> shellRule<R extends KaiselRoute, B>({
  required R host,
  required int Function(B branch) index,
  required Map<B, List<Rule<R>>> branches,
}) {
  KaiselConfig<R>? decode(Uri uri) {
    for (final entry in branches.entries) {
      for (final rule in entry.value) {
        final config = rule.decode(uri);
        if (config != null) {
          return KaiselConfig<R>(
            mainStack: <R>[host],
            nestedState: KaiselShellConfig(
              activeBranch: index(entry.key),
              activeBranchStack: config.mainStack,
            ),
          );
        }
      }
    }
    return null;
  }

  Uri? encode(KaiselConfig<R> config) {
    final nested = config.nestedState;
    if (nested is! KaiselShellConfig) return null;
    for (final entry in branches.entries) {
      if (index(entry.key) != nested.activeBranch) continue;
      final branchConfig = KaiselConfig<R>(
        mainStack: nested.activeBranchStack.cast<R>(),
      );
      for (final rule in entry.value) {
        final uri = rule.encode(branchConfig);
        if (uri != null) return uri;
      }
    }
    return null;
  }

  return Rule<R>.custom(decode: decode, encode: encode);
}

/// A module rule: a module mounted under the literal [prefix] segments and
/// rendered by the main-stack [host] route.
///
/// The module's [rules] are written *without* the prefix; a URL `prefix/<rest>`
/// has its prefix stripped and `<rest>` decoded by them into the module's
/// internal stack, and encoding re-adds the prefix.
Rule<R> moduleRule<R extends KaiselRoute>({
  required R host,
  required List<String> prefix,
  required List<Rule<R>> rules,
}) {
  KaiselConfig<R>? decode(Uri uri) {
    final segments = uri.pathSegments.where((s) => s.isNotEmpty).toList();
    if (segments.length < prefix.length) return null;
    for (var i = 0; i < prefix.length; i++) {
      if (segments[i] != prefix[i]) return null;
    }
    final rest = segments.skip(prefix.length).join('/');
    final subUri = Uri(
      path: '/$rest',
      queryParameters: uri.queryParameters.isEmpty ? null : uri.queryParameters,
    );
    for (final rule in rules) {
      final config = rule.decode(subUri);
      if (config != null) {
        return KaiselConfig<R>(
          mainStack: <R>[host],
          nestedState: KaiselModuleConfig(stack: config.mainStack),
        );
      }
    }
    return null;
  }

  Uri? encode(KaiselConfig<R> config) {
    final nested = config.nestedState;
    if (nested is! KaiselModuleConfig) return null;
    final moduleConfig = KaiselConfig<R>(mainStack: nested.stack.cast<R>());
    for (final rule in rules) {
      final sub = rule.encode(moduleConfig);
      if (sub != null) {
        final tail = sub.pathSegments.where((s) => s.isNotEmpty);
        return Uri(
          path: '/${[...prefix, ...tail].join('/')}',
          queryParameters: sub.queryParameters.isEmpty
              ? null
              : sub.queryParameters,
        );
      }
    }
    return null;
  }

  return Rule<R>.custom(decode: decode, encode: encode);
}
