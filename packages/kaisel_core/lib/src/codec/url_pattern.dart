/// Bidirectional URL patterns — the substrate of the typed codec DSL.
///
/// A [UrlPattern] both *parses* a URL into a captured value and *writes* that
/// value back into a URL, from one declaration, so the two directions are
/// inverse by construction. Captures are records: a literal segment captures
/// the empty record [Unit], a single param captures a 1-record (`(String,)`),
/// and composition (a later step) concatenates them.
///
/// See `doc/design/codec-dsl.md` for the full design.
library;

/// The empty capture — what a literal segment (or the root) captures.
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

/// A URL fragment that captures a value of type [T] in both directions.
abstract class UrlPattern<T> {
  /// Const base so leaf patterns can be const.
  const UrlPattern();

  /// Consume from [reader] and return the captured value, or null on no match.
  /// On no match, leave [reader] positioned where it was found.
  T? parse(UrlReader reader);

  /// Append [value]'s representation to [writer].
  void write(T value, UrlWriter writer);
}

/// Whole-URL parse/print helpers over a pattern.
extension UrlPatternUri<T> on UrlPattern<T> {
  /// Parse [uri] end-to-end, requiring the *entire* path to be consumed.
  /// Returns null if it doesn't match or leaves segments unread.
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

/// Matches the empty path (the index route) and captures nothing.
const UrlPattern<Unit> root = _Root();

/// Matches exactly the literal segment [literal], capturing nothing.
UrlPattern<Unit> seg(String literal) => _Seg(literal);

/// Captures one path segment verbatim as a `String`.
const UrlPattern<(String,)> str = _Str();

/// Captures one path segment parsed as an `int` (no match if not an int).
const UrlPattern<(int,)> intg = _Intg();

/// Captures one path segment parsed as a `bool` (`true`/`false`).
const UrlPattern<(bool,)> boolg = _Boolg();

/// Captures one path segment matched against an enum's `.name`.
UrlPattern<(E,)> enumOf<E extends Enum>(List<E> values) => _EnumOf<E>(values);

class _Root extends UrlPattern<Unit> {
  const _Root();
  @override
  Unit? parse(UrlReader r) => r.atEnd ? () : null;
  @override
  void write(Unit value, UrlWriter w) {}
}

class _Seg extends UrlPattern<Unit> {
  const _Seg(this.literal);
  final String literal;
  @override
  Unit? parse(UrlReader r) {
    if (r.peek() != literal) return null;
    r.take();
    return ();
  }

  @override
  void write(Unit value, UrlWriter w) => w.segments.add(literal);
}

class _Str extends UrlPattern<(String,)> {
  const _Str();
  @override
  (String,)? parse(UrlReader r) {
    final s = r.take();
    return s == null ? null : (s,);
  }

  @override
  void write((String,) value, UrlWriter w) => w.segments.add(value.$1);
}

class _Intg extends UrlPattern<(int,)> {
  const _Intg();
  @override
  (int,)? parse(UrlReader r) {
    final s = r.peek();
    if (s == null) return null;
    final n = int.tryParse(s);
    if (n == null) return null;
    r.take();
    return (n,);
  }

  @override
  void write((int,) value, UrlWriter w) => w.segments.add('${value.$1}');
}

class _Boolg extends UrlPattern<(bool,)> {
  const _Boolg();
  @override
  (bool,)? parse(UrlReader r) {
    final b = switch (r.peek()) {
      'true' => true,
      'false' => false,
      _ => null,
    };
    if (b == null) return null;
    r.take();
    return (b,);
  }

  @override
  void write((bool,) value, UrlWriter w) => w.segments.add('${value.$1}');
}

class _EnumOf<E extends Enum> extends UrlPattern<(E,)> {
  const _EnumOf(this.values);
  final List<E> values;
  @override
  (E,)? parse(UrlReader r) {
    final s = r.peek();
    if (s == null) return null;
    for (final value in values) {
      if (value.name == s) {
        r.take();
        return (value,);
      }
    }
    return null;
  }

  @override
  void write((E,) value, UrlWriter w) => w.segments.add(value.$1.name);
}
