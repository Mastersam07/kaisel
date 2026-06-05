// Demonstrations of `avoid_modal_route_on_main_stack`.
//
// Each violating call is annotated with the expected diagnostic; the
// quick fix is the same as the assist of the same name.

// ignore_for_file: unused_local_variable

import 'package:kaisel/kaisel.dart';

import 'routes.dart';

void violations(KaiselRouter<AppRoute> router) {
  // VIOLATION: pushing a KaiselModalRoute<String> via push() loses the
  // typed completion contract. The fix converts to `run<String>(...)`.
  router.push(const AddCardFlow());
  //     ^^^^ avoid_modal_route_on_main_stack

  // VIOLATION: same pattern, different T. The fix recovers `bool`
  // from the route's `implements KaiselModalRoute<bool>` clause.
  router.push(const ConfirmPaymentFlow(amountCents: 1999));
  //     ^^^^ avoid_modal_route_on_main_stack
}

void correctUsage(KaiselRouter<AppRoute> router) async {
  // CORRECT: the flow is opened via run<T>; the result is awaited.
  final String? cardId = await router.run<String>(const AddCardFlow());

  // CORRECT: same pattern with the payment flow.
  final bool? confirmed = await router.run<bool>(
    const ConfirmPaymentFlow(amountCents: 1999),
  );

  // CORRECT (no rule fires): pushing a non-modal route via push() is
  // exactly what push is for.
  router.push(const ProductList());
  router.push(const ProductDetail('sku-42'));
}
