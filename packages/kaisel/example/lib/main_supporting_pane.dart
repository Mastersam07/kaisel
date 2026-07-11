// Adaptive layouts beyond master-detail, on the same KaiselAbsorbingPage
// primitive. Resize the window:
//
//   flutter run -t lib/main_supporting_pane.dart
//
//   < 900px : one pane, stacked
//  >= 900px : Document | Comments (supporting pane)
//  >= 1300px: Document | Comments | Thread (three panes, absorbing: 2)
//
// The codec makes the stack URL-addressable — and because absorption only changes
// rendering, the same URL is panes when wide, stacked when narrow.

import 'package:flutter/material.dart';
import 'package:kaisel/kaisel.dart';

sealed class _AppRoute extends KaiselRoute {
  const _AppRoute();
}

final class _Doc extends _AppRoute {
  const _Doc();
}

final class _Comments extends _AppRoute {
  const _Comments();
}

final class _Thread extends _AppRoute {
  const _Thread(this.id);

  final int id;

  @override
  List<Object?> get props => [id];
}

const _docColor = Color(0xFF1565C0);
const _commentsColor = Color(0xFF2E7D32);
const _threadColor = Color(0xFFEF6C00);

KaiselPageResult _adaptiveBuilder(
  BuildContext context,
  _AppRoute route,
  KaiselStackContext<_AppRoute> ctx,
) {
  final width = MediaQuery.sizeOf(context).width;
  final wide = width >= 900;
  final extraWide = width >= 1300;

  return switch (route) {
    _Doc() => KaiselStandalonePage(
      _screen(title: 'Document', child: _DocBody()),
    ),

    _Comments() =>
      (ctx.isTop && wide && ctx.previous is _Doc)
          ? KaiselAbsorbingPage(
              widget: KaiselSupportingPaneScaffold(
                primary: _pane(
                  'Document',
                  _docColor,
                  const _DocBody(inPane: true),
                ),
                supporting: _pane(
                  'Comments',
                  _commentsColor,
                  const _CommentsBody(),
                ),
              ),
            )
          : KaiselStandalonePage(
              _screen(title: 'Comments', child: const _CommentsBody()),
            ),

    _Thread(:final id) => switch ((extraWide, wide)) {
      (true, _) when ctx.position >= 2 => KaiselAbsorbingPage(
        absorbing: 2,
        widget: Row(
          children: [
            Expanded(
              flex: 40,
              child: _pane('Document', _docColor, const _DocBody(inPane: true)),
            ),
            const VerticalDivider(width: 1),
            Expanded(
              flex: 32,
              child: _pane('Comments', _commentsColor, const _CommentsBody()),
            ),
            const VerticalDivider(width: 1),
            Expanded(
              flex: 28,
              child: _pane('Thread #$id', _threadColor, _ThreadBody(id)),
            ),
          ],
        ),
      ),
      (false, true) when ctx.previous is _Comments => KaiselAbsorbingPage(
        widget: KaiselSupportingPaneScaffold(
          primary: _pane('Comments', _commentsColor, const _CommentsBody()),
          supporting: _pane('Thread #$id', _threadColor, _ThreadBody(id)),
        ),
      ),
      _ => KaiselStandalonePage(
        _screen(title: 'Thread #$id', child: _ThreadBody(id)),
      ),
    },
  };
}

Widget _screen({required String title, required Widget child}) => Scaffold(
  appBar: AppBar(title: Text(title)),
  body: child,
);

Widget _pane(String title, Color color, Widget body) => Material(
  child: Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      Container(
        color: color,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        child: Text(
          title,
          style: const TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.w600,
            fontSize: 16,
          ),
        ),
      ),
      Expanded(child: body),
    ],
  ),
);

class _DocBody extends StatelessWidget {
  const _DocBody({this.inPane = false});

  final bool inPane;

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.sizeOf(context).width.round();
    return Padding(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'The absorption primitive',
            style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 12),
          const Text(
            'A route renders a widget that subsumes N entries below it on the '
            'stack. Master-detail is just the n=1 example. Resize this window to '
            'watch one, two, then three panes appear — same stack, different '
            'rendering.',
          ),
          const SizedBox(height: 16),
          Text(
            'window width: $width px',
            style: const TextStyle(color: Colors.grey),
          ),
          const Spacer(),
          if (!inPane)
            FilledButton.tonal(
              onPressed: () => context.push(const _Comments()),
              child: const Text('Open comments'),
            ),
        ],
      ),
    );
  }
}

class _CommentsBody extends StatelessWidget {
  const _CommentsBody();

  @override
  Widget build(BuildContext context) => ListView(
    children: [
      for (final id in [1, 2, 3])
        ListTile(
          leading: CircleAvatar(child: Text('$id')),
          title: Text('Comment $id'),
          subtitle: const Text('Tap to open its thread'),
          onTap: () => context.pushOrReplaceTop(_Thread(id)),
        ),
    ],
  );
}

class _ThreadBody extends StatelessWidget {
  const _ThreadBody(this.id);

  final int id;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.all(20),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Replies to comment $id',
          style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 12),
        const Text('· Nice, this maps cleanly.'),
        const Text('· Same primitive, more panes.'),
        const Spacer(),
        OutlinedButton(
          onPressed: () => context.pop(),
          child: const Text('Close thread'),
        ),
      ],
    ),
  );
}

class _PaneCodec extends KaiselStackCodec<_AppRoute> {
  const _PaneCodec();

  @override
  Uri encode(List<_AppRoute> stack) => switch (stack.last) {
    _Doc() => Uri(path: '/doc'),
    _Comments() => Uri(path: '/doc/comments'),
    _Thread(:final id) => Uri(path: '/doc/comments/thread/$id'),
  };

  @override
  List<_AppRoute>? decode(Uri uri) => switch (uri.pathSegments) {
    [] || ['doc'] => const [_Doc()],
    ['doc', 'comments'] => const [_Doc(), _Comments()],
    ['doc', 'comments', 'thread', final raw] when int.tryParse(raw) != null => [
      const _Doc(),
      const _Comments(),
      _Thread(int.parse(raw)),
    ],
    _ => null,
  };
}

final _config = KaiselRouterConfig<_AppRoute>.adaptive(
  initial: const _Doc(),
  builder: _adaptiveBuilder,
  codec: const StackToConfigCodec(_PaneCodec()),
  fallback: const [_Doc()],
);

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(
    MaterialApp.router(
      routerConfig: _config,
      debugShowCheckedModeBanner: false,
    ),
  );
}
