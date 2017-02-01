// Copyright 2017 The Chromium Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

import 'expressions.dart';
import 'serializable_segments.dart';

class Metadata extends SerializableSegment {
  const Metadata(this.name, this.arguments);

  final TriplyQualifiedIdentifier name;
  final Arguments arguments;

  @override
  int get intrinsicWidth {
    int result = 1; // "@"
    result = addChildIntrinsic(result, name);
    result = addChildIntrinsic(result, arguments);
    return result;
  }

  @override
  void serialize(Serializer sink, RenderingMode preferredMode) {
    sink.emitString('@');
    sink.emit(name);
    sink.emit(arguments);
  }
}

class MetadataList extends SerializableSegment {
  MetadataList(this.items) {
    assert(items != null);
  }

  const MetadataList.noAssert(this.items);

  final List<Metadata> items;

  @override
  int get intrinsicWidth {
    int result = 0;
    for (Metadata item in items)
      result = addChildIntrinsic(result, item, separatorBefore: 1); // " "
    return result;
  }

  @override
  void serialize(Serializer sink, RenderingMode preferredMode) {
    if (preferredMode == RenderingMode.block) {
      for (Metadata item in items)
        sink.emit(item, forceNewlineBefore: true, forceNewlineAfter: true);
    } else {
      for (Metadata item in items)
        sink.emit(item, ensureSpaceBefore: true);
    }
  }
}