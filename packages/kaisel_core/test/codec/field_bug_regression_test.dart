import 'package:kaisel_core/codec.dart';
import 'package:kaisel_core/kaisel_core.dart';
import 'package:test/test.dart';

// Regression for the reported "every state drifts to the matches tab" bug.
//
// The hand-written codec had two *independent* methods: `encode` turned a home
// tab carrying a "looking for" filter into `/home?type=lookingFor`, while a
// separate `decode` arm treated that exact URL as a redirect to the matches
// branch. The two directions disagreed, so the app silently drifted to matches.
//
// In the DSL there is one ordered rule list and the home filter is one rule, so
// `/home?type=lookingFor` is owned by the home branch in both directions — the
// drift cannot be expressed.

sealed class _App extends KaiselRoute {
  const _App();
}

final class _ShellHost extends _App {
  const _ShellHost();
}

enum _SubletType { lookingFor, offering }

final class _HomeTab extends _App {
  const _HomeTab({this.type});
  final _SubletType? type;
  @override
  List<Object?> get props => [type];
}

final class _MatchesTab extends _App {
  const _MatchesTab();
}

enum _Branch { home, matches }

RouteCodec<_App> _codec() => RouteCodec<_App>(
  rules: [
    shellRule<_App, _Branch>(
      host: const _ShellHost(),
      index: (b) => b.index,
      branches: {
        _Branch.home: [
          (seg('home') / queryEnumOpt('type', _SubletType.values))
              .to((c) => _HomeTab(type: c.enumValueOrNull<_SubletType>(0)))
              .from((r) => r is _HomeTab ? r.props : null),
        ],
        _Branch.matches: [fixed(const _MatchesTab(), seg('matches'))],
      },
    ),
  ],
);

KaiselConfig<_App> _home(_HomeTab tab) => KaiselConfig(
  mainStack: const [_ShellHost()],
  nestedState: KaiselShellConfig(activeBranch: 0, activeBranchStack: [tab]),
);

void main() {
  final codec = _codec();

  test('a looking-for home filter round-trips on HOME, never matches', () {
    final config = _home(const _HomeTab(type: _SubletType.lookingFor));

    final uri = codec.encode(config);
    expect(uri.toString(), '/home?type=lookingFor');

    final back = codec.decode(uri)?.nestedState;
    expect(back, isA<KaiselShellConfig>());
    if (back is KaiselShellConfig) {
      expect(
        back.activeBranch,
        0,
        reason: 'stays on home (branch 0), not matches',
      );
      expect(back.activeBranchStack, const [
        _HomeTab(type: _SubletType.lookingFor),
      ]);
    }
  });

  test('the default (no filter) home state encodes to a clean /home', () {
    expect(codec.encode(_home(const _HomeTab())).toString(), '/home');
    final back = codec.decode(Uri.parse('/home'))?.nestedState;
    if (back is KaiselShellConfig) {
      expect(back.activeBranch, 0);
      expect(back.activeBranchStack, const [_HomeTab()]);
    }
  });

  test('/matches still decodes to the matches branch', () {
    final back = codec.decode(Uri.parse('/matches'))?.nestedState;
    expect(back, isA<KaiselShellConfig>());
    if (back is KaiselShellConfig) {
      expect(back.activeBranch, 1);
    }
  });
}
