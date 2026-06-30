// Type-checking utilities for identifying kaisel-specific types in user
// code. These walk the analyzer's element model rather than matching on
// textual names, so the rules survive renames, type aliases, and
// re-exports.
//
// All checks are anchored on `package:kaisel/` — types declared in other
// packages with the same name (e.g. a user's own `KaiselRoute`) won't
// match. This is deliberate: lints should only fire on types they
// actually understand.

import 'package:analyzer/dart/element/element.dart';
import 'package:analyzer/dart/element/type.dart';

/// Canonical package prefixes for kaisel types. The core types
/// (`KaiselRoute`, `KaiselModalRoute`, `KaiselRouter`, …) are declared in
/// `package:kaisel_core` and re-exported by `package:kaisel`, so both
/// prefixes must be recognised.
const _kaiselPackagePrefixes = ['package:kaisel/', 'package:kaisel_core/'];

/// Returns `true` when [element] is declared inside the kaisel packages.
bool isFromKaiselPackage(Element? element) {
  if (element == null) return false;
  final uri = element.library?.uri.toString() ?? '';
  return _kaiselPackagePrefixes.any(uri.startsWith);
}

/// Returns `true` if [type] is `KaiselRouter<R>` or a subtype.
///
/// Subtypes are walked via [InterfaceType.allSupertypes] so user-defined
/// router wrappers that extend `KaiselRouter` are also recognised.
bool isKaiselRouterType(DartType type) {
  if (type is! InterfaceType) return false;
  if (_isNamedKaiselType(type, 'KaiselRouter')) return true;
  for (final supertype in type.allSupertypes) {
    if (_isNamedKaiselType(supertype, 'KaiselRouter')) return true;
  }
  return false;
}

/// Returns the `T` from `KaiselModalRoute<T>` if [type] (or any of its
/// supertypes) implements it; `null` otherwise.
///
/// Walking supertypes catches the common case where a route both extends
/// `AppRoute` (which extends `KaiselRoute`) AND implements
/// `KaiselModalRoute<T>` — the type argument needs to be recovered from
/// the implements clause, not the extends chain.
DartType? getKaiselModalRouteTypeArgument(DartType type) {
  if (type is! InterfaceType) return null;
  if (_isNamedKaiselType(type, 'KaiselModalRoute') &&
      type.typeArguments.isNotEmpty) {
    return type.typeArguments.first;
  }
  for (final supertype in type.allSupertypes) {
    if (_isNamedKaiselType(supertype, 'KaiselModalRoute') &&
        supertype.typeArguments.isNotEmpty) {
      return supertype.typeArguments.first;
    }
  }
  return null;
}

/// Returns `true` if [element] (or any ancestor) is `KaiselRoute` from
/// the kaisel package.
///
/// Walks the extends chain so a class like
/// `final class ProductDetail extends AppRoute` is correctly identified
/// when `AppRoute extends KaiselRoute`.
bool extendsKaiselRoute(InterfaceElement element) {
  if (element is! ClassElement) return false;

  ClassElement? current = element;
  final visited = <ClassElement>{};
  while (current != null && visited.add(current)) {
    if (current.name == 'KaiselRoute' && isFromKaiselPackage(current)) {
      return true;
    }
    final supertype = current.supertype;
    if (supertype == null) break;
    final superElement = supertype.element;
    if (superElement is! ClassElement) break;
    current = superElement;
  }
  return false;
}

/// True if [type] is the named kaisel type and is from the kaisel package.
bool _isNamedKaiselType(InterfaceType type, String name) =>
    type.element.name == name && isFromKaiselPackage(type.element);

/// Returns the non-static, non-synthetic instance fields declared by
/// [element]. Used by the `require_route_props` rule and its fix.
Iterable<FieldElement> declaredInstanceFields(InterfaceElement element) =>
    element.fields.where(
      (f) =>
          !f.isStatic &&
          f.isOriginDeclaration &&
          (!f.isPrivate || _hasMatchingGetter(element, f)),
    );

bool _hasMatchingGetter(InterfaceElement element, FieldElement field) {
  if (!field.isPrivate) return true;
  final name = field.name ?? '';
  final publicName = name.startsWith('_') ? name.substring(1) : name;
  return element.getters.any((g) => g.name == publicName);
}

/// True if [element] (a KaiselRoute subclass) already overrides `props`.
bool overridesProps(InterfaceElement element) => element.getters.any(
  (g) => g.name == 'props' && !g.isAbstract && g.enclosingElement == element,
);
