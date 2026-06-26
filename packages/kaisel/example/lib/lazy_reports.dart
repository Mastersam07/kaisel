import 'package:flutter/material.dart';

/// The "heavy" Reports screen. In [main_lazy_shell.dart] it is imported with
/// `deferred as reports`, so this file's code is only loaded when the Reports
/// tab is first opened — the payoff of [KaiselBranchSpec.deferred].
class ReportsScreen extends StatelessWidget {
  const ReportsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(Icons.bar_chart, size: 56),
          const SizedBox(height: 12),
          Text('Reports', style: Theme.of(context).textTheme.headlineSmall),
          const SizedBox(height: 4),
          const Text(
            "Loaded on demand — this screen's code was not in the "
            'initial bundle.',
          ),
        ],
      ),
    );
  }
}
