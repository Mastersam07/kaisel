# kaisel_lint example

`kaisel_lint` is an analyzer plugin, so the "example" is how you enable it and
what it flags. Each file under `lib/` carries a deliberate violation for one
rule, so an IDE with the plugin active highlights them (with quick fixes where
available).

## Enable it

```yaml
# pubspec.yaml
dev_dependencies:
  kaisel_lint: ^0.5.0
```

```yaml
# analysis_options.yaml
include: package:kaisel_lint/recommended.yaml
```

Including `recommended.yaml` activates the plugin with the correctness baseline
— `require_route_props` and `avoid_modal_route_on_main_stack` — on, and the
stylistic/adaptive rules off. To enable the others or tune severities, activate
the plugin yourself with a `diagnostics:` map (see `recommended.yaml`):

```yaml
plugins:
  kaisel_lint:
    version: ^0.5.0
    diagnostics:
      prefer_const_route_constructors: true
      prefer_pattern_match_over_is_check: true
      unused_guard_redirect: true
      prefer_push_or_replace_top_in_adaptive: true # fires on every push
```

## Rules

| Rule | Flags | Example file |
|---|---|---|
| `require_route_props` | A `KaiselRoute` with instance fields but no `props` override (breaks value equality). | `lib/props_violations.dart` |
| `avoid_modal_route_on_main_stack` | A `KaiselModalRoute` pushed onto the main stack instead of opened with `run<T>`. | `lib/modal_route_violations.dart` |
| `prefer_push_or_replace_top_in_adaptive` | `push()` in an adaptive master-detail branch where `pushOrReplaceTop()` avoids stacking duplicates. | `lib/adaptive_violations.dart` |
| `prefer_const_route_constructors` | A route construction that can be `const`. | `lib/const_violations.dart` |
| `prefer_pattern_match_over_is_check` | An `is`-check on a sealed route where a pattern match is exhaustive. | `lib/is_check_violations.dart` |
| `unused_guard_redirect` | A guard that returns the proposed stack unchanged on every path. | `lib/guard_violations.dart` |
