// Copyright 2017 The Chromium Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

import 'expressions.dart';
import 'serializable_segments.dart';
import 'types.dart';

class StringLiteral extends Expression {
  const StringLiteral(this.body);

  final List<StringLiteralSegment> body;

  String get value {
    final StringBuffer result = new StringBuffer();
    for (StringLiteralSegment segment in body) {
      if (segment is! StringLiteralText)
        return null;
      final StringLiteralText text = segment;
      result.write(text.value);
    }
    return result.toString();
  }

  // TODO(ianh): implement automatically serializing as multiline strings
  // or raw strings if appropriate, wrapping multiline strings, etc.

  @override
  int get intrinsicWidth {
    int result = 2; // quotes
    for (StringLiteralSegment segment in body)
      result = addChildIntrinsic(result, segment);
    return result;
  }

  @override
  void serialize(Serializer sink, RenderingMode preferredMode) {
    sink.emitString('\'');
    for (StringLiteralSegment segment in body)
      sink.emit(segment);
    sink.emitString('\'');
  }
}

abstract class StringLiteralSegment extends SerializableSegment {
  const StringLiteralSegment();
}

class StringLiteralText extends StringLiteralSegment {
  const StringLiteralText(this.value);

  final String value;

  @override
  int get intrinsicWidth {
    int result = 0;
    for (int rune in value.runes) {
      switch (rune) {
        case 0x08:
        case 0x09:
        case 0x0A:
        case 0x0B:
        case 0x0C:
        case 0x0D:
        case 0x24:
        case 0x27:
        case 0x5C:
          result += 2;
          break;
        default:
          if (rune < 0x20) {
            result += 4;
          } else {
            result += 1;
          }
      }
    }
    return result;
  }

  @override
  void serialize(Serializer sink, RenderingMode preferredMode) {
    for (int rune in value.runes) {
      switch (rune) {
        case 0x08: sink.emitString(r'\b'); break;
        case 0x09: sink.emitString(r'\t'); break;
        case 0x0A: sink.emitString(r'\n'); break;
        case 0x0B: sink.emitString(r'\v'); break;
        case 0x0C: sink.emitString(r'\f'); break;
        case 0x0D: sink.emitString(r'\r'); break;
        case 0x24: sink.emitString(r'\$'); break;
        case 0x27: sink.emitString(r"\'"); break;
        case 0x5C: sink.emitString(r'\\'); break;
        default:
          if (rune < 0x20) {
            sink.emitString('\\u${rune.toRadixString(16).padLeft(2)}');
          } else {
            // TODO(ianh): this... could be more efficient
            sink.emitString(new String.fromCharCode(rune));
          }
      }
    }
  }
}

class StringLiteralInterpolation extends StringLiteralSegment {
  const StringLiteralInterpolation(this.value);

  final Expression value;

  @override
  int get intrinsicWidth {
    if (value is Identifier) {
      int result = 1; // $
      result = addChildIntrinsic(result, value);
      return result;
    }
    int result = 5; // '${ ' ' }'
    result = addChildIntrinsic(result, value);
    return result;
  }

  @override
  void serialize(Serializer sink, RenderingMode preferredMode) {
    sink.emitString('\$');
    if (value is Identifier) {
      sink.emit(value);
    } else {
      sink.emit(value, open: '{', close: '}', ensureSpaceBefore: true, ensureSpaceAfter: true);
    }
  }
}

class ListLiteral extends Expression {
  const ListLiteral(this.isConst, this.type, this.values);
  final bool isConst;
  final TypeArguments type;
  final CommaSeparatedList<Expression> values;

  @override
  int get intrinsicWidth {
    int result = isConst ? 8 : 0; // "const []"
    result = addChildIntrinsic(result, type);
    result = addChildIntrinsic(result, values);
    return result;
  }

  @override
  void serialize(Serializer sink, RenderingMode preferredMode) {
    if (isConst)
      sink.emitString('const ');
    sink.emit(type);
    sink.emit(values, prefix: '  ', open: '[', close: ']');
  }
}

class NumericLiteral extends Expression {
  const NumericLiteral(this.value);
  final String value;

  @override
  int get intrinsicWidth => value.length;

  @override
  void serialize(Serializer sink, RenderingMode preferredMode) {
    sink.emitString('$value');
  }
}

class MapLiteral extends Expression {
  const MapLiteral(this.isConst, this.type, this.values);

  final bool isConst;
  final TypeArguments type;
  final CommaSeparatedList<MapLiteralEntry> values;

  @override
  int get intrinsicWidth {
    int result = isConst ? 8 : 0; // "const {}"
    result = addChildIntrinsic(result, type);
    result = addChildIntrinsic(result, values);
    return result;
  }

  @override
  void serialize(Serializer sink, RenderingMode preferredMode) {
    if (isConst)
      sink.emitString('const ');
    sink.emit(type);
    sink.emit(values, prefix: '  ', open: '{', close: '}');
  }
}

class MapLiteralEntry extends SerializableSegment {
  const MapLiteralEntry(this.name, this.value);

  final Expression name;

  final Expression value;

  @override
  int get intrinsicWidth {
    int result = 2; // ": "
    result = addChildIntrinsic(result, name);
    result = addChildIntrinsic(result, value);
    return result;
  }

  @override
  void serialize(Serializer sink, RenderingMode preferredMode) {
    sink.emit(name, close: ': ');
    sink.emit(value);
  }
}
