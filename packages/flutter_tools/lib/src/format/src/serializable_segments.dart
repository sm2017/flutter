// Copyright 2017 The Chromium Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

import 'dart:collection';

import 'package:meta/meta.dart';

enum RenderingMode { automatic, block, inline, wrapped }

abstract class SerializableSegment {
  const SerializableSegment();

  /// How long the segment would take to render if rendered as one line.
  ///
  /// Returns null if this segment doesn't attempt to support one-line rendering.
  ///
  /// The `preferredMode` may have to be forced to [RenderingMode.inline] to
  /// actually get inline rendering.
  int get intrinsicWidth;

  @protected
  void serialize(Serializer sink, RenderingMode preferredMode);

  @override
  String toString() {
    return '$runtimeType: "${Serializer.serialize(this, lineLength: intrinsicWidth ?? 80)}" ($intrinsicWidth characters)';
  }
}

class ForwardReference {
  ForwardReference(this.debugLabel);

  final String debugLabel;

  SerializableSegment get target {
    assert(_target != null);
    return target;
  }

  SerializableSegment _target;

  void seal(SerializableSegment newTarget) {
    assert(newTarget != null);
    assert(_target == null);
    _target = newTarget;
  }

  @override
  String toString() => '$runtimeType#$hashCode($debugLabel)';
}

class ReturnNull { const ReturnNull(); }

@optionalTypeArgs
abstract class SerializableSegmentSequence<T extends SerializableSegment> extends SerializableSegment {
  const SerializableSegmentSequence(this.body); // : assert(body != null);

  final List<T> body;

  bool hasExactlyOneOfType(Type type) => hasExactlyOne && body.single.runtimeType == type;

  bool get hasExactlyOne => body.length == 1;

  T get single => body.single;

  bool get isEmpty => body.isEmpty;

  bool get isNotEmpty => body.isNotEmpty;
}

@optionalTypeArgs
class BlockSequence<T extends SerializableSegment> extends SerializableSegmentSequence<T> {
  const BlockSequence(List<T> body, { this.paragraphs: false }) : super(body);

  final bool paragraphs;

  @override
  int get intrinsicWidth {
    int result = 0;
    for (T block in body)
      result = addChildIntrinsic(result, block, separatorBefore: 1); // " "
    return result;
  }

  @override
  void serialize(Serializer sink, RenderingMode preferredMode) {
    bool blocky;
    switch (preferredMode) {
      case RenderingMode.automatic:
        blocky = body.length > 1;
        break;
      case RenderingMode.block:
        blocky = true;
        break;
      case RenderingMode.inline:
      case RenderingMode.wrapped:
        blocky = false;
        break;
    }
    assert(blocky != null);
    for (T block in body) {
      sink.emit(
        block,
        ensureSpaceBefore: true,
        ensureSpaceAfter: true,
        ensureBlankLineBefore: blocky && paragraphs,
        ensureBlankLineAfter: blocky && paragraphs,
        forceNewlineBefore: blocky,
        forceNewlineAfter: blocky,
        preferredMode: preferredMode,
      );
    }
  }
}

@optionalTypeArgs
class SeparatedSequence<T extends SerializableSegment> extends SerializableSegmentSequence<T> {
  const SeparatedSequence(List<T> body, this.separator) : super(body);

  final String separator;

  @override
  int get intrinsicWidth {
    int result = 0;
    for (T block in body) {
      if (result > 0)
        result += separator.length;
      addChildIntrinsic(result, block);
      if (result == null)
        return null;
    }
    return result;
  }

  @override
  void serialize(Serializer sink, RenderingMode preferredMode) {
    if (preferredMode == RenderingMode.block) {
      for (T block in body) {
        sink.emit(block, forceNewlineBefore: true);
        sink.emitString(separator);
      }
      sink.ensureLineEnded();
    } else {
      bool first = true;
      for (T block in body) {
        if (first) {
          first = false;
        } else {
          sink.emitString(separator);
        }
        sink.emit(block);
      }
    }
  }
}

class CommaSeparatedList<T extends SerializableSegment> extends SeparatedSequence<T> {
  CommaSeparatedList(List<T> body) : super(body, ', ');
}

class Nothing extends SerializableSegment {
  const Nothing();

  @override
  int get intrinsicWidth => 0;

  @override
  void serialize(Serializer sink, RenderingMode preferredMode) { }
}

class _SegmentFrame {
  _SegmentFrame(this.segment, this.prefix, this.firstLinePrefix) {
    assert(prefix != null);
    assert(firstLinePrefix != null);
  }
  final SerializableSegment segment;
  final String prefix;
  final String firstLinePrefix;
  bool _usedFirstLine = false;
  bool _lastLineWasBlank = true;
  bool _forceBlankLine = false;
  String useCurrentPrefix() {
    if (_usedFirstLine)
      return prefix;
    _usedFirstLine = true;
    return firstLinePrefix;
  }
  bool get currentPrefixIsNotEmpty => _usedFirstLine ? prefix.isNotEmpty : firstLinePrefix.isNotEmpty;
}

class Serializer {
  Serializer._(this._inlineComments);

  StringBuffer _buffer = new StringBuffer();
  StringBuffer _lineBuffer; // use _addString when adding text to the line
  bool _lastCharacterWasSpace = true;
  int _targetLineLength;
  int _currentLineLength = 0;
  Queue<_SegmentFrame> _stack;
  Set<SerializableSegment> _emittedInterruptions = new HashSet<SerializableSegment>();
  Expando<List<SerializableSegment>> _inlineComments;
  List<SerializableSegment> _pendingComments = <SerializableSegment>[];

  static String serialize(SerializableSegment root, { @required int lineLength, Expando<List<SerializableSegment>> inlineComments }) {
    final Serializer sink = new Serializer._(inlineComments);
    assert(lineLength != null);
    sink._targetLineLength = lineLength;
    sink._stack = new Queue<_SegmentFrame>();
    sink.emit(root);
    sink._flushComments();
    if (sink._lineBuffer != null)
      sink._buffer.write(sink._lineBuffer.toString().trimRight());
    return sink._buffer.toString();
  }

  void emit(SerializableSegment segment, {
    String prefix: '',
    String firstLinePrefix,
    bool flushCommentsBefore,
    bool flushCommentsAfter,
    bool forceNewlineBefore: false,
    bool forceNewlineAfter: false,
    bool ensureSpaceBefore: false,
    bool ensureSpaceAfter: false,
    bool ensureBlankLineBefore: false,
    bool ensureBlankLineAfter: false,
    String open,
    String close,
    RenderingMode preferredMode: RenderingMode.automatic,
  }) {
    if (segment == null || _emittedInterruptions.contains(segment))
      return;
    firstLinePrefix ??= prefix;
    flushCommentsBefore ??= forceNewlineBefore || ensureBlankLineBefore;
    flushCommentsAfter ??= forceNewlineAfter || ensureBlankLineAfter;
    if (flushCommentsBefore)
      _flushComments();
    if (ensureBlankLineBefore)
      ensureBlankLine();
    if (open != null)
      emitString(open);
    final bool framed = _stack.isEmpty || prefix.isNotEmpty || firstLinePrefix.isNotEmpty;
    if (framed)
      _stack.addLast(new _SegmentFrame(segment, prefix, firstLinePrefix));
    if (forceNewlineBefore)
      ensureLineEnded();
    if (ensureSpaceBefore)
      ensureSpace();
    segment.serialize(this, preferredMode);
    final List<SerializableSegment> comments = _inlineComments != null ? _inlineComments[segment] : null;
    if (comments != null) {
      assert(comments.isNotEmpty);
      _pendingComments.addAll(comments);
    }
    if (ensureSpaceAfter)
      ensureSpace();
    if (flushCommentsAfter)
      _flushComments();
    if (forceNewlineAfter)
      ensureLineEnded();
    if (framed) {
      _stack.removeLast();
      if (_stack.isNotEmpty)
        _stack.last._lastLineWasBlank = false;
    }
    if (close != null)
      emitString(close);
    if (ensureBlankLineAfter)
      ensureBlankLine();
  }

  void _flushComments() {
    // TODO(ianh): Prefer end-of-line comments, but fall back on inline comments
    // where necessary.
    final List<SerializableSegment> comments = _pendingComments;
    _pendingComments = <SerializableSegment>[];
    for (SerializableSegment comment in comments)
      emit(comment, ensureSpaceBefore: true, ensureSpaceAfter: true);
  }

  void emitInterruption(SerializableSegment segment, ForwardReference parent) {
    assert(!_emittedInterruptions.contains(segment));
    final Queue<_SegmentFrame> oldStack = _stack;
    _stack = new Queue<_SegmentFrame>();
    for (_SegmentFrame ancestor in oldStack) {
      _stack.addLast(ancestor);
      if (ancestor.segment == parent.target)
        break;
    }
    emit(segment, forceNewlineBefore: true, forceNewlineAfter: true);
    _emittedInterruptions.add(segment);
    _stack = oldStack;
  }

  /// Adds the string to the line.
  ///
  /// Returns the remaining space on the line.
  void emitString(String string, {
    bool forceNewlineBefore: false,
    bool forceNewlineAfter: false,
    bool ensureSpaceBefore: false,
    bool ensureSpaceAfter: false,
    bool ensureBlankLineBefore: false,
    bool ensureBlankLineAfter: false,
  }) {
    if (string == null || string.isEmpty)
      return;
    if (ensureBlankLineBefore)
      ensureBlankLine();
    else if (forceNewlineBefore)
      ensureLineEnded();
    _ensureLineStarted();
    if (ensureSpaceBefore)
      ensureSpace();
    _ensureLinePrefixed();
    _addString(string);
    if (string.trim().isNotEmpty)
      _stack.last._lastLineWasBlank = false;
    if (ensureSpaceAfter)
      ensureSpace();
    if (ensureBlankLineAfter)
      ensureBlankLine();
    else if (forceNewlineAfter)
      ensureLineEnded();
  }

  void _ensureLineStarted() {
    if (_lineBuffer == null || _stack.last._forceBlankLine) {
      if (_lineBuffer != null)
        _endLine();
      _lineBuffer = new StringBuffer();
      _stack.last._lastLineWasBlank = true;
      assert(_currentLineLength == 0);
      if (_stack.last._forceBlankLine) {
        _ensureLinePrefixed();
        _endLine();
        _lineBuffer = new StringBuffer();
        _stack.last._forceBlankLine = false;
      }
      _lastCharacterWasSpace = true;
      assert(_stack.last._lastLineWasBlank);
    }
  }

  void _ensureLinePrefixed() {
    if (_currentLineLength == 0) {
      for (_SegmentFrame frame in _stack) {
        if (frame.currentPrefixIsNotEmpty)
          _addString(frame.useCurrentPrefix());
      }
      assert(_stack.last._lastLineWasBlank);
    }
  }

  void _addString(String string) {
    assert(string.isNotEmpty);
    _lineBuffer.write(string);
    _currentLineLength += string.length;
    _lastCharacterWasSpace = string.runes.last == 0x20;
  }

  void _endLine() {
    assert(_lineBuffer != null);
    _buffer.writeln(_lineBuffer.toString().trimRight());
    _lineBuffer = null;
    _currentLineLength = 0;
  }

  void ensureSpace() {
    if (_lineBuffer != null && !_lastCharacterWasSpace)
      _addString(' ');
  }

  void ensureLineEnded() {
    if (_lineBuffer != null)
      _endLine();
  }

  void emitNewline() {
    _ensureLineStarted();
    _endLine();
  }

  void ensureBlankLine() {
    final bool alreadyBlank = _stack.last._lastLineWasBlank;
    if (_lineBuffer != null)
      _endLine();
    if (!alreadyBlank)
      _stack.last._forceBlankLine = true;
  }

  int get remaining => _targetLineLength - _currentLineLength;

  bool canFit(SerializableSegment segment, { int padding: 0 }) {
    assert(_targetLineLength != null);
    assert(padding != null);
    final int length = segment.intrinsicWidth;
    return length != null && length <= remaining - padding;
  }
}

int addChildIntrinsic(int total, SerializableSegment segment, { int separatorBefore: 0, int additional: 0 }) {
  if (segment == null)
    return total;
  if (total == null)
    return null;
  final int childIntrinsic = segment.intrinsicWidth;
  if (childIntrinsic == null)
    return null;
  if (total > 0)
    total += separatorBefore;
  return total + childIntrinsic + additional;
}