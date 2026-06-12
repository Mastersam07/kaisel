import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kaisel/kaisel.dart';

// A faithful reproduction of a customer's bottom-nav shell codec: the same
// branch-index constants, `pathSegments` decode, and the `type=lookingFor`
// redirect that sends a `/home` URL to the matches branch. `filterKey` toggles
// the original codec (home filter under `type`) against the fix (`filterType`),
// defaulting to the original.

enum SubletPostType {
  lookingFor,
  offering;

  static SubletPostType? fromParameter(String? value) => switch (value) {
    'lookingFor' => SubletPostType.lookingFor,
    'offering' => SubletPostType.offering,
    _ => null,
  };
}

sealed class AppRoute extends KaiselRoute {
  const AppRoute();
}

final class ShellHost extends AppRoute {
  const ShellHost();
}

sealed class HomeRoute extends KaiselRoute {
  const HomeRoute();
}

final class HomeTab extends HomeRoute {
  const HomeTab({this.filtersSubletPostType, this.location});

  final SubletPostType? filtersSubletPostType;
  final String? location;

  @override
  List<Object?> get props => [filtersSubletPostType, location];
}

final class SubletsFilterTab extends HomeRoute {
  const SubletsFilterTab({this.location});

  final String? location;

  @override
  List<Object?> get props => [location];
}

sealed class MatchesRoute extends KaiselRoute {
  const MatchesRoute();
}

final class MatchesTab extends MatchesRoute {
  const MatchesTab({this.refresh});

  final bool? refresh;

  @override
  List<Object?> get props => [refresh];
}

sealed class ChatsRoute extends KaiselRoute {
  const ChatsRoute();
}

final class ChatsTab extends ChatsRoute {
  const ChatsTab();
}

sealed class ProfileRoute extends KaiselRoute {
  const ProfileRoute();
}

final class ProfileTab extends ProfileRoute {
  const ProfileTab();
}

// Favorites (4) and bookings (5) are desktop-only branches the mobile shell
// below doesn't mount.
sealed class FavoritesRoute extends KaiselRoute {
  const FavoritesRoute();
}

final class FavoritesTab extends FavoritesRoute {
  const FavoritesTab();
}

sealed class BookingsRoute extends KaiselRoute {
  const BookingsRoute();
}

final class BookingsTab extends BookingsRoute {
  const BookingsTab();
}

class _AppCodec extends KaiselConfigCodec<AppRoute> {
  const _AppCodec({this.filterKey = 'type'});

  /// `'type'` reproduces the original codec (collides with the redirect);
  /// `'filterType'` is the fix.
  final String filterKey;

  static const _homeBranch = 0;
  static const _matchesBranch = 1;
  static const _chatsBranch = 2;
  static const _profileBranch = 3;
  static const _favoritesBranch = 4;
  static const _bookingsBranch = 5;

  KaiselConfig<AppRoute> _branchConfig(int branch, List<KaiselRoute> stack) =>
      KaiselConfig(
        mainStack: const [ShellHost()],
        nestedState: KaiselShellConfig(
          activeBranch: branch,
          activeBranchStack: stack,
        ),
      );

  @override
  KaiselConfig<AppRoute>? decode(Uri uri) {
    final normalized = _normalizeUri(uri);
    final query = normalized.queryParameters;
    final segments = [
      ...normalized.pathSegments.where((segment) => segment.isNotEmpty),
    ];

    return switch (segments) {
      [] || ['home'] =>
        SubletPostType.fromParameter(query['type']) == SubletPostType.lookingFor
            ? _branchConfig(_matchesBranch, [const MatchesTab(refresh: true)])
            : _branchConfig(_homeBranch, [_decodeHomeTab(query)]),
      ['sublets_filter'] || ['home', 'sublets_filter'] => _branchConfig(
        _homeBranch,
        [const HomeTab(), _decodeSubletsFilter(query)],
      ),
      ['matches'] => _branchConfig(_matchesBranch, [
        MatchesTab(refresh: bool.tryParse(query['refresh'] ?? '')),
      ]),
      ['chat'] => _branchConfig(_chatsBranch, [const ChatsTab()]),
      ['user-profile'] => _branchConfig(_profileBranch, [const ProfileTab()]),
      ['favorites'] => _branchConfig(_favoritesBranch, [const FavoritesTab()]),
      ['bookings'] => _branchConfig(_bookingsBranch, [const BookingsTab()]),
      _ => _branchConfig(_homeBranch, [const HomeTab()]),
    };
  }

  HomeTab _decodeHomeTab(Map<String, String> query) => HomeTab(
    filtersSubletPostType: SubletPostType.fromParameter(
      query[filterKey] ?? query['type'],
    ),
    location: query['location'],
  );

  SubletsFilterTab _decodeSubletsFilter(Map<String, String> query) =>
      SubletsFilterTab(location: query['location']);

  @override
  Uri encode(KaiselConfig<AppRoute> config) {
    final top = config.mainStack.last;
    if (top is ShellHost) {
      final nested = config.nestedState;
      if (nested is KaiselShellConfig) return _encodeShell(nested);
    }
    return Uri(path: '/home');
  }

  Uri _encodeShell(KaiselShellConfig shell) =>
      switch (shell.activeBranchStack) {
        [final HomeTab home] => _encodeHomeTab(home),
        [HomeTab(), final SubletsFilterTab filter] => _encodeSubletsFilter(
          filter,
        ),
        [MatchesTab(:final refresh)] => Uri(
          path: '/matches',
          queryParameters: refresh == null ? null : {'refresh': '$refresh'},
        ),
        [ChatsTab()] => Uri(path: '/chat'),
        [ProfileTab()] => Uri(path: '/user-profile'),
        [FavoritesTab()] => Uri(path: '/favorites'),
        [BookingsTab()] => Uri(path: '/bookings'),
        _ => Uri(path: '/home'),
      };

  Uri _encodeHomeTab(HomeTab home) {
    final params = <String, String>{
      if (home.filtersSubletPostType != null)
        filterKey: home.filtersSubletPostType?.name ?? '',
      if (home.location != null) 'location': home.location ?? '',
    };
    return Uri(path: '/home', queryParameters: params.isEmpty ? null : params);
  }

  Uri _encodeSubletsFilter(SubletsFilterTab filter) {
    final params = <String, String>{
      if (filter.location != null) 'location': filter.location ?? '',
    };
    return Uri(
      path: '/sublets_filter',
      queryParameters: params.isEmpty ? null : params,
    );
  }

  Uri _normalizeUri(Uri uri) {
    const customSchemes = ['app-staging', 'app'];
    const httpSchemes = ['https', 'http'];

    if (customSchemes.contains(uri.scheme)) {
      final tail = uri.pathSegments.isNotEmpty
          ? '/${uri.pathSegments.join('/')}'
          : '';
      return Uri(
        path: '/${uri.authority}$tail',
        queryParameters: uri.queryParameters.isNotEmpty
            ? uri.queryParameters
            : null,
      );
    }

    if (httpSchemes.contains(uri.scheme)) {
      final segments = uri.pathSegments;
      final path = segments.isNotEmpty ? '/${segments.skip(1).join('/')}' : '/';
      return Uri(
        path: path,
        queryParameters: uri.queryParameters.isNotEmpty
            ? uri.queryParameters
            : null,
      );
    }

    return Uri(
      path: uri.path,
      queryParameters: uri.queryParameters.isNotEmpty
          ? uri.queryParameters
          : null,
    );
  }
}

class _App extends StatefulWidget {
  const _App({this.codec = const _AppCodec(), this.initialBranch = 0});

  final _AppCodec codec;

  /// The mobile shell mounts four branches (home, matches, chats, profile);
  /// [initialBranch] is the one shown first, i.e. the default to fall back on.
  final int initialBranch;

  @override
  State<_App> createState() => _AppState();
}

class _AppState extends State<_App> {
  late final KaiselRouterConfig<AppRoute> config = KaiselRouterConfig<AppRoute>(
    initial: const ShellHost(),
    codec: widget.codec,
    builder: (context, route) => switch (route) {
      ShellHost() => KaiselBranchedShell.specs(
        initialBranch: widget.initialBranch,
        branches: [
          KaiselBranchSpec<HomeRoute>(
            initial: const HomeTab(),
            builder: (context, r) => switch (r) {
              HomeTab() => const Scaffold(body: Center(child: Text('home'))),
              SubletsFilterTab() => const Scaffold(
                body: Center(child: Text('sublets_filter')),
              ),
            },
          ),
          KaiselBranchSpec<MatchesRoute>(
            initial: const MatchesTab(),
            builder: (context, r) => switch (r) {
              MatchesTab() => const Scaffold(
                body: Center(child: Text('matches')),
              ),
            },
          ),
          KaiselBranchSpec<ChatsRoute>(
            initial: const ChatsTab(),
            builder: (context, r) => switch (r) {
              ChatsTab() => const Scaffold(body: Center(child: Text('chats'))),
            },
          ),
          KaiselBranchSpec<ProfileRoute>(
            initial: const ProfileTab(),
            builder: (context, r) => switch (r) {
              ProfileTab() => const Scaffold(
                body: Center(child: Text('profile')),
              ),
            },
          ),
        ],
        chromeBuilder: (context, active, content, switchBranch) => content,
      ),
    },
  );

  @override
  void dispose() {
    config.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) =>
      MaterialApp.router(routerConfig: config);
}

Future<void> _coldStart(
  WidgetTester tester,
  String route, {
  _AppCodec codec = const _AppCodec(),
  int initialBranch = 0,
}) async {
  tester.platformDispatcher.defaultRouteNameTestValue = route;
  addTearDown(tester.platformDispatcher.clearDefaultRouteNameTestValue);
  await tester.pumpWidget(_App(codec: codec, initialBranch: initialBranch));
  await tester.pumpAndSettle();
}

// The branch a state lands on after one encode→decode round-trip, or null if it
// fails to round-trip to a shell config.
int? _roundTripBranch(_AppCodec codec, KaiselShellConfig state) {
  final config = KaiselConfig<AppRoute>(
    mainStack: const [ShellHost()],
    nestedState: state,
  );
  final decoded = codec.decode(codec.encode(config));
  if (decoded?.nestedState case final KaiselShellConfig shell) {
    return shell.activeBranch;
  }
  return null;
}

void main() {
  group('kaisel routes the customer codec correctly', () {
    testWidgets('a cold-start deep link into /home/sublets_filter lands on '
        'the home branch and stays there', (tester) async {
      await _coldStart(tester, '/home/sublets_filter');

      expect(find.text('sublets_filter'), findsOneWidget);
      expect(find.text('matches'), findsNothing);
    });

    testWidgets('the same deep link via a custom scheme also lands on home', (
      tester,
    ) async {
      await _coldStart(tester, 'app://home/sublets_filter');

      expect(find.text('sublets_filter'), findsOneWidget);
      expect(find.text('matches'), findsNothing);
    });

    testWidgets('a bare launch lands on the home branch root', (tester) async {
      await _coldStart(tester, '/');

      expect(find.text('home'), findsOneWidget);
    });

    testWidgets('/matches lands on the matches branch', (tester) async {
      await _coldStart(tester, '/matches');

      expect(find.text('matches'), findsOneWidget);
    });

    testWidgets('an incoming /home?type=lookingFor deep link is redirected to '
        'matches, as the codec intends', (tester) async {
      await _coldStart(tester, '/home?type=lookingFor');

      expect(find.text('matches'), findsOneWidget);
    });
  });

  group('a deep link to a desktop-only branch degrades gracefully', () {
    testWidgets('/favorites does not throw and stays on the default branch '
        '(here, matches)', (tester) async {
      await _coldStart(tester, '/favorites', initialBranch: 1);

      expect(tester.takeException(), isNull);
      expect(find.text('matches'), findsOneWidget);
      expect(find.text('favorites'), findsNothing);
    });

    testWidgets('/bookings likewise stays on the default branch '
        '(here, home)', (tester) async {
      await _coldStart(tester, '/bookings', initialBranch: 0);

      expect(tester.takeException(), isNull);
      expect(find.text('home'), findsOneWidget);
    });

    testWidgets(
      'an in-range branch still restores normally on the same shell',
      (tester) async {
        await _coldStart(tester, '/user-profile', initialBranch: 0);

        expect(tester.takeException(), isNull);
        expect(find.text('profile'), findsOneWidget);
      },
    );
  });

  group('the original codec collides on type=lookingFor', () {
    const codec = _AppCodec();

    test('a home tab carrying a looking-for filter encodes to the same URL the '
        'redirect claims', () {
      final url = codec.encode(
        KaiselConfig<AppRoute>(
          mainStack: const [ShellHost()],
          nestedState: KaiselShellConfig(
            activeBranch: 0,
            activeBranchStack: const [
              HomeTab(filtersSubletPostType: SubletPostType.lookingFor),
            ],
          ),
        ),
      );

      expect(url.toString(), '/home?type=lookingFor');
    });

    test(
      'so that home state does not round-trip — it decodes onto matches',
      () {
        final branch = _roundTripBranch(
          codec,
          KaiselShellConfig(
            activeBranch: 0,
            activeBranchStack: const [
              HomeTab(filtersSubletPostType: SubletPostType.lookingFor),
            ],
          ),
        );

        expect(
          branch,
          1,
          reason: 'home (0) state round-trips onto matches (1)',
        );
      },
    );
  });

  group('the filterType fix restores the round-trip', () {
    const fixed = _AppCodec(filterKey: 'filterType');

    test('the looking-for home filter now encodes under filterType', () {
      final url = fixed.encode(
        KaiselConfig<AppRoute>(
          mainStack: const [ShellHost()],
          nestedState: KaiselShellConfig(
            activeBranch: 0,
            activeBranchStack: const [
              HomeTab(filtersSubletPostType: SubletPostType.lookingFor),
            ],
          ),
        ),
      );

      expect(url.toString(), '/home?filterType=lookingFor');
    });

    test(
      'and round-trips back onto the home branch with the filter intact',
      () {
        final config = KaiselConfig<AppRoute>(
          mainStack: const [ShellHost()],
          nestedState: KaiselShellConfig(
            activeBranch: 0,
            activeBranchStack: const [
              HomeTab(filtersSubletPostType: SubletPostType.lookingFor),
            ],
          ),
        );

        final decoded = fixed.decode(fixed.encode(config));
        expect(decoded?.nestedState, isA<KaiselShellConfig>());
        if (decoded?.nestedState case final KaiselShellConfig shell) {
          expect(shell.activeBranch, 0);
          expect(shell.activeBranchStack.single, isA<HomeTab>());
          if (shell.activeBranchStack.single case final HomeTab home) {
            expect(home.filtersSubletPostType, SubletPostType.lookingFor);
          }
        }
      },
    );

    test(
      'the intended /home?type=lookingFor redirect still reaches matches',
      () {
        final decoded = fixed.decode(Uri.parse('/home?type=lookingFor'));
        if (decoded?.nestedState case final KaiselShellConfig shell) {
          expect(shell.activeBranch, 1);
        } else {
          fail('expected a shell config');
        }
      },
    );

    test('a legacy /home?type=offering link still sets the home filter', () {
      final decoded = fixed.decode(Uri.parse('/home?type=offering'));
      if (decoded?.nestedState case final KaiselShellConfig shell) {
        expect(shell.activeBranch, 0);
        if (shell.activeBranchStack.single case final HomeTab home) {
          expect(home.filtersSubletPostType, SubletPostType.offering);
        }
      } else {
        fail('expected a shell config');
      }
    });

    test(
      'every representative shell state round-trips onto its own branch',
      () {
        final states = <KaiselShellConfig>[
          KaiselShellConfig(
            activeBranch: 0,
            activeBranchStack: const [HomeTab()],
          ),
          KaiselShellConfig(
            activeBranch: 0,
            activeBranchStack: const [
              HomeTab(filtersSubletPostType: SubletPostType.lookingFor),
            ],
          ),
          KaiselShellConfig(
            activeBranch: 0,
            activeBranchStack: const [HomeTab(), SubletsFilterTab()],
          ),
          KaiselShellConfig(
            activeBranch: 1,
            activeBranchStack: const [MatchesTab(refresh: true)],
          ),
          KaiselShellConfig(
            activeBranch: 2,
            activeBranchStack: const [ChatsTab()],
          ),
        ];

        for (final state in states) {
          expect(
            _roundTripBranch(fixed, state),
            state.activeBranch,
            reason: 'state on branch ${state.activeBranch} did not round-trip',
          );
        }
      },
    );
  });
}
