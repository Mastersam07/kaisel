# Changelog

## 0.1.0 — Foundation

Initial release.

- `GateRoute` base marker for sealed route types.
- `GateRouter<R>` state container with `push`, `pop`, `replace`, `set`, `popUntil`.
- `GateRouterDelegate<R>` plugging into `MaterialApp.router`.
- `GateRouteInformationParser<R>` for URL → route stack restoration.
- `GateCodec<R>` interface for URL ↔ route mapping.
- Identity-stable internal page keying so duplicate equal routes on the stack coexist.
- Pure-Dart unit tests for the navigation state.

### Deliberately not yet shipped (v0.2+):

- Guards as pure-function transforms.
- `Shell` / `Branch` for tab/scoped navigation.
- Modal sub-flows with typed result returns.
- Composable `RouteModule`s.
- Multi-route URL encoding.
- Adaptive layout policies.
- Direction-aware and shared-element transitions.
