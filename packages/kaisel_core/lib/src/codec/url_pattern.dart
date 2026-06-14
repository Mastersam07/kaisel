/// Bidirectional URL patterns — the substrate of the typed codec DSL.
///
/// A [UrlPattern] both *parses* a URL into a typed capture and *writes* that
/// capture back into a URL, from one declaration, so the two directions are
/// inverse by construction. Captures are records: the empty [Unit] for a
/// path with no params, `(String,)` for one, `(String, int)` for two, …
///
/// Build a pattern fluently from [path], adding literal segments with `.seg`
/// and typed params with `.param`:
///
/// ```dart
/// final chat = path.seg('chat').param(str).param(intg); // UrlPattern<(String, int)>
/// chat.printUri(('room', 5));        // Uri /chat/room/5
/// chat.parseUri(Uri.parse('/chat/room/5')); // ('room', 5)
/// ```
///
/// Composition is a fluent builder rather than a `/` operator because Dart has
/// no type-level record concatenation (an operator can't turn `(A,)` and
/// `(B,)` into `(A, B)`). The builder threads the arity through [Path0]–[Path4],
/// so captures stay flat and typed (`c.$1`, `c.$2`) with no casts. Four params
/// is the cap; beyond that, a custom [UrlPattern].
///
/// See `doc/design/codec-dsl.md` for the full design.
library;

/// The empty capture — a path with no params.
typedef Unit = ();

/// A forward cursor over a URL's path segments and query, for parsing.
class UrlReader {
  /// Read over [segments] (already split, no empty entries) and [query].
  UrlReader(this.segments, this.query);

  /// Build a reader from a [Uri], dropping empty path segments.
  factory UrlReader.of(Uri uri) => UrlReader(
    uri.pathSegments.where((s) => s.isNotEmpty).toList(growable: false),
    uri.queryParameters,
  );

  /// The path segments being consumed.
  final List<String> segments;

  /// The query parameters (consumed by key, not positionally).
  final Map<String, String> query;

  /// The current read position; assignable for save/restore on backtracking.
  int position = 0;

  /// Whether all path segments have been consumed.
  bool get atEnd => position >= segments.length;

  /// The next segment without consuming it, or null at the end.
  String? peek() => atEnd ? null : segments[position];

  /// Consume and return the next segment, or null at the end.
  String? take() => atEnd ? null : segments[position++];
}

/// Accumulates path segments and query while writing.
class UrlWriter {
  /// The path segments appended so far.
  final List<String> segments = <String>[];

  /// The query parameters appended so far.
  final Map<String, String> query = <String, String>{};

  /// Assemble the written parts into a `Uri` (path + optional query).
  Uri toUri() => Uri(
    path: '/${segments.join('/')}',
    queryParameters: query.isEmpty ? null : query,
  );
}

/// A single path segment that captures a value of type [A] in both directions.
abstract class UrlParam<A> {
  /// Const base so params can be const.
  const UrlParam();

  /// Parse one [segment]; null if it doesn't match.
  A? parse(String segment);

  /// Render [value] as one segment.
  String format(A value);
}

/// Captures one path segment verbatim as a `String`.
const UrlParam<String> str = _StrParam();

/// Captures one path segment parsed as an `int` (no match if not an int).
const UrlParam<int> intg = _IntParam();

/// Captures one path segment parsed as a `bool` (`true`/`false`).
const UrlParam<bool> boolg = _BoolParam();

/// Captures one path segment matched against an enum's `.name`.
UrlParam<E> enumParam<E extends Enum>(List<E> values) => _EnumParam<E>(values);

class _StrParam extends UrlParam<String> {
  const _StrParam();
  @override
  String? parse(String s) => s;
  @override
  String format(String v) => v;
}

class _IntParam extends UrlParam<int> {
  const _IntParam();
  @override
  int? parse(String s) => int.tryParse(s);
  @override
  String format(int v) => '$v';
}

class _BoolParam extends UrlParam<bool> {
  const _BoolParam();
  @override
  bool? parse(String s) => switch (s) {
    'true' => true,
    'false' => false,
    _ => null,
  };
  @override
  String format(bool v) => '$v';
}

class _EnumParam<E extends Enum> extends UrlParam<E> {
  const _EnumParam(this.values);
  final List<E> values;
  @override
  E? parse(String s) {
    for (final value in values) {
      if (value.name == s) return value;
    }
    return null;
  }

  @override
  String format(E v) => v.name;
}

/// A query parameter that captures a value of type [A] in both directions.
abstract class QueryParam<A> {
  /// Const base so query params can be const.
  const QueryParam();

  /// Read from [query]: null means no match (fails the pattern); otherwise the
  /// (possibly-null) captured value.
  ({A value})? read(Map<String, String> query);

  /// Write [value] into [query] — may omit it (e.g. when it equals a default).
  void write(A value, Map<String, String> query);
}

/// A required query param captured as a `String` (no match if the key is
/// absent).
QueryParam<String> queryStr(String key) =>
    _ReqQuery<String>(key, (s) => s, (v) => v);

/// A required query param parsed as an `int` (no match if absent or not an int).
QueryParam<int> queryIntReq(String key) =>
    _ReqQuery<int>(key, int.tryParse, (v) => '$v');

/// An optional query param as a `String?` — null when the key is absent.
QueryParam<String?> queryStrOpt(String key) =>
    _OptQuery<String>(key, (s) => s, (v) => v);

/// An optional query param parsed as an `int?` — null when absent or invalid.
QueryParam<int?> queryIntOpt(String key) =>
    _OptQuery<int>(key, int.tryParse, (v) => '$v');

/// An optional query param parsed as a `bool?`.
QueryParam<bool?> queryBoolOpt(String key) =>
    _OptQuery<bool>(key, boolg.parse, (v) => '$v');

/// An optional query param matched against an enum's `.name`.
QueryParam<E?> queryEnumOpt<E extends Enum>(String key, List<E> values) {
  final param = enumParam(values);
  return _OptQuery<E>(key, param.parse, (v) => v.name);
}

/// A query param with a default: absent reads as [orElse]; writing a value
/// equal to [orElse] omits the key, so a default-valued state has a clean URL.
QueryParam<int> queryInt(String key, {required int orElse}) =>
    _DefQuery<int>(key, int.tryParse, (v) => '$v', orElse);

class _ReqQuery<A> extends QueryParam<A> {
  const _ReqQuery(this.key, this._parse, this._format);
  final String key;
  final A? Function(String) _parse;
  final String Function(A) _format;
  @override
  ({A value})? read(Map<String, String> q) {
    final s = q[key];
    if (s == null) return null;
    final v = _parse(s);
    return v == null ? null : (value: v);
  }

  @override
  void write(A value, Map<String, String> q) => q[key] = _format(value);
}

class _OptQuery<A> extends QueryParam<A?> {
  const _OptQuery(this.key, this._parse, this._format);
  final String key;
  final A? Function(String) _parse;
  final String Function(A) _format;
  @override
  ({A? value})? read(Map<String, String> q) {
    final s = q[key];
    return (value: s == null ? null : _parse(s));
  }

  @override
  void write(A? value, Map<String, String> q) {
    if (value != null) q[key] = _format(value);
  }
}

class _DefQuery<A> extends QueryParam<A> {
  const _DefQuery(this.key, this._parse, this._format, this.orElse);
  final String key;
  final A? Function(String) _parse;
  final String Function(A) _format;
  final A orElse;
  @override
  ({A value})? read(Map<String, String> q) {
    final s = q[key];
    if (s == null) return (value: orElse);
    final v = _parse(s);
    return v == null ? null : (value: v);
  }

  @override
  void write(A value, Map<String, String> q) {
    if (value != orElse) q[key] = _format(value);
  }
}

/// A URL fragment that captures a value of type [T] in both directions.
abstract class UrlPattern<T> {
  /// Const base so patterns can be const.
  const UrlPattern();

  /// Consume from [reader] and return the captured value, or null on no match.
  T? parse(UrlReader reader);

  /// Append [value]'s representation to [writer].
  void write(T value, UrlWriter writer);
}

/// Whole-URL parse/print helpers over a typed pattern.
extension UrlPatternUri<T> on UrlPattern<T> {
  /// Parse [uri] end-to-end, requiring the *entire* path to be consumed.
  /// Returns the typed capture, or null if it doesn't match or leaves segments.
  T? parseUri(Uri uri) {
    final reader = UrlReader.of(uri);
    final result = parse(reader);
    if (result == null || !reader.atEnd) return null;
    return result;
  }

  /// Print [value] to a `Uri`.
  Uri printUri(T value) {
    final writer = UrlWriter();
    write(value, writer);
    return writer.toUri();
  }
}

/// The empty pattern — matches the index path (`/`) and the start of every
/// fluent build. Add literals with `.seg`, params with `.param`.
const Path0 path = Path0(<_Step>[]);

sealed class _Step {
  const _Step();
}

class _Lit extends _Step {
  const _Lit(this.literal);
  final String literal;
}

class _Par extends _Step {
  const _Par(this.parse, this.format);
  final Object? Function(String segment) parse;
  final String Function(Object? value) format;
}

_Par _par<A>(UrlParam<A> param) =>
    _Par((s) => param.parse(s), (v) => param.format(v as A));

class _Query extends _Step {
  const _Query(this.read, this.write);
  final List<Object?>? Function(Map<String, String> query) read;
  final void Function(Object? value, Map<String, String> query) write;
}

_Query _query<A>(QueryParam<A> param) => _Query((query) {
  final result = param.read(query);
  return result == null ? null : <Object?>[result.value];
}, (value, query) => param.write(value as A, query));

/// Shared parse/write over the ordered [steps]; subclasses construct the
/// typed record from the raw captures.
abstract class _Path<T> extends UrlPattern<T> {
  const _Path(this.steps);
  final List<_Step> steps;

  List<Object?>? parseRaw(UrlReader r) {
    final captures = <Object?>[];
    for (final step in steps) {
      switch (step) {
        case _Lit(:final literal):
          if (r.peek() != literal) return null;
          r.take();
        case _Par(:final parse):
          final segment = r.peek();
          if (segment == null) return null;
          final value = parse(segment);
          if (value == null) return null;
          r.take();
          captures.add(value);
        case _Query(:final read):
          final result = read(r.query);
          if (result == null) return null;
          captures.add(result[0]);
      }
    }
    return captures;
  }

  void writeRaw(List<Object?> captures, UrlWriter w) {
    var i = 0;
    for (final step in steps) {
      switch (step) {
        case _Lit(:final literal):
          w.segments.add(literal);
        case _Par(:final format):
          w.segments.add(format(captures[i++]));
        case _Query(:final write):
          write(captures[i++], w.query);
      }
    }
  }
}

/// A pattern with no params.
class Path0 extends _Path<Unit> {
  /// Wrap [steps].
  const Path0(super.steps);

  /// Append a literal segment.
  Path0 seg(String literal) => Path0(<_Step>[...steps, _Lit(literal)]);

  /// Append a typed param, capturing [A].
  Path1<A> param<A>(UrlParam<A> p) => Path1<A>(<_Step>[...steps, _par(p)]);

  /// Append a query param, capturing [A].
  Path1<A> query<A>(QueryParam<A> q) => Path1<A>(<_Step>[...steps, _query(q)]);

  @override
  Unit? parse(UrlReader r) => parseRaw(r) == null ? null : ();
  @override
  void write(Unit value, UrlWriter w) => writeRaw(const <Object?>[], w);
}

/// A pattern with one param.
class Path1<A> extends _Path<(A,)> {
  /// Wrap [steps].
  const Path1(super.steps);

  /// Append a literal segment.
  Path1<A> seg(String literal) => Path1<A>(<_Step>[...steps, _Lit(literal)]);

  /// Append a typed param, capturing [B].
  Path2<A, B> param<B>(UrlParam<B> p) =>
      Path2<A, B>(<_Step>[...steps, _par(p)]);

  /// Append a query param, capturing [B].
  Path2<A, B> query<B>(QueryParam<B> q) =>
      Path2<A, B>(<_Step>[...steps, _query(q)]);

  @override
  (A,)? parse(UrlReader r) {
    final c = parseRaw(r);
    return c == null ? null : (c[0] as A,);
  }

  @override
  void write((A,) value, UrlWriter w) => writeRaw(<Object?>[value.$1], w);
}

/// A pattern with two params.
class Path2<A, B> extends _Path<(A, B)> {
  /// Wrap [steps].
  const Path2(super.steps);

  /// Append a literal segment.
  Path2<A, B> seg(String literal) =>
      Path2<A, B>(<_Step>[...steps, _Lit(literal)]);

  /// Append a typed param, capturing [C].
  Path3<A, B, C> param<C>(UrlParam<C> p) =>
      Path3<A, B, C>(<_Step>[...steps, _par(p)]);

  /// Append a query param, capturing [C].
  Path3<A, B, C> query<C>(QueryParam<C> q) =>
      Path3<A, B, C>(<_Step>[...steps, _query(q)]);

  @override
  (A, B)? parse(UrlReader r) {
    final c = parseRaw(r);
    return c == null ? null : (c[0] as A, c[1] as B);
  }

  @override
  void write((A, B) value, UrlWriter w) =>
      writeRaw(<Object?>[value.$1, value.$2], w);
}

/// A pattern with three params.
class Path3<A, B, C> extends _Path<(A, B, C)> {
  /// Wrap [steps].
  const Path3(super.steps);

  /// Append a literal segment.
  Path3<A, B, C> seg(String literal) =>
      Path3<A, B, C>(<_Step>[...steps, _Lit(literal)]);

  /// Append a typed param, capturing [D].
  Path4<A, B, C, D> param<D>(UrlParam<D> p) =>
      Path4<A, B, C, D>(<_Step>[...steps, _par(p)]);

  /// Append a query param, capturing [D].
  Path4<A, B, C, D> query<D>(QueryParam<D> q) =>
      Path4<A, B, C, D>(<_Step>[...steps, _query(q)]);

  @override
  (A, B, C)? parse(UrlReader r) {
    final c = parseRaw(r);
    return c == null ? null : (c[0] as A, c[1] as B, c[2] as C);
  }

  @override
  void write((A, B, C) value, UrlWriter w) =>
      writeRaw(<Object?>[value.$1, value.$2, value.$3], w);
}

/// A pattern with four params (the cap; beyond this, write a custom
/// [UrlPattern]).
class Path4<A, B, C, D> extends _Path<(A, B, C, D)> {
  /// Wrap [steps].
  const Path4(super.steps);

  /// Append a literal segment.
  Path4<A, B, C, D> seg(String literal) =>
      Path4<A, B, C, D>(<_Step>[...steps, _Lit(literal)]);

  @override
  (A, B, C, D)? parse(UrlReader r) {
    final c = parseRaw(r);
    return c == null ? null : (c[0] as A, c[1] as B, c[2] as C, c[3] as D);
  }

  @override
  void write((A, B, C, D) value, UrlWriter w) =>
      writeRaw(<Object?>[value.$1, value.$2, value.$3, value.$4], w);
}
