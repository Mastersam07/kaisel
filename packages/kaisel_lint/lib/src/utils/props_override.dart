import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/source/source_range.dart';
import 'package:analyzer_plugin/utilities/change_builder/change_builder_core.dart';

/// Adds `@override List<Object?> get props => [...]` naming [fieldNames] to
/// [classDecl].
///
/// A class declared with a primary constructor can end in `;` with no body
/// (`final class const Detail(final String id) extends KaiselRoute;`), so that
/// `;` is replaced by a body holding the getter.
void addPropsOverride(
  FileEditBuilder builder,
  ClassDeclaration classDecl,
  List<String> fieldNames,
) {
  final getter =
      '  @override\n'
      '  List<Object?> get props => [${fieldNames.join(', ')}];\n';
  final end = classDecl.endToken;
  if (end.lexeme == ';') {
    builder.addSimpleReplacement(
      SourceRange(end.offset, end.length),
      ' {\n$getter}',
    );
  } else {
    builder.addSimpleInsertion(classDecl.end - 1, '\n$getter');
  }
}
