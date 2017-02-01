// Copyright 2017 The Chromium Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

import 'package:meta/meta.dart';

import 'alternating_list.dart';
import 'metadata.dart';
import 'serializable_segments.dart';
import 'types.dart';

abstract class SelectorOrArgumentChainComponent extends SerializableSegment {
  const SelectorOrArgumentChainComponent();
}

abstract class Selector extends SelectorOrArgumentChainComponent {
  const Selector();
}

abstract class CascadeSelector extends SerializableSegment {
  const CascadeSelector();
}

abstract class Expression extends SerializableSegment {
  const Expression();
}

class Identifier extends Expression implements CascadeSelector {
  const Identifier(this.value);
  const Identifier.noAssert(this.value);
  final String value;

  bool get isGet => value == 'get';
  bool get isSet => value == 'set';

  @override
  int get intrinsicWidth {
    return value.length;
  }

  @override
  void serialize(Serializer sink, RenderingMode preferredMode) {
    sink.emitString(value);
  }
}

class QualifiedIdentifier extends Expression {
  const QualifiedIdentifier(this.identifier1, [ this.identifier2 ]);
  final Identifier identifier1;
  final Identifier identifier2;

  Identifier get asSingleIdentifier {
    if (identifier2 == null)
      return identifier1;
    return null;
  }

  bool get isQualified => identifier2 != null;

  bool get isFromThis => isFrom('this');

  bool isFrom(String namespace) {
    return identifier1.value == namespace && identifier2 != null;
  }

  bool get isVar => asSingleIdentifier?.value == 'var';

  @override
  int get intrinsicWidth {
    int result = 0;
    result = addChildIntrinsic(result, identifier1);
    result = addChildIntrinsic(result, identifier2, additional: 1); // "."
    return result;
  }

  @override
  void serialize(Serializer sink, RenderingMode preferredMode) {
    assert(identifier1 != null);
    sink.emit(identifier1);
    sink.emit(identifier2, open: '.');
  }
}

class TriplyQualifiedIdentifier extends Expression {
  const TriplyQualifiedIdentifier(this.identifier1, [ this.identifier2, this.identifier3 ]);
  final Identifier identifier1;
  final Identifier identifier2;
  final Identifier identifier3;

  @override
  int get intrinsicWidth {
    int result = 0;
    result = addChildIntrinsic(result, identifier1);
    result = addChildIntrinsic(result, identifier2, additional: 1); // "."
    result = addChildIntrinsic(result, identifier3, additional: 1); // "."
    return result;
  }

  @override
  void serialize(Serializer sink, RenderingMode preferredMode) {
    assert(identifier1 != null);
    sink.emit(identifier1);
    sink.emit(identifier2, open: '.');
    sink.emit(identifier3, open: '.');
  }
}

class ExpressionOperatorChain extends Expression {
  const ExpressionOperatorChain(this.leftHandSide, this.rightHandSide);

  factory ExpressionOperatorChain.pair(Expression leftHandSide, Operator op, Expression rightHandSide) {
    return new ExpressionOperatorChain(
      leftHandSide,
      new AlternatingList<Operator, Expression>.pair(op, rightHandSide)..seal(),
    );
  }

  final Expression leftHandSide;
  final AlternatingList<Operator, Expression> rightHandSide;

  ExpressionOperatorChain prepend(Expression newLeftHandSide, Operator op) {
    return new ExpressionOperatorChain(
      newLeftHandSide,
      new AlternatingList<Operator, Expression>.prepend(op, leftHandSide, to: rightHandSide)..seal(),
    );
  }

  @override
  int get intrinsicWidth {
    int result = 0;
    result = addChildIntrinsic(result, leftHandSide);
    rightHandSide.forEach((Operator op, Expression expression) {
      result = addChildIntrinsic(result, op, additional: 1); // " "
      result = addChildIntrinsic(result, expression, additional: 1); // " "
    });
    return result;
  }

  @override
  void serialize(Serializer sink, RenderingMode preferredMode) {
    sink.emit(leftHandSide);
    rightHandSide.forEach((Operator op, Expression expression) {
      sink.emit(op, ensureSpaceBefore: true);
      sink.emit(expression, ensureSpaceBefore: true);
    });
  }
}

class Operator extends SerializableSegment {
  const Operator(this.value);
  final String value;

  @override
  int get intrinsicWidth {
    return value.length;
  }

  @override
  void serialize(Serializer sink, RenderingMode preferredMode) {
    sink.emitString(value);
  }
}

class AssignableExpression extends Expression {
  const AssignableExpression(this.primary, this.chain);
  final Expression primary;
  final List<SelectorOrArgumentChainComponent> chain;

  @override
  int get intrinsicWidth {
    int result = 0;
    result = addChildIntrinsic(result, primary);
    for (SerializableSegment segment in chain)
      result = addChildIntrinsic(result, segment);
    return result;
  }

  @override
  void serialize(Serializer sink, RenderingMode preferredMode) {
    sink.emit(primary);
    for (SerializableSegment segment in chain)
      sink.emit(segment);
  }
}

class CascadedExpression extends Expression {
  const CascadedExpression(this.leftHandSide, this.cascade);
  final Expression leftHandSide;
  final List<CascadeSection> cascade;

  @override
  int get intrinsicWidth {
    if (cascade.length > 1)
      return null;
    int result = 0;
    result = addChildIntrinsic(result, leftHandSide);
    for (SerializableSegment item in cascade)
      result = addChildIntrinsic(result, item, additional: 2); // ".."
    return result;
  }

  @override
  void serialize(Serializer sink, RenderingMode preferredMode) {
    if (preferredMode == RenderingMode.inline) {
      sink.emit(leftHandSide);
      for (SerializableSegment item in cascade)
        sink.emit(item, open: '..');
    } else {
      sink.emit(leftHandSide);
      for (SerializableSegment item in cascade) {
        sink.emit(
          item,
          firstLinePrefix: '  ..',
          prefix: '    ',
          forceNewlineBefore: true,
        );
      }
    }
  }
}

class CascadeSection extends SerializableSegment {
  const CascadeSection(this.selector, this.chain1, this.chain2);
  final CascadeSelector selector;
  final List<SelectorOrArgumentChainComponent> chain1;
  final AlternatingList<Operator, Expression> chain2;

  @override
  int get intrinsicWidth {
    int result = 0;
    result = addChildIntrinsic(result, selector);
    if (chain1 != null) {
      for (SerializableSegment segment in chain1) {
        result = addChildIntrinsic(result, segment);
        if (result == null)
          return null;
      }
    }
    chain2?.forEach((SerializableSegment odd, SerializableSegment even) {
      result = addChildIntrinsic(result, odd);
      result = addChildIntrinsic(result, even);
    });
    return result;
  }

  @override
  void serialize(Serializer sink, RenderingMode preferredMode) {
    sink.emit(selector);
    if (chain1 != null) {
      for (SerializableSegment segment in chain1)
        sink.emit(segment);
    }
    chain2?.forEach((SerializableSegment odd, SerializableSegment even) {
      sink.emit(odd, ensureSpaceBefore: true, ensureSpaceAfter: true);
      sink.emit(even);
    });
  }
}

class ArraySelector extends SerializableSegment implements Selector, CascadeSelector {
  const ArraySelector(this.expression);
  final Expression expression;

  @override
  int get intrinsicWidth {
    int result = 2;
    result = addChildIntrinsic(result, expression);
    return result;
  }

  @override
  void serialize(Serializer sink, RenderingMode preferredMode) {
    sink.emitString('[');
    sink.emit(expression);
    sink.emitString(']');
  }
}

class OperatorSelector extends SerializableSegment implements Selector {
  const OperatorSelector(this.op, this.expression);
  final Operator op;
  final Expression expression;

  @override
  int get intrinsicWidth {
    int result = 0;
    result = addChildIntrinsic(result, op);
    result = addChildIntrinsic(result, expression);
    return result;
  }

  @override
  void serialize(Serializer sink, RenderingMode preferredMode) {
    sink.emit(op);
    sink.emit(expression);
  }
}

class ArgumentsSelector extends SerializableSegment implements SelectorOrArgumentChainComponent {
  ArgumentsSelector(this.typeArguments, this.arguments);

  final TypeArguments typeArguments;
  final Arguments arguments;

  @override
  int get intrinsicWidth {
    int result = 0;
    result = addChildIntrinsic(result, typeArguments);
    result = addChildIntrinsic(result, arguments);
    return result;
  }

  @override
  void serialize(Serializer sink, RenderingMode preferredMode) {
    sink.emit(typeArguments);
    sink.emit(arguments);
  }
}

class Arguments extends SeparatedSequence<Argument> {
  Arguments(List<Argument> body) : super(body, ', ');

  @override
  int get intrinsicWidth {
    int result = super.intrinsicWidth;
    if (result != null)
      result += 2;
    return result;
  }

  @override
  void serialize(Serializer sink, RenderingMode preferredMode) {
    sink.emitString('(');
    super.serialize(sink, preferredMode);
    sink.emitString(')');
  }
}

class Argument extends SerializableSegment {
  const Argument({ this.name, this.value });
  final Identifier name;
  final Expression value;

  @override
  int get intrinsicWidth {
    int result = 0;
    result = addChildIntrinsic(result, name, additional: 2); // ": "
    result = addChildIntrinsic(result, value);
    return result;
  }

  @override
  void serialize(Serializer sink, RenderingMode preferredMode) {
    if (name != null)
      sink.emitString('$name: ');
    sink.emit(value);
  }
}

class NestedExpression extends Expression {
  const NestedExpression(this.expression);
  final Expression expression;

  @override
  int get intrinsicWidth {
    int result = 2;
    result = addChildIntrinsic(result, expression);
    return result;
  }

  @override
  void serialize(Serializer sink, RenderingMode preferredMode) {
    sink.emit(expression, open: '(', close: ')');
  }
}

class Constructor extends Expression {
  const Constructor(this.keyword, this.className, this.constructorName, this.typeArguments, this.arguments);
  final Identifier keyword;
  final QualifiedIdentifier className;
  final Identifier constructorName;
  final TypeArguments typeArguments;
  final Arguments arguments;

  @override
  int get intrinsicWidth {
    int result = 0;
    result = addChildIntrinsic(result, keyword);
    result = addChildIntrinsic(result, className, separatorBefore: 1); // " "
    result = addChildIntrinsic(result, typeArguments);
    result = addChildIntrinsic(result, constructorName, separatorBefore: 1); // "."
    result = addChildIntrinsic(result, arguments);
    return result;
  }

  @override
  void serialize(Serializer sink, RenderingMode preferredMode) {
    sink.emit(keyword);
    sink.emit(className, ensureSpaceBefore: true);
    sink.emit(typeArguments);
    sink.emit(constructorName, open: '.');
    sink.emit(arguments);
  }
}

class ConditionalExpression extends Expression {
  const ConditionalExpression(this.expression, this.part1, this.part2);
  final Expression expression;
  final Expression part1;
  final Expression part2;

  @override
  int get intrinsicWidth {
    int result = 6; // " ? " " : "
    result = addChildIntrinsic(result, expression);
    result = addChildIntrinsic(result, part1);
    result = addChildIntrinsic(result, part2);
    return result;
  }

  @override
  void serialize(Serializer sink, RenderingMode preferredMode) {
    sink.emit(expression);
    sink.ensureSpace();
    sink.emitString('?');
    sink.ensureSpace();
    sink.emit(part1);
    sink.ensureSpace();
    sink.emitString(':');
    sink.ensureSpace();
    sink.emit(part2);
  }
}

class PrefixOperatorExpression extends Expression {
  const PrefixOperatorExpression(this.op, this.expression);
  final Operator op;
  final Expression expression;

  @override
  int get intrinsicWidth {
    int result = 0;
    result = addChildIntrinsic(result, op);
    result = addChildIntrinsic(result, expression);
    return result;
  }

  @override
  void serialize(Serializer sink, RenderingMode preferredMode) {
    sink.emit(op);
    sink.emit(expression);
  }
}

class PostfixOperatorExpression extends Expression {
  const PostfixOperatorExpression(this.expression, this.op);
  final Expression expression;
  final Operator op;

  @override
  int get intrinsicWidth {
    int result = 0;
    result = addChildIntrinsic(result, expression);
    result = addChildIntrinsic(result, op);
    return result;
  }

  @override
  void serialize(Serializer sink, RenderingMode preferredMode) {
    sink.emit(expression);
    sink.emit(op);
  }
}

class PrefixKeywordExpression extends Expression {
  const PrefixKeywordExpression(this.keyword, this.expression);
  final Identifier keyword;
  final Expression expression;

  @override
  int get intrinsicWidth {
    int result = 0;
    result = addChildIntrinsic(result, keyword);
    result = addChildIntrinsic(result, expression, additional: 1);
    return result;
  }

  @override
  void serialize(Serializer sink, RenderingMode preferredMode) {
    sink.emit(keyword);
    sink.emit(expression, ensureSpaceBefore: true);
  }
}

class InitializedVariableDeclaration extends Expression {
  InitializedVariableDeclaration({
    this.metadata,
    this.isStatic,
    this.isFinal,
    this.isConst,
    this.type,
    @required this.initializers,
  }) {
    assert(initializers != null);
    assert(initializers.isNotEmpty);
  }

  final MetadataList metadata;
  final bool isStatic;
  final bool isFinal;
  final bool isConst;
  final TypeExpression type;
  final CommaSeparatedList<Initializer> initializers;

  bool get isField => !isStatic && !isConst && initializers.hasExactlyOne;

  @override
  int get intrinsicWidth {
    if (metadata != null)
      return null;
    int result = 0;
    if (isStatic)
      result += 7; // "static "
    if (isFinal)
      result += 6; // "final "
    if (isConst)
      result += 6; // "const "
    result = addChildIntrinsic(result, type, additional: 1); // " "
    result = addChildIntrinsic(result, initializers);
    return result;
  }

  @override
  void serialize(Serializer sink, RenderingMode preferredMode) {
    sink.emit(metadata, forceNewlineBefore: true, forceNewlineAfter: true);
    if (isStatic)
      sink.emitString('static ');
    if (isFinal)
      sink.emitString('final ');
    if (isConst)
      sink.emitString('const ');
    sink.emit(type, ensureSpaceAfter: true);
    sink.emit(initializers);
  }
}

class Initializer extends SerializableSegment {
  const Initializer(this.identifier, [this.expression]);
  final Identifier identifier;
  final Expression expression;

  @override
  int get intrinsicWidth {
    int result = 0;
    result = addChildIntrinsic(result, identifier);
    result = addChildIntrinsic(result, expression, additional: 3); // " = "
    return result;
  }

  @override
  void serialize(Serializer sink, RenderingMode preferredMode) {
    sink.emit(identifier);
    if (expression != null) {
      sink.ensureSpace();
      sink.emitString('=');
      sink.emit(expression, ensureSpaceBefore: true);
    }
  }
}
