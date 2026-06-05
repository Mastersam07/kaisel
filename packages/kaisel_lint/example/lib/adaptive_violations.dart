// Demonstrations of `prefer_push_or_replace_top_in_adaptive`.
//
// This rule is off by default — it fires on every router push of a
// non-modal route, which produces noise outside of adaptive contexts.
// The example's analysis_options.yaml turns it on explicitly so the
// violations below light up.
//
// Modal-route pushes intentionally do NOT trigger this rule — the
// `avoid_modal_route_on_main_stack` rule covers those with a different
// fix (`run<T>`, not `pushOrReplaceTop`).

// ignore_for_file: unused_local_variable

import 'package:kaisel/kaisel.dart';

import 'routes.dart';

void adaptivePushes(KaiselRouter<AppRoute> router) {
  // VIOLATION: in adaptive master-detail, push stacks duplicates of
  // the same detail type instead of swapping in place. The fix
  // converts to pushOrReplaceTop.
  router.push(const ProductDetail('sku-42'));
  //     ^^^^ prefer_push_or_replace_top_in_adaptive

  router.push(const ProductDetail('sku-43'));
  //     ^^^^ prefer_push_or_replace_top_in_adaptive

  // VIOLATION: even ProductList push triggers (since the rule can't
  // know whether the calling context is adaptive). When this fires
  // spuriously, suppress with `// ignore: kaisel_lint/prefer_push_or_replace_top_in_adaptive`.
  router.push(const ProductList());
  //     ^^^^ prefer_push_or_replace_top_in_adaptive
}

void modalPushes(KaiselRouter<AppRoute> router) {
  // NO `prefer_push_or_replace_top_in_adaptive` fires here — the
  // modal-route rule handles these. (It still fires the modal-stack
  // diagnostic.)
  router.push(const AddCardFlow());
}

void correctUsage(KaiselRouter<AppRoute> router) {
  // CORRECT: pushOrReplaceTop in adaptive contexts.
  router.pushOrReplaceTop(const ProductDetail('sku-42'));
  router.pushOrReplaceTop(const ProductDetail('sku-43'));
}
