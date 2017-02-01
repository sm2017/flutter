// Copyright 2017 The Chromium Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

import 'package:meta/meta.dart';

import 'expressions.dart';
import 'metadata.dart';
import 'serializable_segments.dart';
import 'statements.dart';
import 'types.dart';

class FunctionDeclaration extends SerializableSegment {
  const FunctionDeclaration({
    this.isExternal: false,
    this.isStatic: false,
    this.isConst: false,
    this.signature,
    this.initializers,
    this.body,
  });

  final bool isExternal;
  final bool isStatic;
  final bool isConst;
  final Signature signature;
  final CommaSeparatedList<Expression> initializers;
  final FunctionBody body;

  @override
  int get intrinsicWidth {
    int result = 0;
    if (isExternal)
      result += 9; // "external "
    if (isStatic)
      result += 7; // "static "
    if (isConst)
      result += 6; // "const "
    result = addChildIntrinsic(result, signature);
    result = addChildIntrinsic(result, initializers, separatorBefore: 1);
    result = addChildIntrinsic(result, body, separatorBefore: 1);
    return result;
  }

  @override
  void serialize(Serializer sink, RenderingMode preferredMode) {
    if (isExternal)
      sink.emitString('external ');
    if (isStatic)
      sink.emitString('static ');
    if (isConst)
      sink.emitString('const ');
    sink.emit(signature);
    sink.emit(initializers, open: ' :', ensureSpaceBefore: true, prefix: '     ');
    if (body != null) {
      sink.emit(body, ensureSpaceBefore: body.ensureSpaceBefore);
    } else {
      sink.emitString(';');
    }
    if (preferredMode != RenderingMode.inline)
      sink.emitNewline();
  }
}

class Signature extends SerializableSegment {
  const Signature({
    this.metadata,
    this.isFinal: false,
    this.returnType,
    this.keyword,
    @required this.identifier,
    // TODO(ianh): TypeParameters
    this.parameters,
  });

  final MetadataList metadata;
  final bool isFinal; // possible when part of a parameter list
  final TypeExpression returnType;
  final Identifier keyword;
  final QualifiedIdentifier identifier; // can be "this." when used in a constructor parameter list
  // TODO(ianh): TypeParameters
  final ParameterList parameters;

  bool get isGetter => keyword.isGet;
  bool get isSetter => keyword.isSet;

  @override
  int get intrinsicWidth {
    if (metadata != null)
      return null;
    int result = isFinal ? 6 : 0; // "final "
    result = addChildIntrinsic(result, returnType, additional: 1); // space after
    result = addChildIntrinsic(result, identifier);
    result = addChildIntrinsic(result, parameters);
    return result;
  }

  @override
  void serialize(Serializer sink, RenderingMode preferredMode) {
    sink.emit(metadata, forceNewlineBefore: true, forceNewlineAfter: true);
    if (isFinal)
      sink.emitString('final ');
    sink.emit(returnType, ensureSpaceAfter: true);
    sink.emit(identifier);
    sink.emit(parameters);
  }
}

class ParameterList extends SerializableSegment {
  const ParameterList({ this.typeParameters, this.positionalParameters, this.optionalParameters, this.namedParameters });
  final TypeParameters typeParameters;
  final CommaSeparatedList<Parameter> positionalParameters;
  final CommaSeparatedList<OptionalPositionalParameter> optionalParameters;
  final CommaSeparatedList<OptionalNamedParameter> namedParameters;

  @override
  int get intrinsicWidth {
    int result = 2; // ()
    result = addChildIntrinsic(result, typeParameters);
    result = addChildIntrinsic(result, positionalParameters);
    result = addChildIntrinsic(result, optionalParameters, separatorBefore: 2, additional: 2 /* '[' + ']' */);
    result = addChildIntrinsic(result, namedParameters, separatorBefore: 2, additional: 4 /* '{ ' + ' }' */);
    return result;
  }

  @override
  void serialize(Serializer sink, RenderingMode preferredMode) {
    sink.emit(typeParameters);
    sink.emitString('(');
    sink.emit(positionalParameters);
    if (positionalParameters != null && optionalParameters != null)
      sink.emitString(', ');
    sink.emit(optionalParameters, open: '[', close: ']');
    if ((positionalParameters != null || optionalParameters != null) && namedParameters != null)
      sink.emitString(', ');
    sink.emit(namedParameters, open: '{', ensureSpaceBefore: true, ensureSpaceAfter: true, close: '}');
    sink.emitString(')');
  }
}

abstract class Parameter extends SerializableSegment {
  const Parameter();
}

class FunctionSignatureParameter extends Parameter {
  const FunctionSignatureParameter(this.signature);

  final Signature signature;

  @override
  int get intrinsicWidth => signature.intrinsicWidth;

  @override
  void serialize(Serializer sink, RenderingMode preferredMode) {
    sink.emit(signature);
  }
}

class FieldFormalParameter extends Parameter {
  const FieldFormalParameter(this.metadata, this.isFinal, this.type, this.identifier);

  final MetadataList metadata;
  final bool isFinal;
  final TypeExpression type;
  final QualifiedIdentifier identifier;

  @override
  int get intrinsicWidth {
    int result = 0;
    result = addChildIntrinsic(result, metadata, additional: 1); // trailing space
    if (isFinal)
      result += 6; // "final "
    result = addChildIntrinsic(result, type, additional: 1); // trailing space
    result = addChildIntrinsic(result, identifier);
    return result;
  }

  @override
  void serialize(Serializer sink, RenderingMode preferredMode) {
    sink.emit(metadata, ensureSpaceAfter: true);
    if (isFinal)
      sink.emitString('final ');
    sink.emit(type, ensureSpaceAfter: true);
    sink.emit(identifier);
  }
}

abstract class OptionalParameter extends SerializableSegment {
  const OptionalParameter(this.parameter, this.defaultValue);
  final Parameter parameter;
  final Expression defaultValue;

  @override
  int get intrinsicWidth {
    final int parameter = 0;
    if (parameter == null)
      return null;
    final int expression = defaultValue.intrinsicWidth;
    if (expression == null)
      return null;
    return parameter + punctuation.length + expression;
  }

  String get punctuation;

  @override
  void serialize(Serializer sink, RenderingMode preferredMode) {
    sink.emit(parameter);
    sink.emitString(punctuation);
    sink.emit(defaultValue);
  }
}

class OptionalPositionalParameter extends OptionalParameter {
  const OptionalPositionalParameter(Parameter parameter, Expression defaultValue)
    : super(parameter, defaultValue);
  @override
  String get punctuation => ' = ';
}

class OptionalNamedParameter extends OptionalParameter {
  const OptionalNamedParameter(Parameter parameter, Expression defaultValue)
    : super(parameter, defaultValue);
  @override
  String get punctuation => ': ';
}

class FieldInitializer extends SerializableSegment {
  const FieldInitializer(this.qualifiedIdentifier, this.expression);
  final QualifiedIdentifier qualifiedIdentifier;
  final Expression expression;

  @override
  int get intrinsicWidth {
    int result = 3; // " = "
    if (qualifiedIdentifier.isFromThis) {
      result = addChildIntrinsic(result, qualifiedIdentifier.identifier2);
    } else {
      result = addChildIntrinsic(result, qualifiedIdentifier);
    }
    result = addChildIntrinsic(result, expression);
    return result;
  }

  @override
  void serialize(Serializer sink, RenderingMode preferredMode) {
    if (qualifiedIdentifier.isFromThis) {
      sink.emit(qualifiedIdentifier.identifier2);
    } else {
      sink.emit(qualifiedIdentifier);
    }
    sink.emitString('=', ensureSpaceBefore: true, ensureSpaceAfter: true);
    sink.emit(expression);
  }
}

abstract class FunctionBody extends SerializableSegment {
  const FunctionBody();

  bool get ensureSpaceBefore => true;
}

class AbstractFunction extends FunctionBody {
  const AbstractFunction();

  @override
  bool get ensureSpaceBefore => false;

  @override
  int get intrinsicWidth => 1;

  @override
  void serialize(Serializer sink, RenderingMode preferredMode) {
    sink.emitString(';');
  }
}

class FunctionImplementation extends FunctionBody {
  const FunctionImplementation(this.body, {
    this.asynchronous: false,
    this.generator: false,
    @required this.isInExpression,
  });

  final Block body;
  final bool asynchronous;
  final bool generator;
  final bool isInExpression;

  @override
  int get intrinsicWidth {
    int result = 0;
    if (asynchronous) {
      result += generator ? 7 : 6; // "async* " or "async "
    } else if (generator) {
      result += 6; // "sync* "
    }
    final Expression returnExpression = body.asExpression;
    if (returnExpression != null) {
      result += 4; // "=> "
      result = addChildIntrinsic(result, returnExpression);
      if (result != null && !isInExpression)
        result += 1; // ";"
      return result;
    }
    result += 4; // "{ " and " }"
    result = addChildIntrinsic(result, body);
    return result;
  }

  @override
  void serialize(Serializer sink, RenderingMode preferredMode) {
    if (asynchronous) {
      sink.emitString(generator ? 'async* ' : 'async ');
    } else if (generator) {
      sink.emitString('sync* ');
    }
    final Expression returnExpression = body.asExpression;
    if (returnExpression != null && sink.canFit(returnExpression)) {
      sink.emitString('=> ');
      sink.emit(returnExpression, preferredMode: preferredMode);
      if (!isInExpression)
        sink.emitString(';');
    } else {
      assert(body != null);
      sink.emit(body);
    }
  }
}

class RedirectImplementation extends FunctionBody {
  const RedirectImplementation(this.target);

  final QualifiedIdentifier target;

  @override
  int get intrinsicWidth {
    int result = 0;
    result = addChildIntrinsic(result, target, additional: 2); // "= "
    return result;
  }

  @override
  void serialize(Serializer sink, RenderingMode preferredMode) {
    sink.emit(target, open: '=', ensureSpaceBefore: true);
  }
}

class FunctionExpression extends Expression {
  const FunctionExpression(this.parameters, this.body);
  final ParameterList parameters;
  final FunctionBody body;

  @override
  int get intrinsicWidth {
    int result = 0;
    result = addChildIntrinsic(result, parameters);
    result = addChildIntrinsic(result, body, additional: 1); // " "
    return result;
  }

  @override
  void serialize(Serializer sink, RenderingMode preferredMode) {
    sink.emit(parameters);
    sink.emit(body, ensureSpaceBefore: true);
  }
}

class Typedef extends SerializableSegment {
  const Typedef(this.metadata, this.signature);
  final MetadataList metadata;
  final Signature signature;

  @override
  int get intrinsicWidth {
    if (metadata != null)
      return null;
    int result = 9; // "typedef " ";"
    result = addChildIntrinsic(result, signature);
    return result;
  }

  @override
  void serialize(Serializer sink, RenderingMode preferredMode) {
    sink.emit(metadata, forceNewlineBefore: true, forceNewlineAfter: true);
    sink.emitString('typedef', ensureSpaceBefore: true, ensureSpaceAfter: true);
    sink.emit(signature);
    sink.emitString(';');
  }
}
