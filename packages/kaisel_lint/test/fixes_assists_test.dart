// End-to-end tests for the kaisel_lint quick fixes and assists.
//
// AnalysisRuleTest (rules_test.dart) only verifies that a rule *reports* a
// diagnostic — it can't see the fixes or assists. To exercise those we stand
// up a real PluginServer (the same host the analysis server runs), give it a
// resolved file, ask it for fixes/assists at a cursor, apply the returned
// SourceChange, and assert the rewritten source. This mirrors
// analysis_server_plugin's own PluginServerTestBase.
//
// The harness reaches into a few `src/` test utilities (the mock SDK, the
// PluginServer, TestCode) — the same ones the framework's own tests use.

// ignore_for_file: implementation_imports, non_constant_identifier_names

import 'dart:async';

import 'package:analysis_server_plugin/src/plugin_server.dart';
import 'package:analyzer/file_system/file_system.dart';
import 'package:analyzer/src/test_utilities/mock_sdk.dart';
import 'package:analyzer/src/test_utilities/test_code_format.dart';
import 'package:analyzer/utilities/package_config_file_builder.dart';
import 'package:analyzer_plugin/channel/channel.dart';
import 'package:analyzer_plugin/protocol/protocol.dart' as protocol;
import 'package:analyzer_plugin/protocol/protocol_common.dart' as protocol;
import 'package:analyzer_plugin/protocol/protocol_generated.dart' as protocol;
import 'package:analyzer_plugin/src/protocol/protocol_internal.dart'
    as protocol;
import 'package:analyzer_testing/resource_provider_mixin.dart';
import 'package:kaisel_lint/src/plugin.dart';
import 'package:test/test.dart';
import 'package:test_reflective_loader/test_reflective_loader.dart';

void main() {
  defineReflectiveSuite(() {
    defineReflectiveTests(FixTest);
    defineReflectiveTests(AssistTest);
  });
}

/// Minimal stand-in for `package:kaisel`. Return types are kept synchronous so
/// only `dart:core` is needed from the mock SDK.
const _kaiselStub = r'''
class KaiselRoute {
  const KaiselRoute();
  List<Object?> get props => const [];
}

abstract interface class KaiselModalRoute<T> {}

class KaiselRouter<R> {
  void push(R route) {}
  void pushOrReplaceTop(R route) {}
  T? run<T>(KaiselModalRoute<T> route) => null;
}
''';

/// A [PluginCommunicationChannel] that records requests and lets the test
/// resolve their responses, modelled on analysis_server_plugin's test channel.
class FakeChannel implements PluginCommunicationChannel {
  final _completers = <String, Completer<protocol.Response>>{};
  final _notifications = StreamController<protocol.Notification>();
  void Function(protocol.Request)? _onRequest;
  int _idCounter = 0;

  @override
  void close() {}

  @override
  void listen(
    void Function(protocol.Request request)? onRequest, {
    void Function()? onDone,
    Function? onError,
    Function? onNotification,
  }) => _onRequest = onRequest;

  @override
  void sendNotification(protocol.Notification notification) =>
      _notifications.add(notification);

  @override
  void sendResponse(protocol.Response response) =>
      _completers.remove(response.id)?.complete(response);

  Future<protocol.Response> sendRequest(protocol.RequestParams params) {
    final onRequest = _onRequest;
    if (onRequest == null) {
      throw StateError('listen() has not been called on the channel');
    }
    final request = params.toRequest('${_idCounter++}');
    final completer = Completer<protocol.Response>();
    _completers[request.id] = completer;
    onRequest(request);
    return completer.future;
  }
}

abstract class _PluginTestBase with ResourceProviderMixin {
  final channel = FakeChannel();
  late final PluginServer pluginServer;

  Folder get sdkRoot => getFolder('/sdk');
  Folder get byteStoreRoot => getFolder('/byteStore');
  String get packagePath => convertPath('/package');
  String get kaiselPath => convertPath('/kaisel');
  String get filePath => join(packagePath, 'lib', 'test.dart');

  Future<void> setUp() async {
    createMockSdk(resourceProvider: resourceProvider, root: sdkRoot);

    newFile(join(kaiselPath, 'lib', 'kaisel.dart'), _kaiselStub);
    newPackageConfigJsonFileFromBuilder(
      packagePath,
      PackageConfigFileBuilder()
        ..add(name: 'test', rootPath: packagePath)
        ..add(name: 'kaisel', rootPath: kaiselPath),
    );
    newAnalysisOptionsYamlFile(packagePath, '''
plugins:
  kaisel_lint:
    path: some/path
    diagnostics:
      avoid_modal_route_on_main_stack: true
      require_route_props: true
      prefer_push_or_replace_top_in_adaptive: true
''');

    pluginServer = PluginServer(
      resourceProvider: resourceProvider,
      plugins: [KaiselLintPlugin()],
    );
    await pluginServer.initialize();
    pluginServer.start(channel);
    await pluginServer.handlePluginVersionCheck(
      protocol.PluginVersionCheckParams(
        byteStoreRoot.path,
        sdkRoot.path,
        '0.0.1',
      ),
    );
  }

  void tearDown() {}

  /// Writes [content] to the test file and registers the context root, so the
  /// plugin analyzes it.
  Future<TestCode> _analyze(String content) async {
    final code = TestCode.parseNormalized(content);
    newFile(filePath, code.code);
    await channel.sendRequest(
      protocol.AnalysisSetContextRootsParams([
        protocol.ContextRoot(packagePath, []),
      ]),
    );
    return code;
  }

  /// Applies [change]'s edits for the test file to [original], last-to-first so
  /// offsets stay valid.
  String _apply(String original, protocol.SourceChange change) {
    final fileEdit = change.edits.singleWhere((e) => e.file == filePath);
    final edits = [...fileEdit.edits]
      ..sort((a, b) => b.offset.compareTo(a.offset));
    var result = original;
    for (final edit in edits) {
      result = result.replaceRange(
        edit.offset,
        edit.offset + edit.length,
        edit.replacement,
      );
    }
    return result;
  }
}

@reflectiveTest
class FixTest extends _PluginTestBase {
  /// Resolves the single fix whose message is [message], offered at the `^`
  /// cursor in [content], and returns the source with that fix applied.
  Future<String> _fixed(String content, String message) async {
    final code = await _analyze(content);
    final result = await pluginServer.handleEditGetFixes(
      protocol.EditGetFixesParams(filePath, code.position.offset),
    );
    final changes = result.fixes.expand((f) => f.fixes);
    final change = changes
        .firstWhere((c) => c.change.message == message)
        .change;
    return _apply(code.code, change);
  }

  Future<void> test_addPropsOverride() async {
    final fixed = await _fixed(r'''
import 'package:kaisel/kaisel.dart';

final class ^ProductDetail extends KaiselRoute {
  const ProductDetail(this.id);
  final String id;
}
''', 'Add props override');
    expect(fixed, '''
import 'package:kaisel/kaisel.dart';

final class ProductDetail extends KaiselRoute {
  const ProductDetail(this.id);
  final String id;

  @override
  List<Object?> get props => [id];
}
''');
  }

  Future<void> test_convertPushToRun() async {
    final fixed = await _fixed(r'''
import 'package:kaisel/kaisel.dart';

final class AddCardFlow extends KaiselRoute
    implements KaiselModalRoute<String> {
  const AddCardFlow();
}

void open(KaiselRouter<KaiselRoute> router) {
  router.^push(const AddCardFlow());
}
''', 'Convert push() to run<T>()');
    expect(fixed, contains('router.run<String>(const AddCardFlow());'));
  }

  Future<void> test_convertPushToPushOrReplaceTop() async {
    final fixed = await _fixed(r'''
import 'package:kaisel/kaisel.dart';

final class ProductDetail extends KaiselRoute {
  const ProductDetail(this.id);
  final String id;

  @override
  List<Object?> get props => [id];
}

void open(KaiselRouter<KaiselRoute> router) {
  router.^push(const ProductDetail('a'));
}
''', 'Convert push() to pushOrReplaceTop()');
    expect(
      fixed,
      contains('router.pushOrReplaceTop(const ProductDetail(\'a\'));'),
    );
  }
}

@reflectiveTest
class AssistTest extends _PluginTestBase {
  /// Resolves the single assist whose message is [message], offered at the `^`
  /// cursor in [content], and returns the source with that assist applied.
  Future<String> _assisted(String content, String message) async {
    final code = await _analyze(content);
    final result = await pluginServer.handleEditGetAssists(
      protocol.EditGetAssistsParams(filePath, code.position.offset, 0),
    );
    final change = result.assists
        .firstWhere((c) => c.change.message == message)
        .change;
    return _apply(code.code, change);
  }

  Future<void> test_addPropsOverride() async {
    final assisted = await _assisted(r'''
import 'package:kaisel/kaisel.dart';

final class ^ProductDetail extends KaiselRoute {
  const ProductDetail(this.id);
  final String id;
}
''', 'Add props override');
    expect(assisted, contains('List<Object?> get props => [id];'));
  }

  Future<void> test_convertPushToRun() async {
    final assisted = await _assisted(r'''
import 'package:kaisel/kaisel.dart';

final class AddCardFlow extends KaiselRoute
    implements KaiselModalRoute<String> {
  const AddCardFlow();
}

void open(KaiselRouter<KaiselRoute> router) {
  router.^push(const AddCardFlow());
}
''', 'Convert push() to run<T>()');
    expect(assisted, contains('router.run<String>(const AddCardFlow());'));
  }

  Future<void> test_convertPushToPushOrReplaceTop() async {
    final assisted = await _assisted(r'''
import 'package:kaisel/kaisel.dart';

final class ProductDetail extends KaiselRoute {
  const ProductDetail(this.id);
  final String id;

  @override
  List<Object?> get props => [id];
}

void open(KaiselRouter<KaiselRoute> router) {
  router.^push(const ProductDetail('a'));
}
''', 'Convert push() to pushOrReplaceTop()');
    expect(
      assisted,
      contains('router.pushOrReplaceTop(const ProductDetail(\'a\'));'),
    );
  }
}
