// Copyright 2017 The Chromium Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

import 'expressions.dart';
import 'functions.dart';
import 'metadata.dart';
import 'serializable_segments.dart';
import 'statements.dart';
import 'types.dart';

class ClassDefinition extends SerializableSegment {
  const ClassDefinition({
    this.metadata,
    this.isAbstract: false,
    this.identifier,
    this.typeParameters,
    this.superclass,
    this.mixins,
    this.interfaces,
    this.body,
  });
  final MetadataList metadata;
  final bool isAbstract;
  final Identifier identifier;
  final TypeParameters typeParameters;
  final TypeExpression superclass;
  final CommaSeparatedList<TypeExpression> mixins;
  final CommaSeparatedList<TypeExpression> interfaces;
  final ClassDeclarationSequence body;

  bool get hasSuperclass => superclass != null && superclass.isObject;
  bool get hasMixins => mixins != null && mixins.isNotEmpty;
  bool get hasBlock => body != null && body.isNotEmpty;

  @override
  int get intrinsicWidth {
    if (metadata != null)
      return null;
    int result = 6; // "class "
    if (isAbstract)
      result += 9; // "abstract "
    result = addChildIntrinsic(result, identifier);
    result = addChildIntrinsic(result, typeParameters);
    if (hasSuperclass || hasMixins) {
      result += 9; // " extends "
      if (hasSuperclass) {
        result = addChildIntrinsic(result, superclass);
      } else {
        result += 6; // "Object"
      }
      if (hasMixins) {
        result += 6; // " with "
        result = addChildIntrinsic(result, mixins);
      }
    }
    if (interfaces != null && interfaces.isNotEmpty) {
      result += 6; // " implements "
      result = addChildIntrinsic(result, interfaces);
    }
    result = addChildIntrinsic(result, body, additional: 5); // " { " "} "
    return result;
  }

  @override
  void serialize(Serializer sink, RenderingMode preferredMode) {
    sink.ensureBlankLine();
    sink.emit(metadata, forceNewlineBefore: true, forceNewlineAfter: true);
    if (isAbstract)
      sink.emitString('abstract ');
    sink.emitString('class ');
    sink.emit(identifier);
    sink.emit(typeParameters);
    if (hasSuperclass || hasMixins) {
      if (!hasMixins || hasBlock) {
        sink.emitString('extends', ensureSpaceBefore: true, ensureSpaceAfter: true);
      } else {
        sink.emitString('=', ensureSpaceBefore: true, ensureSpaceAfter: true);
      }
      if (hasSuperclass) {
        sink.emit(superclass);
      } else {
        sink.emitString('Object');
      }
      sink.emit(mixins, open: ' with ');
    }
    sink.emit(interfaces, open: ' implements ');
    if (!hasMixins || hasBlock) {
      sink.emit(body, prefix: '  ', open: ' {', forceNewlineBefore: true, forceNewlineAfter: true, close: '}');
    } else {
      sink.emitString(';');
    }
    sink.ensureBlankLine();
  }
}

enum _ClassDeclarationChildKind { getter, field, setter }

class _ClassDeclarationRecord {
  _ClassDeclarationRecord(this.kind, this._name);
  final _ClassDeclarationChildKind kind;
  String get name => _name.startsWith('_') ? _name.substring(1) : _name;
  final String _name;
}

class ClassDeclarationSequence extends SerializableSegmentSequence<SerializableSegment> {
  ClassDeclarationSequence(List<SerializableSegment> body) : super(body);

  @override
  int get intrinsicWidth => null;

  _ClassDeclarationRecord _identifyChild(final SerializableSegment child) {
    if (child is CommentedStatement) {
      final SerializableSegment childStatement = child.statement;
      if (childStatement is Signature) {
        if (childStatement.isGetter)
          return new _ClassDeclarationRecord(_ClassDeclarationChildKind.getter, childStatement.identifier.asSingleIdentifier.value);
        if (childStatement.isSetter)
          return new _ClassDeclarationRecord(_ClassDeclarationChildKind.setter, childStatement.identifier.asSingleIdentifier.value);
      }
    } else if (child is ExpressionStatement) {
      final Expression childExpression = child.expression;
      if (childExpression is InitializedVariableDeclaration) {
        if (childExpression.isField)
          return new _ClassDeclarationRecord(_ClassDeclarationChildKind.field, childExpression.initializers.single.identifier.value);
      }
    }
    return null;
  }

  @override
  void serialize(Serializer sink, RenderingMode preferredMode) {
    _ClassDeclarationRecord nextFriend;
    bool first = true;
    for (SerializableSegment child in body) {
      final _ClassDeclarationRecord record = _identifyChild(child);
      if (nextFriend != null && record != null && record.kind == nextFriend.kind && record.name == nextFriend.name) {
        sink.emit(child, forceNewlineBefore: true, forceNewlineAfter: true);
      } else {
        sink.emit(child, ensureBlankLineBefore: !first, forceNewlineAfter: true);
      }
      if (record != null && record.kind != _ClassDeclarationChildKind.setter) {
        nextFriend = new _ClassDeclarationRecord(
          record.kind == _ClassDeclarationChildKind.getter ? _ClassDeclarationChildKind.field : _ClassDeclarationChildKind.setter,
          record.name,
        );
      }
      first = false;
    }
  }
}
