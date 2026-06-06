// Nested modal flows demo for the kaisel router.
//
// Run from the `example/` directory:
//
//   flutter run -t lib/main_nested_flows.dart
//
// What this shows
// ---------------
// `router.run<T>(...)` opens a modal flow that returns
// `Future<T?>`. A flow can itself call `router.run<U>(...)` to open
// a nested flow on top. Each flow gets its own sub-router and its
// own modal overlay layer. Completions unwind LIFO.
//
// The demo:
//
// 1. Home has a "Pay $42" button.
// 2. Tapping it opens **PaymentFlow** (the outer flow). The
//    payment screen shows the amount, a list of saved cards, and a
//    "+ Add card" button.
// 3. Tapping "+ Add card" opens **AddCardFlow** (the inner flow)
//    on top of PaymentFlow. Both modal layers are visible at the
//    same time.
// 4. The inner flow's "Save card" calls
//    `context.completeFlow<String>(...)`. The outer flow's
//    `await router.run<String>(AddCardFlow())` resumes with the
//    new card, which gets appended to the saved-cards list.
// 5. The outer flow's "Pay" calls
//    `context.completeFlow<bool>(true)`. Home's
//    `await router.run<bool>(PaymentFlow())` resumes with the
//    result.
//
// Notes
// -----
// - Active flows are exposed at `delegate.activeFlows`. The
//   delegate iterates them and calls `modalBuilder` once per flow,
//   so the outer flow's UI stays mounted while the inner one is
//   open.
// - Per-flow state (the cards list, in PaymentFlow's case) lives in
//   a StatefulWidget inside the flow's screen and is preserved
//   across opening/closing nested flows.

import 'package:flutter/material.dart';
import 'package:kaisel/kaisel.dart';

sealed class AppRoute extends KaiselRoute {
  const AppRoute();
}

final class Home extends AppRoute {
  const Home();
}

/// Outer modal flow. Completes with `true` on Pay, `null` on
/// dismiss (e.g., tap the scrim or call `dismissFlow`).
final class PaymentFlow extends AppRoute implements KaiselModalRoute<bool> {
  const PaymentFlow({required this.amountCents});
  final int amountCents;
  @override
  List<Object?> get props => [amountCents];
}

/// Inner modal flow opened from inside PaymentFlow. Completes with
/// the new card's display name on Save, `null` on dismiss.
final class AddCardFlow extends AppRoute implements KaiselModalRoute<String> {
  const AddCardFlow();
}

class _HomeScreen extends StatefulWidget {
  const _HomeScreen();
  @override
  State<_HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<_HomeScreen> {
  String? _lastResult;

  Future<void> _startPayment() async {
    final result = await context.router<AppRoute>().run<bool>(
      const PaymentFlow(amountCents: 4200),
    );
    if (!mounted) return;
    setState(() {
      _lastResult = switch (result) {
        true => 'Payment successful',
        false => 'Payment declined',
        null => 'Payment cancelled',
      };
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Nested flows demo')),
      body: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('Checkout', style: Theme.of(context).textTheme.headlineMedium),
            const SizedBox(height: 8),
            Text(
              'Tap "Pay" to open the payment flow. From inside it, '
              'tap "+ Add card" to stack a nested flow on top.',
              style: Theme.of(context).textTheme.bodyLarge,
            ),
            const SizedBox(height: 32),
            Card(
              color: const Color(0xFF14141C),
              child: Padding(
                padding: const EdgeInsets.all(20),
                child: Row(
                  children: [
                    const Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('Order total'),
                          SizedBox(height: 4),
                          Text(
                            r'$42.00',
                            style: TextStyle(
                              fontSize: 28,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                    ),
                    FilledButton(
                      onPressed: _startPayment,
                      child: const Padding(
                        padding: EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 8,
                        ),
                        child: Text('Pay'),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            if (_lastResult case final result?) ...[
              const SizedBox(height: 24),
              Center(
                child: Text(
                  result,
                  style: const TextStyle(color: Color(0xFF00D4FF)),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// PaymentFlow's screen. Stateful so the cards list survives the
/// nested AddCardFlow opening and closing.
class _PaymentFlowScreen extends StatefulWidget {
  const _PaymentFlowScreen({required this.amountCents});
  final int amountCents;
  @override
  State<_PaymentFlowScreen> createState() => _PaymentFlowScreenState();
}

class _PaymentFlowScreenState extends State<_PaymentFlowScreen> {
  final List<String> _cards = [r'Visa ····1234'];
  int _selected = 0;
  bool _busy = false;

  String get _amount => r'$' + (widget.amountCents / 100).toStringAsFixed(2);

  Future<void> _addCard() async {
    final newCard = await context.router<AppRoute>().run<String>(
      const AddCardFlow(),
    );
    if (!mounted || newCard == null) return;
    setState(() {
      _cards.add(newCard);
      _selected = _cards.length - 1;
    });
  }

  Future<void> _pay() async {
    setState(() => _busy = true);
    await Future<void>.delayed(const Duration(milliseconds: 600));
    if (!mounted) return;
    context.completeFlow<bool>(true);
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            const Expanded(
              child: Text(
                'Payment',
                style: TextStyle(fontSize: 20, fontWeight: FontWeight.w600),
              ),
            ),
            IconButton(
              icon: const Icon(Icons.close),
              onPressed: _busy ? null : () => context.dismissFlow(),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Text(
          _amount,
          style: const TextStyle(
            fontSize: 32,
            fontWeight: FontWeight.w700,
            color: Color(0xFF00D4FF),
          ),
        ),
        const SizedBox(height: 24),
        const Text('Pay with', style: TextStyle(fontSize: 12)),
        const SizedBox(height: 8),
        RadioGroup<int>(
          groupValue: _selected,
          onChanged: (v) {
            if (_busy || v == null) return;
            setState(() => _selected = v);
          },
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              for (var i = 0; i < _cards.length; i++)
                RadioListTile<int>(
                  value: i,
                  title: Text(_cards[i]),
                  contentPadding: EdgeInsets.zero,
                  dense: true,
                ),
            ],
          ),
        ),
        const SizedBox(height: 4),
        OutlinedButton.icon(
          icon: const Icon(Icons.add),
          label: const Text('Add card'),
          onPressed: _busy ? null : _addCard,
        ),
        const SizedBox(height: 24),
        FilledButton(
          onPressed: _busy ? null : _pay,
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 12),
            child: _busy
                ? const SizedBox(
                    height: 18,
                    width: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : Text('Pay $_amount'),
          ),
        ),
      ],
    );
  }
}

/// AddCardFlow's screen. Returns the new card's display name on
/// Save.
class _AddCardFlowScreen extends StatefulWidget {
  const _AddCardFlowScreen();
  @override
  State<_AddCardFlowScreen> createState() => _AddCardFlowScreenState();
}

class _AddCardFlowScreenState extends State<_AddCardFlowScreen> {
  bool _busy = false;

  Future<void> _save() async {
    setState(() => _busy = true);
    await Future<void>.delayed(const Duration(milliseconds: 500));
    if (!mounted) return;
    context.completeFlow<String>(r'Mastercard ····5678');
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            const Expanded(
              child: Text(
                'Add a card',
                style: TextStyle(fontSize: 20, fontWeight: FontWeight.w600),
              ),
            ),
            IconButton(
              icon: const Icon(Icons.close),
              onPressed: _busy ? null : () => context.dismissFlow(),
            ),
          ],
        ),
        const SizedBox(height: 16),
        const Text('Card number', style: TextStyle(fontSize: 12)),
        const SizedBox(height: 4),
        const TextField(
          enabled: false,
          decoration: InputDecoration(
            hintText: '5555 5555 5555 5678',
            border: OutlineInputBorder(),
          ),
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            const Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Expiry', style: TextStyle(fontSize: 12)),
                  SizedBox(height: 4),
                  TextField(
                    enabled: false,
                    decoration: InputDecoration(
                      hintText: '12/29',
                      border: OutlineInputBorder(),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 12),
            const Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('CVV', style: TextStyle(fontSize: 12)),
                  SizedBox(height: 4),
                  TextField(
                    enabled: false,
                    decoration: InputDecoration(
                      hintText: '•••',
                      border: OutlineInputBorder(),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: 24),
        FilledButton(
          onPressed: _busy ? null : _save,
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 12),
            child: _busy
                ? const SizedBox(
                    height: 18,
                    width: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Text('Save card'),
          ),
        ),
      ],
    );
  }
}

final _config = KaiselRouterConfig<AppRoute>(
  initial: const Home(),
  builder: (context, route) => switch (route) {
    Home() => const _HomeScreen(),
    PaymentFlow(:final amountCents) => _PaymentFlowScreen(
      amountCents: amountCents,
    ),
    AddCardFlow() => const _AddCardFlowScreen(),
  },
  modalBuilder: _modalBuilder,
);

// Modal builder. Called once per active flow. The outer
// PaymentFlow renders first; when AddCardFlow is opened on top,
// both modal layers are mounted simultaneously and stack
// visually (the inner one drawn over the outer).
Widget _modalBuilder(
  BuildContext context,
  KaiselModalRoute<Object?> flowRoute,
  Widget flowChild,
) {
  // Slight inset for the inner flow so both layers are visible.
  final isInner = flowRoute is AddCardFlow;
  return ColoredBox(
    color: Colors.black.withValues(alpha: isInner ? 0.35 : 0.6),
    child: Center(
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: isInner ? 380 : 420),
        child: Container(
          margin: EdgeInsets.symmetric(
            horizontal: 16,
            vertical: isInner ? 48 : 24,
          ),
          padding: const EdgeInsets.fromLTRB(24, 16, 24, 24),
          decoration: BoxDecoration(
            color: const Color(0xFF14141C),
            border: Border.all(
              color: isInner
                  ? const Color(0xFF00D4FF).withValues(alpha: 0.4)
                  : const Color(0xFF2A2A35),
            ),
            borderRadius: BorderRadius.circular(16),
          ),
          child: SingleChildScrollView(child: flowChild),
        ),
      ),
    ),
  );
}

void main() {
  runApp(
    MaterialApp.router(
      title: 'kaisel nested flows demo',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF00D4FF),
          brightness: Brightness.dark,
        ),
        scaffoldBackgroundColor: const Color(0xFF0A0A0F),
        cardColor: const Color(0xFF14141C),
        useMaterial3: true,
      ),
      routerConfig: _config,
    ),
  );
}
