// Tests for the kaisel_lint analysis rules.
//
// Each rule is exercised with a firing case and non-firing cases, resolved
// against an in-memory stub of `package:kaisel`. Because the rules anchor on
// the resolved element model (not textual names), the stub must expose real
// `KaiselRoute` / `KaiselModalRoute` / `KaiselRouter` types under the
// `package:kaisel/` URI — which is exactly what `newPackage('kaisel')` gives
// us. Running through resolution means these tests also cover the
// type-detection logic in `kaisel_types.dart`.

// test_reflective_loader requires `test_`-prefixed method names.
// ignore_for_file: non_constant_identifier_names

import 'package:analyzer/utilities/package_config_file_builder.dart';
import 'package:analyzer_testing/analysis_rule/analysis_rule.dart';
import 'package:kaisel_lint/src/rules/avoid_modal_route_on_main_stack.dart';
import 'package:kaisel_lint/src/rules/prefer_const_route_constructors.dart';
import 'package:kaisel_lint/src/rules/prefer_pattern_match_over_is_check.dart';
import 'package:kaisel_lint/src/rules/prefer_push_or_replace_top_in_adaptive.dart';
import 'package:kaisel_lint/src/rules/require_route_props.dart';
import 'package:kaisel_lint/src/rules/unused_guard_redirect.dart';
import 'package:test_reflective_loader/test_reflective_loader.dart';

void main() {
  defineReflectiveSuite(() {
    defineReflectiveTests(AvoidModalRouteOnMainStackTest);
    defineReflectiveTests(RequireRoutePropsTest);
    defineReflectiveTests(PreferPushOrReplaceTopInAdaptiveTest);
    defineReflectiveTests(PreferConstRouteConstructorsTest);
    defineReflectiveTests(PreferPatternMatchOverIsCheckTest);
    defineReflectiveTests(UnusedGuardRedirectTest);
  });
}

/// Minimal stand-in for `package:kaisel` — just the surface the rules inspect.
const _kaiselStub = r'''
class KaiselRoute {
  const KaiselRoute();
  List<Object?> get props => const [];
}

abstract class KaiselModalRoute<T> extends KaiselRoute {
  const KaiselModalRoute();
}

class KaiselRouter<R> {
  Future<void> push(R route) async {}
  Future<void> pushOrReplaceTop(R route) async {}
  Future<T?> run<T>(KaiselModalRoute<T> route) async => null;
}
''';

abstract class _KaiselRuleTest extends AnalysisRuleTest {
  void addKaiselPackage() {
    newPackage('kaisel').addFile('lib/kaisel.dart', _kaiselStub);
    writeTestPackageConfig(PackageConfigFileBuilder());
  }
}

@reflectiveTest
class AvoidModalRouteOnMainStackTest extends _KaiselRuleTest {
  @override
  void setUp() {
    rule = AvoidModalRouteOnMainStack();
    super.setUp();
    addKaiselPackage();
  }

  Future<void> test_fires_whenModalRoutePushed() async {
    await assertDiagnostics(
      r'''
import 'package:kaisel/kaisel.dart';

final class AddCardFlow extends KaiselRoute
    implements KaiselModalRoute<String> {
  const AddCardFlow();
}

void open(KaiselRouter<KaiselRoute> router) {
  router.push(const AddCardFlow());
}
''',
      [lint(198, 32)],
    );
  }

  Future<void> test_noFire_whenOpenedViaRun() async {
    await assertNoDiagnostics(r'''
import 'package:kaisel/kaisel.dart';

final class AddCardFlow extends KaiselRoute
    implements KaiselModalRoute<String> {
  const AddCardFlow();
}

void open(KaiselRouter<KaiselRoute> router) {
  router.run<String>(const AddCardFlow());
}
''');
  }

  Future<void> test_noFire_whenPlainRoutePushed() async {
    await assertNoDiagnostics(r'''
import 'package:kaisel/kaisel.dart';

final class Home extends KaiselRoute {
  const Home();
}

void open(KaiselRouter<KaiselRoute> router) {
  router.push(const Home());
}
''');
  }

  Future<void> test_fires_whenReceiverIsRouterSubclass() async {
    // The receiver is a user wrapper that *extends* KaiselRouter; detection
    // walks the supertype chain.
    await assertDiagnostics(
      r'''
import 'package:kaisel/kaisel.dart';

final class AddCardFlow extends KaiselRoute
    implements KaiselModalRoute<String> {
  const AddCardFlow();
}

class AppRouter extends KaiselRouter<KaiselRoute> {}

void open(AppRouter router) {
  router.push(const AddCardFlow());
}
''',
      [lint(236, 32)],
    );
  }

  Future<void> test_fires_whenArgTypedAsModalRouteDirectly() async {
    // The argument's own static type is `KaiselModalRoute<T>` (not a
    // subtype), exercising the direct-match branch.
    await assertDiagnostics(
      r'''
import 'package:kaisel/kaisel.dart';

void open(KaiselRouter<Object> router, KaiselModalRoute<String> flow) {
  router.push(flow);
}
''',
      [lint(112, 17)],
    );
  }
}

@reflectiveTest
class RequireRoutePropsTest extends _KaiselRuleTest {
  @override
  void setUp() {
    rule = RequireRouteProps();
    super.setUp();
    addKaiselPackage();
  }

  Future<void> test_fires_whenFieldsButNoProps() async {
    await assertDiagnostics(
      r'''
import 'package:kaisel/kaisel.dart';

final class ProductDetail extends KaiselRoute {
  const ProductDetail(this.id);
  final String id;
}
''',
      [lint(50, 13)],
    );
  }

  Future<void> test_noFire_whenPropsOverridden() async {
    await assertNoDiagnostics(r'''
import 'package:kaisel/kaisel.dart';

final class ProductDetail extends KaiselRoute {
  const ProductDetail(this.id);
  final String id;

  @override
  List<Object?> get props => [id];
}
''');
  }

  Future<void> test_noFire_whenNoFields() async {
    await assertNoDiagnostics(r'''
import 'package:kaisel/kaisel.dart';

final class Home extends KaiselRoute {
  const Home();
}
''');
  }

  Future<void> test_fires_whenPrivateFieldHasPublicGetter() async {
    // A private field exposed via a public getter still counts toward props.
    await assertDiagnostics(
      r'''
import 'package:kaisel/kaisel.dart';

final class ProductDetail extends KaiselRoute {
  const ProductDetail(this._id);
  final String _id;
  String get id => _id;
}
''',
      [lint(50, 13)],
    );
  }
}

@reflectiveTest
class PreferPushOrReplaceTopInAdaptiveTest extends _KaiselRuleTest {
  @override
  void setUp() {
    rule = PreferPushOrReplaceTopInAdaptive();
    super.setUp();
    addKaiselPackage();
  }

  Future<void> test_fires_whenPlainRoutePushed() async {
    await assertDiagnostics(
      r'''
import 'package:kaisel/kaisel.dart';

final class ProductDetail extends KaiselRoute {
  const ProductDetail(this.id);
  final String id;

  @override
  List<Object?> get props => [id];
}

void open(KaiselRouter<KaiselRoute> router) {
  router.push(const ProductDetail('a'));
}
''',
      [lint(236, 37)],
    );
  }

  Future<void> test_noFire_whenPushOrReplaceTopUsed() async {
    await assertNoDiagnostics(r'''
import 'package:kaisel/kaisel.dart';

final class ProductDetail extends KaiselRoute {
  const ProductDetail(this.id);
  final String id;

  @override
  List<Object?> get props => [id];
}

void open(KaiselRouter<KaiselRoute> router) {
  router.pushOrReplaceTop(const ProductDetail('a'));
}
''');
  }

  Future<void> test_noFire_onModalRoute() async {
    // The modal-route rule owns that case; this rule must not double-fire.
    await assertNoDiagnostics(r'''
import 'package:kaisel/kaisel.dart';

final class AddCardFlow extends KaiselRoute
    implements KaiselModalRoute<String> {
  const AddCardFlow();
}

void open(KaiselRouter<KaiselRoute> router) {
  router.push(const AddCardFlow());
}
''');
  }
}

@reflectiveTest
class PreferConstRouteConstructorsTest extends _KaiselRuleTest {
  @override
  void setUp() {
    rule = PreferConstRouteConstructors();
    super.setUp();
    addKaiselPackage();
  }

  Future<void> test_fires_whenConstructionCanBeConst() async {
    await assertDiagnostics(
      r'''
import 'package:kaisel/kaisel.dart';

final class Home extends KaiselRoute {
  const Home();
}

final route = Home();
''',
      [lint(110, 6)],
    );
  }

  Future<void> test_noFire_whenAlreadyConst() async {
    await assertNoDiagnostics(r'''
import 'package:kaisel/kaisel.dart';

final class Home extends KaiselRoute {
  const Home();
}

final route = const Home();
''');
  }

  Future<void> test_noFire_whenConstructorIsNotConst() async {
    await assertNoDiagnostics(r'''
import 'package:kaisel/kaisel.dart';

final class Mutable extends KaiselRoute {
  Mutable();
}

final route = Mutable();
''');
  }

  Future<void> test_noFire_whenNotARoute() async {
    await assertNoDiagnostics(r'''
final class Plain {
  const Plain();
}

final value = Plain();
''');
  }
}

@reflectiveTest
class PreferPatternMatchOverIsCheckTest extends _KaiselRuleTest {
  @override
  void setUp() {
    rule = PreferPatternMatchOverIsCheck();
    super.setUp();
    addKaiselPackage();
  }

  Future<void> test_fires_onRouteIsRouteCheck() async {
    await assertDiagnostics(
      r'''
import 'package:kaisel/kaisel.dart';

final class Home extends KaiselRoute {
  const Home();
}

bool check(KaiselRoute route) => route is Home;
''',
      [lint(129, 13)],
    );
  }

  Future<void> test_noFire_onNegatedCheck() async {
    // `is!` is a narrowing guard, not "which route is this" branching.
    await assertNoDiagnostics(r'''
import 'package:kaisel/kaisel.dart';

final class Home extends KaiselRoute {
  const Home();
}

bool check(KaiselRoute route) => route is! Home;
''');
  }

  Future<void> test_noFire_onCapabilityCheck() async {
    // Testing a marker interface (not a concrete route) is legitimate.
    await assertNoDiagnostics(r'''
import 'package:kaisel/kaisel.dart';

bool isFlow(KaiselRoute route) => route is KaiselModalRoute<String>;
''');
  }

  Future<void> test_noFire_onNonRouteOperand() async {
    await assertNoDiagnostics(r'''
bool check(Object value) => value is String;
''');
  }
}

@reflectiveTest
class UnusedGuardRedirectTest extends _KaiselRuleTest {
  @override
  void setUp() {
    rule = UnusedGuardRedirect();
    super.setUp();
    addKaiselPackage();
  }

  Future<void> test_fires_onTrivialPassThrough() async {
    await assertDiagnostics(
      r'''
import 'package:kaisel/kaisel.dart';

final guard =
    (List<KaiselRoute> current, List<KaiselRoute> proposed) => proposed;
''',
      [lint(56, 67)],
    );
  }

  Future<void> test_fires_whenEveryBranchReturnsProposed() async {
    await assertDiagnostics(
      r'''
import 'package:kaisel/kaisel.dart';

final guard = (List<KaiselRoute> current, List<KaiselRoute> proposed) {
  if (current.isEmpty) return proposed;
  return proposed;
};
''',
      [lint(52, 118)],
    );
  }

  Future<void> test_fires_whenIfElseBothReturnProposed() async {
    await assertDiagnostics(
      r'''
import 'package:kaisel/kaisel.dart';

final guard = (List<KaiselRoute> current, List<KaiselRoute> proposed) {
  if (current.isEmpty) {
    return proposed;
  } else {
    return proposed;
  }
};
''',
      [lint(52, 141)],
    );
  }

  Future<void> test_noFire_whenABranchRedirects() async {
    await assertNoDiagnostics(r'''
import 'package:kaisel/kaisel.dart';

final class Home extends KaiselRoute {
  const Home();
}

final guard = (List<KaiselRoute> current, List<KaiselRoute> proposed) {
  if (current.isEmpty) return const [Home()];
  return proposed;
};
''');
  }

  Future<void> test_noFire_whenBodyHasSideEffect() async {
    await assertNoDiagnostics(r'''
import 'package:kaisel/kaisel.dart';

final guard = (List<KaiselRoute> current, List<KaiselRoute> proposed) {
  print(proposed.length);
  return proposed;
};
''');
  }

  Future<void> test_noFire_onNonGuardShape() async {
    await assertNoDiagnostics(r'''
final fn = (int a, int b) => b;
''');
  }

  Future<void> test_noFire_whenReturningACopy() async {
    // A copy is still a no-op, but we conservatively don't flag it.
    await assertNoDiagnostics(r'''
import 'package:kaisel/kaisel.dart';

final guard =
    (List<KaiselRoute> current, List<KaiselRoute> proposed) => [...proposed];
''');
  }
}
