// Copyright 2017 The Chromium Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

import 'serializable_segments.dart';
import 'text_block.dart';

class DartProgram extends SerializableSegment {
  const DartProgram(this.body, this.inlineComments);

  final BlockSequence body;

  final Expando<List<SerializableSegment>> inlineComments;

  @override
  int get intrinsicWidth => null;

  @override
  void serialize(Serializer sink, RenderingMode preferredMode) {
    sink.emit(body);
  }

  @override
  String toString({ int lineLength: 80 }) {
    return Serializer.serialize(this, lineLength: lineLength, inlineComments: inlineComments);
  }
}

class PreformattedDart extends PreformattedBlock {
  const PreformattedDart(this.program);

  final DartProgram program;

  @override
  String get format => 'dart';

  @override
  SerializableSegment get body => program;
}
