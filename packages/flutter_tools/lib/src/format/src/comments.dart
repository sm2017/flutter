// Copyright 2017 The Chromium Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

import 'serializable_segments.dart';
import 'text_span.dart';

class Comment extends SerializableSegment {
  const Comment(this.body);

  final BlockSequence body;

  @override
  int get intrinsicWidth => null;

  @override
  void serialize(Serializer sink, RenderingMode preferredMode) {
    sink.emit(body, prefix: prefix);
  }

  String get prefix => '// ';
}

class DartDoc extends Comment {
  const DartDoc(BlockSequence body) : super(body);

  @override
  String get prefix => '/// ';
}

class InlineComment extends SerializableSegment {
  const InlineComment(this.body);
  final TextSpanSequence body;

  @override
  int get intrinsicWidth {
    int result = body.intrinsicWidth;
    if (result == null)
      return null;
    result += 6; // "/* " and " */"
    return result;
  }

  @override
  void serialize(Serializer sink, RenderingMode preferredMode) {
    // sink.emit(body, preferredMode: RenderingMode.inline, open: '/*', ensureSpaceBefore: true, ensureSpaceAfter: true, close: '*/');
    sink.emit(body, prefix: '  // ', preferredMode: RenderingMode.inline, open: '//', ensureSpaceBefore: true, forceNewlineAfter: true);
  }
}