// Adaptive layout with NO built-in scaffold — the absorption primitive isn't
// about panes. A linear checkout wizard (Account → Shipping → Payment) is a
// normal route stack; at wide widths the top step absorbs the ones below into one
// horizontal stepper (KaiselAbsorbingPage + a plain Column/Row).
//
//   flutter run -t lib/main_adaptive_stepper.dart      (resize the window)

import 'package:flutter/material.dart';
import 'package:kaisel/kaisel.dart';

sealed class _Step extends KaiselRoute {
  const _Step();

  int get index;
  String get title;
  _Step? get next;
}

final class _Account extends _Step {
  const _Account();
  @override
  int get index => 0;
  @override
  String get title => 'Account';
  @override
  _Step? get next => const _Shipping();
}

final class _Shipping extends _Step {
  const _Shipping();
  @override
  int get index => 1;
  @override
  String get title => 'Shipping';
  @override
  _Step? get next => const _Payment();
}

final class _Payment extends _Step {
  const _Payment();
  @override
  int get index => 2;
  @override
  String get title => 'Payment';
  @override
  _Step? get next => null;
}

const _labels = ['Account', 'Shipping', 'Payment'];

KaiselPageResult _adaptiveBuilder(
  BuildContext context,
  _Step route,
  KaiselStackContext<_Step> ctx,
) {
  final wide = MediaQuery.sizeOf(context).width >= 820;

  if (!wide) {
    return KaiselStandalonePage(_StepScaffold(step: route));
  }

  // Only the top entry renders; it absorbs everything below it (absorbing == its
  // position), collapsing the whole linear stack into one page.
  if (!ctx.isTop) {
    return const KaiselStandalonePage(SizedBox.shrink());
  }
  final wizard = _WizardPage(step: route);
  return ctx.position == 0
      ? KaiselStandalonePage(wizard)
      : KaiselAbsorbingPage(widget: wizard, absorbing: ctx.position);
}

class _StepScaffold extends StatelessWidget {
  const _StepScaffold({required this.step});

  final _Step step;

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: Text('Checkout · ${step.title}')),
    body: Padding(
      padding: const EdgeInsets.all(24),
      child: Align(
        alignment: Alignment.topCenter,
        child: _StepBody(step: step),
      ),
    ),
  );
}

class _WizardPage extends StatelessWidget {
  const _WizardPage({required this.step});

  final _Step step;

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Checkout')),
    body: Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        children: [
          _StepperHeader(current: step.index),
          const SizedBox(height: 32),
          Expanded(
            child: Center(child: _StepBody(step: step)),
          ),
        ],
      ),
    ),
  );
}

class _StepperHeader extends StatelessWidget {
  const _StepperHeader({required this.current});

  final int current;

  @override
  Widget build(BuildContext context) {
    final active = Theme.of(context).colorScheme.primary;
    final muted = Theme.of(context).disabledColor;
    final row = <Widget>[];
    for (var i = 0; i < _labels.length; i++) {
      final done = i < current;
      final isCurrent = i == current;
      final color = (done || isCurrent) ? active : muted;
      row.add(
        Column(
          children: [
            CircleAvatar(
              radius: 16,
              backgroundColor: color,
              child: done
                  ? const Icon(Icons.check, size: 18, color: Colors.white)
                  : Text(
                      '${i + 1}',
                      style: const TextStyle(color: Colors.white),
                    ),
            ),
            const SizedBox(height: 6),
            Text(
              _labels[i],
              style: TextStyle(
                color: color,
                fontWeight: isCurrent ? FontWeight.bold : FontWeight.normal,
              ),
            ),
          ],
        ),
      );
      if (i < _labels.length - 1) {
        row.add(
          Expanded(
            child: Container(
              height: 2,
              margin: const EdgeInsets.only(bottom: 22),
              color: i < current ? active : muted,
            ),
          ),
        );
      }
    }
    return Row(crossAxisAlignment: CrossAxisAlignment.start, children: row);
  }
}

class _StepBody extends StatelessWidget {
  const _StepBody({required this.step});

  final _Step step;

  @override
  Widget build(BuildContext context) => ConstrainedBox(
    constraints: const BoxConstraints(maxWidth: 420),
    child: Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          '${step.title} details',
          style: Theme.of(context).textTheme.titleLarge,
        ),
        const SizedBox(height: 16),
        const TextField(decoration: InputDecoration(labelText: 'Field one')),
        const SizedBox(height: 12),
        const TextField(decoration: InputDecoration(labelText: 'Field two')),
        const SizedBox(height: 24),
        Row(
          children: [
            if (step.index > 0)
              OutlinedButton(
                onPressed: () => context.pop(),
                child: const Text('Back'),
              ),
            const Spacer(),
            FilledButton(
              onPressed: () {
                final n = step.next;
                if (n != null) {
                  context.push(n);
                } else {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Order placed 🎉')),
                  );
                }
              },
              child: Text(step.next == null ? 'Place order' : 'Next'),
            ),
          ],
        ),
      ],
    ),
  );
}

final _config = KaiselRouterConfig<_Step>.adaptive(
  initial: const _Account(),
  builder: _adaptiveBuilder,
);

void main() => runApp(
  MaterialApp.router(routerConfig: _config, debugShowCheckedModeBanner: false),
);
