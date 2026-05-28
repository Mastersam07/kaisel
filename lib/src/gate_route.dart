/// Base marker for application route types.
///
/// Apps define their own sealed subclass:
///
/// ```dart
/// sealed class AppRoute extends GateRoute {
///   const AppRoute();
/// }
///
/// final class Home extends AppRoute {
///   const Home();
/// }
///
/// final class ProductDetail extends AppRoute {
///   const ProductDetail(this.id);
///   final String id;
/// }
/// ```
///
/// `GateRoute` itself imposes no requirements beyond being constructible.
/// You are responsible for value equality on your route types — either
/// override `==`/`hashCode`, use `package:equatable`, or declare your
/// variants with `const` constructors and immutable fields. Two routes
/// that compare equal are treated as the same logical destination for
/// URL-restoration purposes, but page identity in the navigator is
/// tracked independently (so duplicate routes on the stack are fine).
abstract class GateRoute {
  /// Const constructor so subclasses can be `const`.
  const GateRoute();
}
