// Copyright 2017 The Chromium Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

import 'package:meta/meta.dart';

import 'expressions.dart';
import 'literals.dart';
import 'serializable_segments.dart';
import 'types.dart';

class CommentedStatement extends SerializableSegment {
  const CommentedStatement(this.statement, this.commentary);

  final SerializableSegment statement;

  final BlockSequence<SerializableSegment> commentary;

  @override
  @mustCallSuper
  int get intrinsicWidth => null;

  @override
  @mustCallSuper
  void serialize(Serializer sink, RenderingMode preferredMode) {
    sink.emit(commentary, ensureBlankLineBefore: true, forceNewlineAfter: true);
    sink.emit(statement, forceNewlineBefore: true, forceNewlineAfter: true);
  }
}

class LabeledStatement extends SerializableSegment {
  const LabeledStatement(this.label, this.statement);

  final Label label;

  final SerializableSegment statement;

  @override
  @mustCallSuper
  int get intrinsicWidth {
    int result = 0;
    result = addChildIntrinsic(result, label, additional: 1); // " "
    result = addChildIntrinsic(result, statement);
    return result;
  }

  @override
  @mustCallSuper
  void serialize(Serializer sink, RenderingMode preferredMode) {
    sink.emit(label);
    sink.emit(statement, ensureSpaceBefore: true);
  }
}

class Label extends SerializableSegment {
  const Label(this.identifier);

  final Identifier identifier;

  @override
  @mustCallSuper
  int get intrinsicWidth {
    int result = 0;
    result = addChildIntrinsic(result, identifier, additional: 1); // ":"
    return result;
  }

  @override
  @mustCallSuper
  void serialize(Serializer sink, RenderingMode preferredMode) {
    sink.emit(identifier, close: ':');
  }
}

class ForStatement extends SerializableSegment {
  const ForStatement(this.condition, this.body, { this.hasAwait: false });
  final bool hasAwait;
  final ForCondition condition;
  final SerializableSegment body;

  @override
  int get intrinsicWidth => null;

  @override
  void serialize(Serializer sink, RenderingMode preferredMode) {
    if (hasAwait)
      sink.emitString('await ');
    sink.emitString('for');
    sink.emit(condition, ensureSpaceBefore: true);
    if (body is Block) {
      sink.emit(body, ensureSpaceBefore: true);
    } else {
      sink.emit(body, prefix: '  ', forceNewlineBefore: true, forceNewlineAfter: true);
    }
  }
}

abstract class ForCondition extends SerializableSegment {
  const ForCondition();
}

class TraditionalForCondition extends ForCondition {
  const TraditionalForCondition(this.initializer, this.condition, this.mutators);
  final SerializableSegment initializer;
  final SerializableSegment condition;
  final SerializableSegment mutators;

  @override
  int get intrinsicWidth {
    int result = 6; // "(" "; " "; " ")"
    result = addChildIntrinsic(result, initializer);
    result = addChildIntrinsic(result, condition);
    result = addChildIntrinsic(result, mutators);
    return result;
  }

  @override
  void serialize(Serializer sink, RenderingMode preferredMode) {
    sink.emitString('(');
    sink.emit(initializer);
    sink.emitString(';');
    sink.emit(condition, ensureSpaceBefore: true);
    sink.emitString(';');
    sink.emit(mutators, ensureSpaceBefore: true);
    sink.emitString(')');
  }
}

class ForInCondition extends ForCondition {
  const ForInCondition(this.item, this.iterable);
  final SerializableSegment item;
  final SerializableSegment iterable;

  @override
  int get intrinsicWidth {
    int result = 6; // "(" " in " ")"
    result = addChildIntrinsic(result, item);
    result = addChildIntrinsic(result, iterable);
    return result;
  }

  @override
  void serialize(Serializer sink, RenderingMode preferredMode) {
    sink.emitString('(');
    sink.emit(item, ensureSpaceAfter: true);
    sink.emitString('in');
    sink.emit(iterable, ensureSpaceBefore: true);
    sink.emitString(')');
  }
}

class WhileStatement extends SerializableSegment {
  const WhileStatement(this.condition, this.body);
  final Expression condition;
  final SerializableSegment body;

  @override
  int get intrinsicWidth => null;

  @override
  void serialize(Serializer sink, RenderingMode preferredMode) {
    sink.emitString('while ');
    sink.emit(condition, open: '(', close: ')');
    if (body is Block) {
      sink.emit(body, ensureSpaceBefore: true);
    } else {
      sink.emit(body, prefix: '  ', forceNewlineBefore: true, forceNewlineAfter: true);
    }
  }
}

class DoWhileStatement extends SerializableSegment {
  const DoWhileStatement(this.condition, this.body);
  final Expression condition;
  final SerializableSegment body;

  @override
  int get intrinsicWidth => null;

  @override
  void serialize(Serializer sink, RenderingMode preferredMode) {
    sink.emitString('do ');
    if (body is Block) {
      sink.emit(body, ensureSpaceBefore: true);
    } else {
      sink.emit(body, prefix: '  ', forceNewlineBefore: true, forceNewlineAfter: true);
    }
    sink.emitString('while ');
    sink.emit(condition, open: '(', close: ')');
    sink.emitString(';');
  }
}

class SwitchStatement extends SerializableSegment {
  const SwitchStatement({ this.expression, this.cases, this.defaultCase });
  final NestedExpression expression;
  final List<SwitchCase> cases;
  final DefaultCase defaultCase;

  @override
  int get intrinsicWidth => null;

  @override
  void serialize(Serializer sink, RenderingMode preferredMode) {
    sink.emitString('switch');
    sink.emit(expression, ensureSpaceBefore: true, ensureSpaceAfter: true);
    sink.emitString('{');
    sink.ensureLineEnded();
    // TODO(ianh): See if all the cases could each fit on one line, and if so, make each one inline
    // otherwise, make them blocky
    if (cases != null) {
      for (SwitchCase item in cases)
        sink.emit(item, prefix: '  ', forceNewlineBefore: true, forceNewlineAfter: true, preferredMode: RenderingMode.block);
    }
    sink.emit(defaultCase, prefix: '  ', forceNewlineBefore: true, forceNewlineAfter: true);
    sink.ensureLineEnded();
    sink.emitString('}');
  }
}

abstract class SwitchCaseBase extends SerializableSegment {
  const SwitchCaseBase(this.labels, this.statements);
  final List<Label> labels;
  final List<SerializableSegment> statements;

  @override
  int get intrinsicWidth {
    int result = 0;
    if (labels != null) {
      for (Label label in labels)
        result = addChildIntrinsic(result, label, additional: 1); // " "
    }
    if (result == null)
      return null;
    result += innerIntrinsicWidth;
    if (statements != null) {
      for (SerializableSegment statement in statements)
        result = addChildIntrinsic(result, statement, additional: 1); // " "
    }
    return result;
  }

  @protected
  int get innerIntrinsicWidth;

  @override
  void serialize(Serializer sink, RenderingMode preferredMode) {
    if (labels != null) {
      for (Label label in labels)
        sink.emit(label, ensureSpaceAfter: true);
    }
    innerSerialize(sink, preferredMode);
    if (statements != null) {
      for (SerializableSegment statement in statements)
        sink.emit(statement, prefix: '  ', ensureSpaceBefore: true, forceNewlineBefore: preferredMode == RenderingMode.block);
    }
  }

  @protected
  void innerSerialize(Serializer sink, RenderingMode preferredMode);
}

class SwitchCase extends SwitchCaseBase {
  const SwitchCase({ List<Label> labels, this.expression, List<SerializableSegment> statements }) : super(labels, statements);
  final Expression expression;

  @override
  int get innerIntrinsicWidth {
    int result = 0;
    result = addChildIntrinsic(result, expression, additional: 6); // "case " and ":"
    return result;
  }

  @override
  void innerSerialize(Serializer sink, RenderingMode preferredMode) {
    sink.emitString('case ');
    sink.emit(expression);
    sink.emitString(':');
  }
}

class DefaultCase extends SwitchCaseBase {
  const DefaultCase({ List<Label> labels, List<SerializableSegment> statements }) : super(labels, statements);

  @override
  int get innerIntrinsicWidth => 8; // "default:"

  @override
  void innerSerialize(Serializer sink, RenderingMode preferredMode) {
    sink.emitString('default:');
  }
}

class IfStatement extends SerializableSegment {
  const IfStatement(this.expression, this.body, this.elseBody);
  final NestedExpression expression;
  final SerializableSegment body;
  final SerializableSegment elseBody;

  @override
  int get intrinsicWidth => null;

  @override
  void serialize(Serializer sink, RenderingMode preferredMode) {
    sink.emitString('if');
    sink.emit(expression, ensureSpaceBefore: true);
    if (body is Block) {
      sink.emit(body, ensureSpaceBefore: true, ensureSpaceAfter: elseBody != null);
    } else {
      if (elseBody != null) {
        sink.emit(body, prefix: '  ', open: '{', ensureSpaceBefore: true, forceNewlineBefore: true, forceNewlineAfter: true, close: '}', ensureSpaceAfter: true);
      } else {
        sink.emit(body, prefix: '  ', forceNewlineBefore: true, forceNewlineAfter: true);
      }
    }
    if (elseBody != null) {
      sink.emitString('else');
      if (body is Block) {
        sink.emit(body, ensureSpaceBefore: true);
      } else {
        sink.emit(body, prefix: '  ', open: '{', ensureSpaceBefore: true, forceNewlineBefore: true, forceNewlineAfter: true, close: '}');
      }
    }
  }
}

class TryStatement extends SerializableSegment {
  const TryStatement(this.tryBlock, this.catchParts, this.finallyBlock);
  final Block tryBlock;
  final List<CatchPart> catchParts;
  final Block finallyBlock;

  @override
  int get intrinsicWidth => null;

  @override
  void serialize(Serializer sink, RenderingMode preferredMode) {
    sink.emit(tryBlock, open: 'try', ensureSpaceBefore: true);
    for (CatchPart catchPart in catchParts)
      sink.emit(catchPart);
    sink.emit(finallyBlock, open: 'finally', ensureSpaceBefore: true);
  }
}

class CatchPart extends SerializableSegment {
  const CatchPart(this.onType, this.catchIdentifiers, this.block);
  final TypeExpression onType;
  final CommaSeparatedList<Identifier> catchIdentifiers;
  final Block block;

  @override
  int get intrinsicWidth => null;

  @override
  void serialize(Serializer sink, RenderingMode preferredMode) {
    sink.emit(onType, open: 'on', ensureSpaceBefore: true, ensureSpaceAfter: true);
    sink.emit(catchIdentifiers, open: 'catch (', close: ')');
    sink.emit(block, ensureSpaceBefore: true);
  }
}

class KeywordStatement extends SerializableSegment {
  const KeywordStatement(this.keyword, this.expression);
  final Identifier keyword;
  final Expression expression;

  @override
  int get intrinsicWidth {
    int result = 0;
    result = addChildIntrinsic(result, keyword);
    result = addChildIntrinsic(result, expression, additional: 2); // " " and ";"
    return result;
  }

  @override
  void serialize(Serializer sink, RenderingMode preferredMode) {
    sink.emit(keyword);
    sink.emit(expression, ensureSpaceBefore: true); // TODO(ianh): handle indentation of subblocks properly
    sink.emitString(';');
  }
}

class ReturnStatement extends KeywordStatement {
  const ReturnStatement(Identifier keyword, Expression expression) : super(keyword, expression);
  const ReturnStatement.fromExpression(Expression expression) : super(const Identifier.noAssert('return'), expression);
}

class YieldStatement extends KeywordStatement {
  const YieldStatement(Identifier keyword, Expression expression) : super(keyword, expression);
  const YieldStatement.fromExpression(Expression expression) : super(const Identifier.noAssert('yield'), expression);
}

class YieldAllStatement extends KeywordStatement {
  const YieldAllStatement(Identifier keyword, Expression expression) : super(keyword, expression);
  const YieldAllStatement.fromExpression(Expression expression) : super(const Identifier.noAssert('yield*'), expression);
}

class BreakStatement extends KeywordStatement {
  const BreakStatement(Identifier keyword, Expression expression) : super(keyword, expression);
  const BreakStatement.fromExpression(Expression expression) : super(const Identifier.noAssert('break'), expression);
}

class ContinueStatement extends KeywordStatement {
  const ContinueStatement(Identifier keyword, Expression expression) : super(keyword, expression);
  const ContinueStatement.fromExpression(Expression expression) : super(const Identifier.noAssert('continue'), expression);
}

class Block extends SerializableSegment {
  const Block(this.body);

  final BlockSequence body;

  SerializableSegment get unwrapped {
    SerializableSegment result;
    if (body.hasExactlyOne) {
      result = body.body.single;
      if (result is Block) {
        final Block resultAsBlock = result;
        result = resultAsBlock.unwrapped;
      }
      return result;
    }
    return this;
  }

  Expression get asExpression {
    assert(body != null);
    if (body.hasExactlyOneOfType(ReturnStatement)) {
      final ReturnStatement statement = body.body.single;
      return statement.expression;
    }
    return null;
  }

  @override
  int get intrinsicWidth {
    int result = 4; // "{ " and " }"
    result = addChildIntrinsic(result, body);
    return result;
  }

  @override
  void serialize(Serializer sink, RenderingMode preferredMode) {
    assert(body != null);
    switch (preferredMode) {
      case RenderingMode.inline:
      case RenderingMode.wrapped:
        if (sink.canFit(body, padding: 4)) { // padding is '{ ' and ' }'
          sink.emit(body, prefix: '  ', open: '{', ensureSpaceBefore: true, ensureSpaceAfter: true, close: '}', preferredMode: preferredMode);
          break;
        }
        continue block;
      block:
      case RenderingMode.automatic:
        sink.emit(body, prefix: '  ', open: '{', forceNewlineBefore: body.isNotEmpty, ensureSpaceBefore: true, ensureSpaceAfter: true, forceNewlineAfter: body.isNotEmpty, close: '}', preferredMode: RenderingMode.block);
        break;
      case RenderingMode.block:
        sink.emit(body, prefix: '  ', open: '{', forceNewlineBefore: true, forceNewlineAfter: true, close: '}', preferredMode: RenderingMode.block);
        break;
    }
  }
}

class ExpressionStatement extends SerializableSegment {
  const ExpressionStatement(this.expression);

  final Expression expression;

  @override
  int get intrinsicWidth {
    int result = 1; // ";"
    result = addChildIntrinsic(result, expression);
    return result;
  }

  @override
  void serialize(Serializer sink, RenderingMode preferredMode) {
    sink.emit(expression);
    sink.emitString(';');
  }
}

enum ImportCategory { dart, package, relative }

class Import extends SerializableSegment {
  const Import(this.url, this.alias);
  final StringLiteral url;
  final Identifier alias;

  ImportCategory get category {
    if (url.value.startsWith('dart:'))
      return ImportCategory.dart;
    if (url.value.startsWith('package:'))
      return ImportCategory.package;
    return ImportCategory.relative;
  }

  @override
  int get intrinsicWidth => null;

  @override
  void serialize(Serializer sink, RenderingMode preferredMode) {
    sink.emitString('import ');
    sink.emit(url, preferredMode: RenderingMode.inline);
    if (alias != null) {
      sink.emitString('as', ensureSpaceBefore: true, ensureSpaceAfter: true);
      sink.emit(alias, preferredMode: RenderingMode.inline);
    }
    sink.emitString(';');
    sink.emitNewline();
  }
}

class UnknownStatement extends SerializableSegment {
  const UnknownStatement(this.expressions);

  final List<SerializableSegment> expressions;

  @override
  int get intrinsicWidth {
    try {
      return expressions.fold(0, (int current, SerializableSegment segment) {
        final int length = segment.intrinsicWidth;
        if (length == null)
          throw const ReturnNull();
        if (current == 0)
          return length;
        return current + 1 + length; // " "
      });
    } on ReturnNull {
      return null;
    }
  }

  @override
  void serialize(Serializer sink, RenderingMode preferredMode) {
    super.serialize(sink, preferredMode);
    for (SerializableSegment expression in expressions)
      sink.emit(expression, ensureSpaceBefore: true);
  }
}
