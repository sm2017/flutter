// Copyright 2017 The Chromium Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

import 'serializable_segments.dart';

abstract class TextBlock extends SerializableSegment {
  const TextBlock();

  @override
  int get intrinsicWidth => null;
}

class Paragraph extends TextBlock {
  const Paragraph(this.body, { this.indentLevel: 0, this.bulleted: false });

  final SerializableSegment body;
  final int indentLevel;
  final bool bulleted;

  @override
  void serialize(Serializer sink, RenderingMode preferredMode) {
    String firstLineIdent, indent;
    if (bulleted) {
      if (indentLevel < 1) {
        firstLineIdent = '* ';
        indent = '  ';
      } else {
        firstLineIdent = ' ' * ((indentLevel - 1) * 2) + ' * ';
        indent = ' ' * (indentLevel * 2 + 1);
      }
    } else {
      firstLineIdent = indent = ' ' * (indentLevel * 2);
    }
    sink.emit(body, firstLinePrefix: firstLineIdent, prefix: indent);
  }
}

class BlankLine extends TextBlock {
  const BlankLine({ this.double: false });

  final bool double;

  @override
  void serialize(Serializer sink, RenderingMode preferredMode) {
    sink.ensureBlankLine();
    if (double)
      sink.emitNewline();
  }
}

abstract class PreformattedBlock extends TextBlock {
  const PreformattedBlock();

  String get format;

  SerializableSegment get body;

  @override
  void serialize(Serializer sink, RenderingMode preferredMode) {
    sink.emitString('```$format');
    sink.emitNewline();
    sink.emit(body);
    sink.emitString('```');
  }
}
