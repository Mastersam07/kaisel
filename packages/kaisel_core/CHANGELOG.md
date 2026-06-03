# Changelog

## 0.13.0 — Renamed to kaisel_core

Renamed from `gate_core` to `kaisel_core` as part of the gate → kaisel
rebrand. Mechanical rename, no behavioural change: every `Gate*` type is
now `Kaisel*`, and imports move from `package:gate_core/...` to
`package:kaisel_core/...`. See the
[`kaisel` changelog](https://github.com/Mastersam07/gate/blob/main/packages/kaisel/CHANGELOG.md)
for the full migration note.

## 0.12.0

Initial release of `kaisel_core`, extracted from the `kaisel` package as its
pure-Dart navigation core. Contains the sealed-route base, the `KaiselRouter`
stack container (now built on a Flutter-free change-notifier), the guard
pipeline, and the URL codecs — with no Flutter dependency.

Versioned in lockstep with `kaisel`; see the
[`kaisel` changelog](https://github.com/Mastersam07/gate/blob/main/packages/kaisel/CHANGELOG.md)
for the history of these APIs prior to the split.
