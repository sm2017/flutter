// Copyright 2017 The Chromium Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

import 'serializable_segments.dart';

abstract class TextSpan extends SerializableSegment {
  const TextSpan();
}

class Word extends TextSpan {
  const Word(this.value);

  final String value;

  @override
  int get intrinsicWidth => value.length;

  @override
  void serialize(Serializer sink, RenderingMode preferredMode) {
    sink.emitString(value);
  }
}

class HardLineBreak extends TextSpan {
  const HardLineBreak();

  @override
  int get intrinsicWidth => 0;

  @override
  void serialize(Serializer sink, RenderingMode preferredMode) {
    sink.emitNewline();
  }
}

class Interruption extends TextSpan {
  const Interruption(this.value, this.parent);
  final SerializableSegment value;
  final ForwardReference parent;

  @override
  int get intrinsicWidth => null;

  @override
  void serialize(Serializer sink, RenderingMode preferredMode) {
    sink.emitInterruption(value, parent);
  }
}

class TextSpanSequence extends SerializableSegment {
  const TextSpanSequence(this.body);

  final List<TextSpan> body;

  @override
  int get intrinsicWidth {
    return body.fold(0, (int current, TextSpan span) {
      return current + (current > 0 ? 1 : 0) + span.intrinsicWidth;
    });
  }

  @override
  void serialize(Serializer sink, RenderingMode preferredMode) {
    for (TextSpan span in body) {
      sink.ensureSpace();
      if (!sink.canFit(span))
        sink.emitNewline();
      sink.emit(span);
    }
    if (preferredMode == RenderingMode.block)
      sink.emitNewline();
  }
}
