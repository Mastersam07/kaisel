// Foldable-aware adaptive layout — the same absorption primitive keyed on the
// fold instead of raw width. Folded/narrow stacks Inbox → Message; spanned across
// a fold renders them as two panes with a gap at the hinge. kaisel collapses the
// stack; the widget places the panes via MediaQuery.displayFeatures (production
// apps use package:dual_screen's TwoPane — this hand-rolls it to stay dep-free).
//
//   flutter run -t lib/main_foldable.dart   (a foldable emulator, or resize)

import 'dart:ui' show DisplayFeature, DisplayFeatureType;

import 'package:flutter/material.dart';
import 'package:kaisel/kaisel.dart';

sealed class _R extends KaiselRoute {
  const _R();
}

final class _Inbox extends _R {
  const _Inbox();
}

final class _Message extends _R {
  const _Message(this.id);

  final int id;

  @override
  List<Object?> get props => [id];
}

const _subjects = ['Welcome', 'Your receipt', 'Standup notes', 'Re: routing'];

/// A vertical fold/hinge that splits the screen left/right, or null.
DisplayFeature? _verticalFold(MediaQueryData mq) {
  for (final f in mq.displayFeatures) {
    final vertical =
        f.bounds.left > 0 && f.bounds.height >= mq.size.height * 0.9;
    final isFold =
        f.type == DisplayFeatureType.fold || f.type == DisplayFeatureType.hinge;
    if (vertical && isFold) return f;
  }
  return null;
}

KaiselPageResult _builder(
  BuildContext context,
  _R route,
  KaiselStackContext<_R> ctx,
) {
  final mq = MediaQuery.of(context);
  final fold = _verticalFold(mq);
  final spanned = fold != null || mq.size.width >= 700;

  return switch ((ctx.previous, route, spanned)) {
    (_Inbox(), _Message(:final id), true) => KaiselAbsorbingPage(
      widget: _TwoPane(
        start: _pane(
          'Inbox',
          const Color(0xFF37474F),
          _InboxList(selected: id),
        ),
        end: _pane(
          _subjects[id % _subjects.length],
          const Color(0xFF00695C),
          _MessageBody(id),
        ),
        hinge: fold?.bounds,
      ),
    ),
    (_, _Message(:final id), _) => KaiselStandalonePage(
      Scaffold(
        appBar: AppBar(title: Text(_subjects[id % _subjects.length])),
        body: _MessageBody(id),
      ),
    ),
    _ => KaiselStandalonePage(
      Scaffold(
        appBar: AppBar(title: const Text('Inbox')),
        body: const _InboxList(),
      ),
    ),
  };
}

/// Lays [start] and [end] around a vertical [hinge] (or a plain 2:3 split when
/// there's no physical fold).
class _TwoPane extends StatelessWidget {
  const _TwoPane({required this.start, required this.end, this.hinge});

  final Widget start;
  final Widget end;
  final Rect? hinge;

  @override
  Widget build(BuildContext context) {
    final h = hinge;
    if (h == null) {
      return Row(
        children: [
          Expanded(flex: 2, child: start),
          const VerticalDivider(width: 1),
          Expanded(flex: 3, child: end),
        ],
      );
    }
    // Size the left pane to the fold, leave a gap at the seam, fill the rest.
    return Row(
      children: [
        SizedBox(width: h.left, child: start),
        SizedBox(width: h.width),
        Expanded(child: end),
      ],
    );
  }
}

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

class _InboxList extends StatelessWidget {
  const _InboxList({this.selected});

  final int? selected;

  @override
  Widget build(BuildContext context) => ListView(
    children: [
      for (var i = 0; i < _subjects.length; i++)
        ListTile(
          selected: i == selected,
          leading: const Icon(Icons.mail_outline),
          title: Text(_subjects[i]),
          subtitle: const Text('Tap to open'),
          onTap: () => context.pushOrReplaceTop(_Message(i)),
        ),
    ],
  );
}

class _MessageBody extends StatelessWidget {
  const _MessageBody(this.id);

  final int id;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.all(20),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          _subjects[id % _subjects.length],
          style: Theme.of(context).textTheme.titleLarge,
        ),
        const SizedBox(height: 12),
        const Text(
          'Full-screen when folded, the right pane when spanned across the '
          'fold. Same stack — only the layout changes, so folding never churns '
          'navigation state.',
        ),
        const Spacer(),
        OutlinedButton(
          onPressed: () => context.pop(),
          child: const Text('Back to inbox'),
        ),
      ],
    ),
  );
}

final _config = KaiselRouterConfig<_R>.adaptive(
  initial: const _Inbox(),
  builder: _builder,
);

void main() => runApp(
  MaterialApp.router(routerConfig: _config, debugShowCheckedModeBanner: false),
);
