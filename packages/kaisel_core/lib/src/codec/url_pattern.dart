/// Bidirectional URL patterns — the substrate of the typed codec DSL.
///
/// A [UrlPattern] both *parses* a URL into captured values and *writes* those
/// values back into a URL, from one declaration, so the two directions are
/// inverse by construction. Patterns compose with `/` to any arity; captures
/// accumulate positionally and are read at the build boundary through the
/// typed [Captures] accessors (`c.string(0)`, `c.integer(1)`, …).
///
/// Captures are a `List<Object?>` rather than a record tuple because Dart can't
/// append to a record type generically (an operator can't turn `(A,)` and
/// `(B,)` into `(A, B)`, and records have no spread). The list model takes no
/// per-arity classes and no generator and composes to any depth; the typed
/// accessors recover safety at the one boundary where a route is built, and the
/// codec's round-trip self-check (a later step) catches any mismatch at startup.
library;

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

/// A cursor over captured values, consumed positionally while writing.
class CaptureCursor {
  /// Cursor over [values].
  CaptureCursor(this.values);

  /// The captures, in pattern order.
  final List<Object?> values;
  int _index = 0;

  /// Consume the next capture.
  Object? take() => values[_index++];
}

/// Typed, positional access to a pattern's captures, for building a route.
class Captures {
  /// Wrap the raw [values].
  const Captures(this.values);

  /// The captures, in pattern order.
  final List<Object?> values;

  /// The capture at [i] as a `String`.
  String string(int i) => values[i] as String;

  /// The capture at [i] as a `String?` (e.g. an optional query param).
  String? stringOrNull(int i) => values[i] as String?;

  /// The capture at [i] as an `int`.
  int integer(int i) => values[i] as int;

  /// The capture at [i] as an `int?`.
  int? integerOrNull(int i) => values[i] as int?;

  /// The capture at [i] as a `bool`.
  bool boolean(int i) => values[i] as bool;

  /// The capture at [i] as a `bool?`.
  bool? booleanOrNull(int i) => values[i] as bool?;

  /// The capture at [i] as an enum value of type [E].
  E enumValue<E extends Enum>(int i) => values[i] as E;

  /// The capture at [i] as a nullable enum value of type [E].
  E? enumValueOrNull<E extends Enum>(int i) => values[i] as E?;

  /// The raw capture at [i].
  Object? operator [](int i) => values[i];

  /// How many captures there are.
  int get length => values.length;
}

/// A URL fragment that captures values in both directions.
abstract class UrlPattern {
  /// Const base so leaf patterns can be const.
  const UrlPattern();

  /// Parse from [reader], appending captures to [out]; return false on no
  /// match, leaving [reader] where it started.
  bool parse(UrlReader reader, List<Object?> out);

  /// Write, consuming this pattern's captures from [cursor] in order.
  void write(CaptureCursor cursor, UrlWriter writer);

  /// Sequence this pattern, then [next].
  UrlPattern operator /(UrlPattern next) =>
      _Seq(<UrlPattern>[..._flatten(this), ..._flatten(next)]);
}

/// Whole-URL parse/print helpers over a pattern.
extension UrlPatternUri on UrlPattern {
  /// Parse [uri] end-to-end, requiring the *entire* path to be consumed.
  /// Returns the captures, or null if it doesn't match or leaves segments.
  List<Object?>? parseUri(Uri uri) {
    final reader = UrlReader.of(uri);
    final out = <Object?>[];
    if (!parse(reader, out) || !reader.atEnd) return null;
    return out;
  }

  /// Print [captures] to a `Uri`.
  Uri printUri(List<Object?> captures) {
    final writer = UrlWriter();
    write(CaptureCursor(captures), writer);
    return writer.toUri();
  }
}

/// Matches the empty path (the index route) and captures nothing.
const UrlPattern root = _Root();

/// Matches exactly the literal segment [literal], capturing nothing.
UrlPattern seg(String literal) => _Seg(literal);

/// Captures one path segment verbatim as a `String`.
const UrlPattern str = _Str();

/// Captures one path segment parsed as an `int` (no match if not an int).
const UrlPattern intg = _Intg();

/// Captures one path segment parsed as a `bool` (`true`/`false`).
const UrlPattern boolg = _Boolg();

/// Captures one path segment matched against an enum's `.name`.
UrlPattern enumOf<E extends Enum>(List<E> values) => _EnumOf<E>(values);

class _Root extends UrlPattern {
  const _Root();
  @override
  bool parse(UrlReader r, List<Object?> out) => r.atEnd;
  @override
  void write(CaptureCursor c, UrlWriter w) {}
}

class _Seg extends UrlPattern {
  const _Seg(this.literal);
  final String literal;
  @override
  bool parse(UrlReader r, List<Object?> out) {
    if (r.peek() != literal) return false;
    r.take();
    return true;
  }

  @override
  void write(CaptureCursor c, UrlWriter w) => w.segments.add(literal);
}

class _Str extends UrlPattern {
  const _Str();
  @override
  bool parse(UrlReader r, List<Object?> out) {
    final s = r.take();
    if (s == null) return false;
    out.add(s);
    return true;
  }

  @override
  void write(CaptureCursor c, UrlWriter w) =>
      w.segments.add(c.take() as String);
}

class _Intg extends UrlPattern {
  const _Intg();
  @override
  bool parse(UrlReader r, List<Object?> out) {
    final s = r.peek();
    if (s == null) return false;
    final n = int.tryParse(s);
    if (n == null) return false;
    r.take();
    out.add(n);
    return true;
  }

  @override
  void write(CaptureCursor c, UrlWriter w) =>
      w.segments.add('${c.take() as int}');
}

class _Boolg extends UrlPattern {
  const _Boolg();
  @override
  bool parse(UrlReader r, List<Object?> out) {
    final b = _parseBool(r.peek());
    if (b == null) return false;
    r.take();
    out.add(b);
    return true;
  }

  @override
  void write(CaptureCursor c, UrlWriter w) =>
      w.segments.add('${c.take() as bool}');
}

class _EnumOf<E extends Enum> extends UrlPattern {
  const _EnumOf(this.values);
  final List<E> values;
  @override
  bool parse(UrlReader r, List<Object?> out) {
    final value = _enumByName(r.peek(), values);
    if (value == null) return false;
    r.take();
    out.add(value);
    return true;
  }

  @override
  void write(CaptureCursor c, UrlWriter w) =>
      w.segments.add((c.take() as E).name);
}

/// A required query param captured as a `String` (no match if absent).
UrlPattern queryStr(String key) => _QueryReq(key, (s) => s, (v) => '$v');

/// A required query param parsed as an `int` (no match if absent or not an int).
UrlPattern queryIntReq(String key) => _QueryReq(key, int.tryParse, (v) => '$v');

/// An optional query param as a `String?` — null when absent.
UrlPattern queryStrOpt(String key) => _QueryOpt(key, (s) => s, (v) => '$v');

/// An optional query param parsed as an `int?` — null when absent or invalid.
UrlPattern queryIntOpt(String key) => _QueryOpt(key, int.tryParse, (v) => '$v');

/// An optional query param parsed as a `bool?`.
UrlPattern queryBoolOpt(String key) => _QueryOpt(key, _parseBool, (v) => '$v');

/// An optional query param matched against an enum's `.name`.
UrlPattern queryEnumOpt<E extends Enum>(String key, List<E> values) =>
    _QueryOpt(key, (s) => _enumByName(s, values), (v) => (v as E).name);

/// A query param with a default: absent reads as [orElse]; writing [orElse]
/// omits the key, so a default-valued state has a clean URL.
UrlPattern queryInt(String key, {required int orElse}) =>
    _QueryDef(key, int.tryParse, (v) => '$v', orElse);

class _QueryReq extends UrlPattern {
  const _QueryReq(this.key, this._parse, this._format);
  final String key;
  final Object? Function(String) _parse;
  final String Function(Object?) _format;
  @override
  bool parse(UrlReader r, List<Object?> out) {
    final s = r.query[key];
    if (s == null) return false;
    final value = _parse(s);
    if (value == null) return false;
    out.add(value);
    return true;
  }

  @override
  void write(CaptureCursor c, UrlWriter w) => w.query[key] = _format(c.take());
}

class _QueryOpt extends UrlPattern {
  const _QueryOpt(this.key, this._parse, this._format);
  final String key;
  final Object? Function(String) _parse;
  final String Function(Object?) _format;
  @override
  bool parse(UrlReader r, List<Object?> out) {
    final s = r.query[key];
    out.add(s == null ? null : _parse(s));
    return true;
  }

  @override
  void write(CaptureCursor c, UrlWriter w) {
    final value = c.take();
    if (value != null) w.query[key] = _format(value);
  }
}

class _QueryDef extends UrlPattern {
  const _QueryDef(this.key, this._parse, this._format, this.orElse);
  final String key;
  final Object? Function(String) _parse;
  final String Function(Object?) _format;
  final Object? orElse;
  @override
  bool parse(UrlReader r, List<Object?> out) {
    final s = r.query[key];
    if (s == null) {
      out.add(orElse);
      return true;
    }
    final value = _parse(s);
    if (value == null) return false;
    out.add(value);
    return true;
  }

  @override
  void write(CaptureCursor c, UrlWriter w) {
    final value = c.take();
    if (value != orElse) w.query[key] = _format(value);
  }
}

List<UrlPattern> _flatten(UrlPattern p) =>
    p is _Seq ? p.parts : <UrlPattern>[p];

class _Seq extends UrlPattern {
  _Seq(this.parts);
  final List<UrlPattern> parts;
  @override
  bool parse(UrlReader r, List<Object?> out) {
    final savedPos = r.position;
    final savedLen = out.length;
    for (final part in parts) {
      if (!part.parse(r, out)) {
        r.position = savedPos;
        out.removeRange(savedLen, out.length);
        return false;
      }
    }
    return true;
  }

  @override
  void write(CaptureCursor c, UrlWriter w) {
    for (final part in parts) {
      part.write(c, w);
    }
  }
}

bool? _parseBool(String? s) => switch (s) {
  'true' => true,
  'false' => false,
  _ => null,
};

E? _enumByName<E extends Enum>(String? s, List<E> values) {
  if (s == null) return null;
  for (final value in values) {
    if (value.name == s) return value;
  }
  return null;
}
