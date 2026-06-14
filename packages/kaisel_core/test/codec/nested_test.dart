import 'package:kaisel_core/codec.dart';
import 'package:kaisel_core/kaisel_core.dart';
import 'package:test/test.dart';

sealed class _App extends KaiselRoute {
  const _App();
}

final class _ShellHost extends _App {
  const _ShellHost();
}

final class _HomeTab extends _App {
  const _HomeTab();
}

final class _SubletsFilter extends _App {
  const _SubletsFilter(this.location);
  final String? location;
  @override
  List<Object?> get props => [location];
}

final class _MatchesTab extends _App {
  const _MatchesTab({this.refresh});
  final bool? refresh;
  @override
  List<Object?> get props => [refresh];
}

final class _CheckoutMount extends _App {
  const _CheckoutMount();
}

final class _CartStep extends _App {
  const _CartStep();
}

final class _PaymentStep extends _App {
  const _PaymentStep(this.method);
  final String method;
  @override
  List<Object?> get props => [method];
}

enum _Branch { home, matches }

RouteCodec<_App> _codec() => RouteCodec<_App>(
  rules: [
    shellRule<_App, _Branch>(
      host: const _ShellHost(),
      index: (b) => b.index,
      branches: {
        _Branch.home: [
          fixed(const _HomeTab(), seg('home')),
          (seg('home') / seg('sublets_filter') / queryStrOpt('location'))
              .to((c) => _SubletsFilter(c.stringOrNull(0)))
              .from((r) => r is _SubletsFilter ? r.props : null),
        ],
        _Branch.matches: [
          (seg('matches') / queryBoolOpt('refresh'))
              .to((c) => _MatchesTab(refresh: c.booleanOrNull(0)))
              .from((r) => r is _MatchesTab ? r.props : null),
        ],
      },
    ),
    moduleRule<_App>(
      host: const _CheckoutMount(),
      prefix: ['checkout'],
      rules: [
        fixed(const _CartStep(), seg('cart')),
        (seg('payment') / str)
            .to((c) => _PaymentStep(c.string(0)))
            .from((r) => r is _PaymentStep ? r.props : null),
      ],
    ),
  ],
);

KaiselShellConfig _shell(int branch, List<KaiselRoute> stack) =>
    KaiselShellConfig(activeBranch: branch, activeBranchStack: stack);

void main() {
  final codec = _codec();

  group('shell decode', () {
    test('a branch URL restores into that branch and selects it', () {
      final config = codec.decode(Uri.parse('/home'));
      expect(config?.mainStack, const [_ShellHost()]);
      final nested = config?.nestedState;
      expect(nested, isA<KaiselShellConfig>());
      if (nested is KaiselShellConfig) {
        expect(nested.activeBranch, 0);
        expect(nested.activeBranchStack, const [_HomeTab()]);
      }
    });

    test('a deeper branch URL carries its query into the branch stack', () {
      final nested = codec
          .decode(Uri.parse('/home/sublets_filter?location=NYC'))
          ?.nestedState;
      expect(nested, isA<KaiselShellConfig>());
      if (nested is KaiselShellConfig) {
        expect(nested.activeBranch, 0);
        expect(nested.activeBranchStack, const [_SubletsFilter('NYC')]);
      }
    });

    test('a different branch decodes to its own index', () {
      final nested = codec.decode(Uri.parse('/matches'))?.nestedState;
      expect(nested, isA<KaiselShellConfig>());
      if (nested is KaiselShellConfig) {
        expect(nested.activeBranch, 1);
        expect(nested.activeBranchStack, const [_MatchesTab()]);
      }
    });
  });

  group('shell encode', () {
    test('encodes the active branch leaf', () {
      expect(
        codec
            .encode(
              KaiselConfig(
                mainStack: const [_ShellHost()],
                nestedState: _shell(0, const [_HomeTab()]),
              ),
            )
            .toString(),
        '/home',
      );
      expect(
        codec
            .encode(
              KaiselConfig(
                mainStack: const [_ShellHost()],
                nestedState: _shell(1, const [_MatchesTab()]),
              ),
            )
            .toString(),
        '/matches',
      );
    });

    test('a default query value is omitted (clean canonical URL)', () {
      // _MatchesTab(refresh: null) → /matches, not /matches?refresh=...
      expect(
        codec
            .encode(
              KaiselConfig(
                mainStack: const [_ShellHost()],
                nestedState: _shell(1, const [_MatchesTab()]),
              ),
            )
            .toString(),
        '/matches',
      );
    });
  });

  group('shell round-trips (no cross-branch claim)', () {
    void roundTrip(int branch, List<_App> stack) {
      final config = KaiselConfig<_App>(
        mainStack: const [_ShellHost()],
        nestedState: _shell(branch, stack),
      );
      final uri = codec.encode(config);
      final back = codec.decode(uri)?.nestedState;
      expect(back, isA<KaiselShellConfig>());
      if (back is KaiselShellConfig) {
        expect(back.activeBranch, branch, reason: 'branch for $uri');
        expect(back.activeBranchStack, stack, reason: 'stack for $uri');
      }
    }

    test('home and matches states each round-trip onto their own branch', () {
      roundTrip(0, const [_HomeTab()]);
      roundTrip(0, const [_SubletsFilter('Brooklyn')]);
      roundTrip(1, const [_MatchesTab(refresh: true)]);
      roundTrip(1, const [_MatchesTab()]);
    });
  });

  group('module', () {
    test('decodes prefix/<rest> into a module config', () {
      final config = codec.decode(Uri.parse('/checkout/payment/visa'));
      expect(config?.mainStack, const [_CheckoutMount()]);
      final nested = config?.nestedState;
      expect(nested, isA<KaiselModuleConfig>());
      if (nested is KaiselModuleConfig) {
        expect(nested.stack, const [_PaymentStep('visa')]);
      }
    });

    test('encodes a module config back, re-adding the prefix', () {
      expect(
        codec
            .encode(
              KaiselConfig(
                mainStack: const [_CheckoutMount()],
                nestedState: KaiselModuleConfig(stack: const [_CartStep()]),
              ),
            )
            .toString(),
        '/checkout/cart',
      );
    });

    test('module round-trips', () {
      final config = KaiselConfig<_App>(
        mainStack: const [_CheckoutMount()],
        nestedState: KaiselModuleConfig(stack: const [_PaymentStep('amex')]),
      );
      final back = codec.decode(codec.encode(config))?.nestedState;
      expect(back, isA<KaiselModuleConfig>());
      if (back is KaiselModuleConfig) {
        expect(back.stack, const [_PaymentStep('amex')]);
      }
    });
  });
}
