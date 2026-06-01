# Changelog

## 0.12.0

Initial release of `gate_core`, extracted from the `gate` package as its
pure-Dart navigation core. Contains the sealed-route base, the `GateRouter`
stack container (now built on a Flutter-free change-notifier), the guard
pipeline, and the URL codecs — with no Flutter dependency.

Versioned in lockstep with `gate`; see the
[`gate` changelog](https://github.com/Mastersam07/gate/blob/main/packages/gate/CHANGELOG.md)
for the history of these APIs prior to the split.
