// Shared route definitions for the kaisel_lint examples. The three
// sibling files import these to demonstrate each rule firing.
//
// This file is deliberately well-formed (every route overrides props,
// no other rules fire here) so the diagnostics in the sibling files
// are attributable to those files' patterns, not to setup noise.

import 'package:kaisel/kaisel.dart';

/// Top-level sealed route hierarchy.
sealed class AppRoute extends KaiselRoute {
  const AppRoute();
}

final class Home extends AppRoute {
  const Home();
}

final class ProductList extends AppRoute {
  const ProductList();
}

/// Detail route with one field. Properly overrides props.
final class ProductDetail extends AppRoute {
  const ProductDetail(this.id);

  final String id;

  @override
  List<Object?> get props => [id];
}

/// A typed modal flow. Implements `KaiselModalRoute<CardId>` so the
/// avoid_modal_route_on_main_stack rule can detect when it's pushed
/// instead of opened via `run<T>`.
final class AddCardFlow extends AppRoute implements KaiselModalRoute<String> {
  const AddCardFlow();
}

/// Another typed flow returning a different type. Used to demonstrate
/// that the rule recovers the correct T per call site.
final class ConfirmPaymentFlow extends AppRoute
    implements KaiselModalRoute<bool> {
  const ConfirmPaymentFlow({required this.amountCents});

  final int amountCents;

  @override
  List<Object?> get props => [amountCents];
}
