// Copyright 2017 The Chromium Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

import 'expressions.dart';
import 'metadata.dart';
import 'serializable_segments.dart';

class TypeExpression extends Expression {
  const TypeExpression(this.baseType, [this.typeArguments]);
  final QualifiedIdentifier baseType;
  final TypeArguments typeArguments;

  bool get isObject {
    return (baseType == null ||
            baseType.asSingleIdentifier.value == 'Object' ||
            baseType.asSingleIdentifier.value == 'dynamic') &&
           (typeArguments == null || typeArguments.isEmpty);
  }

  bool get isVar => baseType.isVar && (typeArguments == null || typeArguments.isEmpty);

  @override
  int get intrinsicWidth {
    int result = 0;
    result = addChildIntrinsic(result, baseType);
    result = addChildIntrinsic(result, typeArguments);
    return result;
  }

  @override
  void serialize(Serializer sink, RenderingMode preferredMode) {
    sink.emit(baseType);
    sink.emit(typeArguments);
  }
}

class TypeArguments extends SerializableSegment {
  const TypeArguments(this.arguments);
  final List<TypeExpression> arguments;

  bool get isEmpty => arguments == null || arguments.isEmpty;

  bool get isNotEmpty => arguments != null && arguments.isNotEmpty;

  @override
  int get intrinsicWidth {
    if (isEmpty)
      return 0;
    return arguments.fold<int>(0, (int previous, SerializableSegment segment) {
      return addChildIntrinsic(previous, segment, additional: 2); // "<>" for the first one, ", " for the others
    });
  }

  @override
  void serialize(Serializer sink, RenderingMode preferredMode) {
    if (isEmpty)
      return;
    sink.emitString('<');
    bool isFirst = true;
    final bool blockMode = preferredMode == RenderingMode.block;
    for (TypeExpression argument in arguments) {
      if (!isFirst) {
        sink.emitString(', ');
      } else {
        isFirst = false;
      }
      sink.emit(argument, prefix: blockMode ? '  ' : '', forceNewlineBefore: blockMode);
    }
    if (blockMode) {
      sink.emitString(',');
      sink.emitNewline();
    }
    sink.emitString('>');
  }
}

class TypeParameters extends SerializableSegment {
  const TypeParameters(this.parameters);
  final List<TypeParameter> parameters;

  @override
  int get intrinsicWidth {
    if (parameters == null || parameters.isEmpty)
      return 0;
    return parameters.fold<int>(0, (int previous, SerializableSegment segment) {
      return addChildIntrinsic(previous, segment, additional: 2); // "<>" for the first one, ", " for the others
    });
  }

  @override
  void serialize(Serializer sink, RenderingMode preferredMode) {
    if (parameters == null || parameters.isEmpty)
      return;
    sink.emitString('<');
    bool isFirst = true;
    final bool blockMode = preferredMode == RenderingMode.block;
    for (TypeParameter argument in parameters) {
      if (!isFirst) {
        sink.emitString(', ');
      } else {
        isFirst = false;
      }
      sink.emit(argument, prefix: '  ', forceNewlineBefore: blockMode);
    }
    if (blockMode) {
      sink.emitString(',');
      sink.emitNewline();
    }
    sink.emitString('>');
  }
}

class TypeParameter extends SerializableSegment {
  const TypeParameter(this.metadata, this.baseType, this.upperBound);
  final MetadataList metadata;
  final Identifier baseType;
  final TypeExpression upperBound;

  @override
  int get intrinsicWidth {
    int result = 0;
    result = addChildIntrinsic(result, metadata, additional: 1); // " "
    result = addChildIntrinsic(result, baseType);
    result = addChildIntrinsic(result, upperBound, additional: 9); // " extends "
    return result;
  }

  @override
  void serialize(Serializer sink, RenderingMode preferredMode) {
    sink.emit(metadata, ensureSpaceAfter: true);
    sink.emit(baseType);
    sink.emit(upperBound, open: ' extends ');
  }
}
