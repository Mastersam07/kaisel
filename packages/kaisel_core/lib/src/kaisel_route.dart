/// Base marker for application route types.
///
/// Apps define their own sealed subclass:
///
/// ```dart
/// sealed class AppRoute extends KaiselRoute {
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
///
///   @override
///   List<Object?> get props => [id];
/// }
/// ```
///
/// ## Equality
///
/// `KaiselRoute` provides default value equality based on [props]. Two
/// routes are equal when they have the same runtime type and equal
/// [props]. For variants with no fields, the default `props` (an empty
/// list) is sufficient — `Home() == Home()` works out of the box.
///
/// For variants with fields, override [props]:
///
/// ```dart
/// final class ProductDetail extends AppRoute {
///   const ProductDetail(this.id);
///   final String id;
///
///   @override
///   List<Object?> get props => [id];
/// }
/// ```
///
/// `props` comparison is per-element using `==`. For collection fields
/// (lists, maps, sets), prefer canonical/const values or override `==`
/// directly with deep-equality logic — `props: [tags]` on a mutable list
/// compares by identity, which is rarely what you want.
///
/// Subclasses are free to override `==`/`hashCode` directly if they
/// want different equality semantics; their override wins over the
/// default.
abstract class KaiselRoute {
  /// Const constructor so subclasses can be `const`.
  const KaiselRoute();

  /// Fields that participate in value equality. Override in variants
  /// that carry data. Defaults to const [] (only runtime type matters).
  List<Object?> get props => const [];

  /// Name set as [RouteSettings.name] on the page kaisel builds, so
  /// `NavigatorObserver`s can identify the screen via `route.settings.name`.
  /// Defaults to the runtime type name; override for a custom (or
  /// obfuscation-stable) one.
  String get routeName => runtimeType.toString();

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    if (other is! KaiselRoute || other.runtimeType != runtimeType) return false;
    final mine = props;
    final theirs = other.props;
    if (mine.length != theirs.length) return false;
    for (var i = 0; i < mine.length; i++) {
      if (mine[i] != theirs[i]) return false;
    }
    return true;
  }

  @override
  int get hashCode => Object.hashAll([runtimeType, ...props]);

  @override
  String toString() {
    if (props.isEmpty) return runtimeType.toString();
    return '$runtimeType(${props.join(', ')})';
  }
}

/// Marker interface for routes that present a modal sub-flow returning
/// a value of type [T].
///
/// Implement this **alongside** your sealed route hierarchy — a modal
/// route is still part of `AppRoute`, but also carries the result type
/// for `await router.run<T>(...)`:
///
/// ```dart
/// sealed class AppRoute extends KaiselRoute {
///   const AppRoute();
/// }
///
/// final class ConfirmPurchase extends AppRoute
///     implements KaiselModalRoute<bool> {
///   const ConfirmPurchase(this.productId);
///   final String productId;
///
///   @override
///   List<Object?> get props => [productId];
/// }
///
/// // Elsewhere:
/// final bool? confirmed = await router.run(ConfirmPurchase('sku-42'));
/// ```
///
/// Inside the flow's screens, call `context.completeFlow<bool>(true)`
/// (or `false`, or `null` to cancel) to resolve the awaited future and
/// dismiss the modal.
abstract class KaiselModalRoute<T> extends KaiselRoute {
  /// Const constructor so subclasses can be `const`.
  const KaiselModalRoute();
}
