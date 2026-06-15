# Design sketch: a typed codec DSL

**Status:** exploratory design. Nothing here is implemented. This documents the
shape of a typed URL codec for kaisel, what part of it can be made "free," what
fundamentally can't be (a Dart limitation), where codegen legitimately fits, and
a full spec including nested shell/module URLs.

## 1. The problem

Writing a `KaiselConfigCodec<R>` by hand is the most verbose and most bug-prone
part of a URL-addressable kaisel app. Two failure modes:

1. **Verbosity.** Every route appears twice — in `decode` (URL → route) and
   `encode` (route → URL) — in two separate methods, plus manual `Uri`/segment
   plumbing. Real codecs reach hundreds of lines.

2. **The round-trip bug class.** Because `encode` and `decode` are independent
   methods, they drift. Field examples:
   - `encode` produced `/home?type=lookingFor` for a resting home-filter state
     while `decode` mapped that exact URL to a *different* tab — drift to the
     wrong screen on every reload.
   - A `_normalizeUri` helper stripped the first path segment of every web URL
     (`/chat` → `/`) because the two sides were maintained apart.

Same root cause both times: **two methods, free to disagree.** The fix is always
"make them inverses." The goal of this design is to make that the only thing you
*can* express.

## 2. What can be "free," and what can't

A URL codec is two compositions:

```
URL  <—— grammar ——>  captures  <—— binding ——>  route
```

- **The grammar** (URL ⇄ captured values) is pure string manipulation. It can be
  declared **once** and yield both parse and print, as in invertible-syntax URL
  parsers (e.g. Elm). The DSL provides this.

- **The binding** (captured values ⇄ a typed route object) is *not* free in
  Dart. To go captures → route you must **call a constructor**; to go route →
  captures you must **destructure fields**. Dart AOT has no reflection, so:
  - you cannot invoke a constructor selected at runtime, and
  - you cannot derive the destructor from the constructor (or vice-versa).

So the **irreducible floor**, per route, with no codegen, is: *name the
constructor.* Everything else can be made free or near-free:

| Piece | Free? | Why |
| --- | --- | --- |
| URL ⇄ captures (parse + print) | **Yes** | one `UrlPattern`, both directions derived |
| captures → route (`build`) | **No** | must name the constructor (Dart can't synthesise it) |
| route → captures (`match`) | **Near-free** | derivable from `props` at runtime, or by codegen |

The DSL supplies the first row, auto-derives the third row from `props`, and
leaves the second row — the constructor — which the language cannot synthesise.
Codegen's role is limited to that second row: generating `build` and the rule
from the route declaration. The grammar is a DSL concern; the binding is the
codegen concern; the two compose.

## 3. The learning-cost trilemma

You can have any two of: **zero to learn**, **full URL control**, **no build
step**.

- **DSL** → control + no build step, but a small vocabulary to learn.
- **Convention codegen** (derive URLs from route names) → zero to learn + no
  control (rigid URL shapes; breaks for custom URLs like `/home/sublets_filter`).
- **Annotation codegen** → control + little to learn, but a build step and
  string path templates (the thing kaisel rejects).

The resolution is to **layer them on one substrate**:

```
                 ┌─────────────────────────────────────────────┐
  power user  →  │  DSL (this doc): rules in plain Dart         │  ← hand-writable
                 ├─────────────────────────────────────────────┤
  zero-learn  →  │  codegen / macro: emits the DSL rules        │  ← optional, never load-bearing
                 └─────────────────────────────────────────────┘
                                    │ both produce
                                    ▼
                          KaiselConfigCodec<R>
```

Control mode writes the DSL directly. Zero-learn mode annotates routes and a
generator writes the DSL; because the generator's output is ordinary DSL, it
stays readable and the generator can be removed without breaking the app
(unlike a model where codegen is load-bearing). The DSL surface is small (about
six combinators), plain Dart, with autocomplete and go-to-definition.

Sections 4–10 specify the substrate (the DSL). Section 11 covers what a
generator on top would emit.

## 4. Core model: bidirectional patterns

The unit is a **`UrlPattern<T>`** — one value that both *parses* and *prints*:

- **parse:** consume path segments / query params, produce a captured `T`, or
  fail to match.
- **print:** take a `T`, append the segments / query it represents.

`T` is the capture type (a record): a literal captures `()`, a string param
`(String,)`, composition concatenates. `parse` and `print` live on the same
object, so `parse(print(t)) == t` by construction.

## 5. The combinators

### 5.1 Segments

```dart
UrlPattern<()>        seg(String literal);   // exact segment
UrlPattern<(String,)> get str;               // capture a segment as String
UrlPattern<(int,)>    get intg;              // capture + parse int
UrlPattern<(bool,)>   get boolg;
UrlPattern<(E,)>      enumOf<E extends Enum>(List<E> values);  // by .name
```

### 5.2 Composition

`/` sequences path patterns and concatenates captures:

```dart
seg('products') / str          // UrlPattern<(String,)>      /products/<string>
seg('chat') / str / intg       // UrlPattern<(String, int)>  /chat/<string>/<int>
```

> **Dart limit.** No variadic generics, so `/` is a fixed overload set for
> arities 0–4. Four captures covers real routes; beyond that, drop to
> `Rule.custom` (§9).

### 5.3 Query parameters

Unordered, often optional, so separate combinators that still add to the capture
tuple (merged with `&`):

```dart
UrlPattern<(String,)>  queryStr(String key);                 // required
UrlPattern<(String?,)> queryStrOpt(String key);              // optional → nullable
UrlPattern<(int,)>     queryInt(String key, {required int orElse});
UrlPattern<(bool?,)>   queryBoolOpt(String key);
UrlPattern<(E?,)>      queryEnumOpt<E extends Enum>(String key, List<E> values);
```

`orElse`: parse fills the default when the key is absent; print **omits a value
equal to the default**. A default-valued state therefore has a clean, key-free
canonical URL, so it cannot encode to a URL that decodes to a different state.

```dart
seg('search') & queryStr('q') & queryInt('page', orElse: 1)
// /search?q=<string>            when page == 1
// /search?q=<string>&page=<int> when page != 1
```

## 6. Binding a pattern to a route

A `UrlPattern<T>` becomes a `Rule<R>`. You always supply `build` (the
constructor — the irreducible floor). For `match` you have two choices:

```dart
// 1. Explicit (full control):
(seg('products') / str)
    .to((c) => ProductDetail(c.$1))
    .from((r) => r is ProductDetail ? (r.id,) : null);

// 2. Derived from props (the common case — write only the constructor):
(seg('products') / str)
    .to((c) => ProductDetail(c.$1))
    .fromType<ProductDetail>();   // captures = this route's props, in order
```

`.fromType<T>()` matches when `route is T` and reads its `props` as the captures
(the third row from §2: the constructor is written, the destructor is derived).
Its contract — `props` order matches the pattern's capture order — is verified by
the self-check (§8), so a mismatch surfaces at construction rather than at
runtime.

No-capture routes get a shortcut:

```dart
fixed(const Home(), seg('/'));
fixed(const Settings(), seg('settings') / seg('account'));
```

### Breadcrumb stacks

A deep link should restore a full back-stack. The rule can build one:

```dart
(seg('products') / str)
    .under([const Home(), const ProductList()])   // breadcrumb prefix
    .to((c) => ProductDetail(c.$1))
    .fromType<ProductDetail>();
// decode → mainStack [Home(), ProductList(), ProductDetail(id)]
// encode → matches on the leaf only; the prefix is decode-side scaffolding
```

## 7. Nested state: shells and modules

`KaiselConfig` carries `nestedState` — a `KaiselShellConfig`
(`activeBranch` + that branch's stack) or `KaiselModuleConfig` (a stack). The
DSL expresses these as composite rules.

### 7.1 Shells

Branches are keyed by a **typed branch token** shared with the
`KaiselBranchedShell`, so the codec's branch index and the shell's branch order
cannot drift:

```dart
enum AppBranch { home, matches, chat, profile }   // shared with the shell widget

shellRule<AppBranch>(
  host: const ShellHost(),            // the main-stack route that renders the shell
  index: (b) => b.index,              // AppBranch -> the int the shell uses
  branches: {
    AppBranch.home: [
      fixed(const HomeTab(), seg('home')),
      (seg('home') / seg('sublets_filter') & queryStrOpt('location'))
          .to((c) => SubletsFilter(location: c.$1))
          .fromType<SubletsFilter>(),
    ],
    AppBranch.matches: [
      (seg('matches') & queryBoolOpt('refresh'))
          .to((c) => MatchesTab(refresh: c.$1))
          .fromType<MatchesTab>(),
    ],
  },
)
```

- **decode:** try every branch's rules; the first match yields
  `KaiselConfig(mainStack: [host], nestedState: KaiselShellConfig(
  activeBranch: index(thatBranch), activeBranchStack: [built stack]))`.
- **encode:** when `config.nestedState` is a `KaiselShellConfig`, find the branch
  whose `index` equals `activeBranch`, take `activeBranchStack.last`, and run
  that branch's rules to print.

Each branch owns its URLs and its rules are separately ordered, so a URL cannot
be claimed by more than one branch through independent decode arms.

### 7.2 Modules

```dart
moduleRule(
  mountedWhen: (config) => config.nestedState is CheckoutModuleConfig,
  prefix: seg('checkout'),
  rules: [
    fixed(const CartStep(), seg('cart')),
    (seg('payment') / str).to((c) => PaymentStep(c.$1)).fromType<PaymentStep>(),
  ],
)
// decode /checkout/payment/visa → KaiselConfig(mainStack: [host],
//   nestedState: KaiselModuleConfig(stack: [..., PaymentStep('visa')]))
```

### 7.3 Composition

```dart
final codec = RouteCodec<AppRoute>(
  rules: [
    fixed(const Splash(), seg('splash')),
    shellRule<AppBranch>(host: const ShellHost(), index: (b) => b.index, branches: { ... }),
    moduleRule(prefix: seg('checkout'), rules: [ ... ]),
    (seg('paywall')).to((c) => Paywall()).fromType<Paywall>(),   // full-screen over the shell
  ],
  fallback: (uri) => [const ShellHost(), NotFound(uri.path)],
);
```

`shellRule` / `moduleRule` are themselves `Rule<R>`s, so they live in the same
ordered list as flat rules and dispatch the same way.

## 8. How it works, and the round-trip guarantee

**decode:** normalise the `Uri` to a cursor over `(pathSegments, query)`; try
each rule's parse **in declaration order**; first full-path match wins; build the
config (with breadcrumb / nested state). No match → `fallback`.

**encode:** take the config's leaf (`mainStack.last`, or the active nested
route); try each rule's `match` **in the same order**; first non-null prints.

Two structural guarantees and one limit:

1. **Within a rule**, parse and print are one `UrlPattern`, so they are inverse
   by construction.
2. **Across rules**, both directions walk the **same ordered list**, so encode
   and decode cannot select different rules for the same route or URL. Separate
   `encode` and `decode` methods deciding independently is not expressible.
3. **Limit:** `build` and `match` are two functions (Dart cannot invert one), so
   they can mismatch (e.g. `build` reads `c.$1` as `id` while `match` returns
   `(r.name,)`). This is not compile-checked. It is caught at construction by a
   self-check: `RouteCodec` round-trips a canonical sample of every rule and
   asserts it decodes back to the same rule. `.fromType` reduces the risk to the
   `props`-order contract, which the same check verifies. The result is a
   construction-time error rather than a static guarantee.

## 9. Dart constraints and escape hatch

- **No variadic generics** → fixed `/` and `&` overloads, arities 0–4.
- **No record spread into positional args** → `build`/`match` use `c.$1`, `c.$2`.
- **No reflection** → `build` must name the constructor; `.fromType` reads
  `props`. This is the §2 floor.
- **Escape hatch:** `Rule.custom(parse: (cursor) => R?, print: (R) => Uri?)` for
  anything the combinators can't express; beyond that, a hand-written
  `KaiselConfigCodec`. The DSL never needs to be total.

## 10. Worked example

```dart
final codec = RouteCodec<AppRoute>(
  rules: [
    fixed(const Splash(), seg('splash')),

    shellRule<AppBranch>(
      host: const ShellHost(),
      index: (b) => b.index,
      branches: {
        AppBranch.home: [
          fixed(const HomeTab(), seg('home')),
          (seg('home') / seg('sublets_filter') & queryStrOpt('location'))
              .to((c) => SubletsFilter(location: c.$1))
              .fromType<SubletsFilter>(),
        ],
        AppBranch.matches: [
          (seg('matches') & queryBoolOpt('refresh'))
              .to((c) => MatchesTab(refresh: c.$1))
              .fromType<MatchesTab>(),
        ],
      },
    ),

    (seg('products') / str)
        .under([const ShellHost()])
        .to((c) => ProductDetail(c.$1))
        .fromType<ProductDetail>(),
  ],
  fallback: (uri) => [const ShellHost(), NotFound(uri.path)],
);
```

This is the full hand-written form. The annotation-plus-generator alternative
(§11) emits the same rules. In both, the per-route leaf is one line: a URL
pattern plus a constructor.

## 11. The codegen layer (optional, on top)

Codegen here is **optional sugar over the DSL, never a requirement** — and it's
two distinct things, which are easy to conflate:

1. **Rule-gen** — emit the `RouteCodec` rules from annotations, so a user who
   doesn't want to learn the DSL never writes it.
2. **`props` macro** — derive `props` from a route's fields, killing the one
   remaining route-class ceremony line.

### 11.1 Rule-gen: keeping the DSL *optional*

The point is not to replace the DSL — it's to make writing it optional, via a
two-mode model on one substrate:

- **Power user** writes the DSL directly: `RouteCodec(rules: [...])`.
- **Zero-learn user** annotates routes; a generator emits the *same* DSL; they
  never see it.

```dart
@url(seg('products') / param)   // a typed annotation, not a "/products/:id" string
final class ProductDetail extends AppRoute {
  const ProductDetail(this.id);
  final String id;
}
// the generator emits ordinary DSL:
(seg('products') / str)
    .to((c) => ProductDetail(c.string(0)))
    .from((r) => r is ProductDetail ? r.props : null)
```

The generator **targets the DSL**, not a parallel imperative codec. It is
therefore not load-bearing: removing the generator and keeping its output leaves
a working app, unlike a model where generated code is required at runtime.

Cost: "not writing the DSL" is not "writing nothing":

- The URL shape must be declared somewhere, so a route still carries a `@url(...)`
  annotation — a different syntax, not the absence of one.
- Dart macros are paused (early 2025), so generating from annotations requires
  `build_runner`, reintroducing the build step the DSL avoids.

The trade is that the DSL stays optional at the cost of per-route annotations and
a build step. Once the DSL is one line per rule, an annotation saves few
keystrokes, so the value is optionality rather than brevity. This is the last
component to build, after the DSL is validated against a real codec.

### 11.2 The `props` macro

Independent of the codec, and the cleaner target: a macro reads a route's
constructor fields and emits `props`, removing the only ceremony line on the
route classes (see §11.3). No annotations, no strings. The same
`build_runner`-vs-macro caveat applies; until macros return, an IDE snippet or a
`kaisel_lint` quick-fix already writes that line on demand with zero
infrastructure.

### 11.3 What codegen can — and can't — do for the route classes

Codegen cannot remove the route-class declarations, because the route classes are
domain data rather than boilerplate:

```dart
final class ProductDetail extends AppRoute {
  const ProductDetail(this.id);              // how to make one
  final String id;                            // the payload — your actual data
  @override List<Object?> get props => [id]; // the ONLY ceremony
}
```

The field `final String id` is the information *"this app has a product-detail
screen and it carries an id."* Codegen can't invent that — it has to be declared
somewhere. So codegen can only **relocate** it or **strip the ceremony** around
it, never conjure it:

| Part of a route | Removable by codegen? | How / cost |
| --- | --- | --- |
| The fields (`final String id`) | **No** | it's your data; must be declared somewhere |
| The constructor | Barely | a macro could derive it from the fields |
| `props` | **Yes** | a macro reads the fields and emits it — the clean win |
| The class existing at all | **No** (not without inverting the model) | only by generating routes *from screens* — that's auto_route |

Generating routes *from annotated screens* (auto_route's model) is the one way to
"not write the classes," but it costs the thesis: the **screen** becomes the
source of truth, so routes stop being pure-Dart values you can push, test, and
serialise without Flutter; the add-route → compile-error loop now runs through a
regen step; and the build step returns. You also haven't reduced **N** — you've
moved N declarations onto N widgets and added machinery.

The number of routes is set by **your app**, not the framework: go_router makes
you declare N `GoRoute`s, auto_route N annotated screens, kaisel N sealed
classes — same N, it's how many screens you have. kaisel's per-route cost is
already ~3 lines of pure data, and `props` (a macro target) is the only line
that isn't. So the floor is low, but it *is* a floor: the route declarations are
your app's surface area, not framework noise.

## 12. Build order

Each step is independently testable; this is an order, not a versioning plan —
the spec above is the whole target.

1. `UrlPattern<T>` core: parse/print cursor + leaf combinators
   (`seg`, `str`, `intg`, `boolg`, `enumOf`).
2. Composition: `/` and `&` overloads, arities 0–4.
3. Query combinators: required / optional / `orElse`-with-omit.
4. `Rule<R>`: `.to`, `.from`, `.fromType`, `fixed`, `.under`/`.toStack`,
   `Rule.custom`.
5. `RouteCodec<R>`: ordered dispatch both directions, `fallback`, the debug
   round-trip self-check.
6. Nested: `shellRule` (typed branch token) and `moduleRule`.
7. Property tests: `decode(encode(build(c))) == build(c)` per rule; ambiguity /
   ordering; the field-bug regression; nested round-trips.
8. (Optional) the codegen layer — `props` macro first; rule annotation second,
   if justified.

Steps 1–7 are a Flutter-free package (`kaisel_codec` or part of `kaisel_core`):
they touch only `Uri`, `KaiselRoute`, `KaiselConfig`, `KaiselConfigCodec`.

## 13. Open questions

- **Capture ergonomics:** records (`c.$1`) vs named captures vs fixed-arity
  `.to1`/`.to2`. Records are the least machinery.
- **`.fromType` props contract:** is debug-time round-trip verification enough,
  or should a lint enforce props-order alignment statically?
- **Branch token coupling:** sharing an `enum AppBranch` between codec and shell
  removes the index-mismatch risk but couples the two definitions.
- **Is rule-codegen worth it** once the DSL + `.fromType` land, or does `props`
  generation cover the real ceremony?
- **Default-omission scope:** query only, or also optional path segments with
  defaults?
