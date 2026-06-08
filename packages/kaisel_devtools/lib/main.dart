import 'package:devtools_extensions/devtools_extensions.dart';
import 'package:flutter/material.dart';

import 'src/inspector_view.dart';

void main() {
  runApp(const KaiselDevToolsExtension());
}

/// Entry widget for the kaisel DevTools extension. [DevToolsExtension] wires up
/// the DevTools theme and the `serviceManager` / `extensionManager` globals.
class KaiselDevToolsExtension extends StatelessWidget {
  /// Create the extension app.
  const KaiselDevToolsExtension({super.key});

  @override
  Widget build(BuildContext context) {
    return const DevToolsExtension(child: KaiselInspectorView());
  }
}
