/// The typed codec DSL — an opt-in way to declare a URL ⇄ route mapping once
/// and get both directions, producing a `KaiselConfigCodec`.
///
/// Import this library directly (it is not part of the main `kaisel_core`
/// barrel) while it is exploratory. See `doc/design/codec-dsl.md`.
library;

export 'src/codec/url_pattern.dart';
