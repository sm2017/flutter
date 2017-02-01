// Copyright 2017 The Chromium Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

import 'dart:collection';

import 'tokenizer.dart';
import 'tokens.dart';

/// Set this to true to trace the parser.
bool _debugVerbose = false;

typedef T ScopeCallback<T>();

class TokenSource {
  TokenSource(this._buffer) {
    assert(_buffer.isNotEmpty);
    _current = 0;
    _max = 0;
    _stack.add(0);
  }

  List<TokenPosition> _buffer;
  // List<String> _messages = <String>[];
  Queue<int> _stack = new Queue<int>();
  int _current;
  int _max;
  int _scope;

  Token get currentToken => _buffer[_current].token;
  TokenPosition get position => _buffer[_current];

  bool get atEnd => _current >= _buffer.length;

  void consume() {
    assert(_scope != null);
    assert(!atEnd);
    _current += 1;
    if (_current > _max)
      _max = _current;
  }

  void save() {
    assert(_scope != null);
    _stack.addLast(_current);
  }

  String _debugLastRewindMessage;

  void rewind([String message]) {
    assert(_scope != null);
    assert(_stack.length > _scope);
    assert(() {
      if (_debugVerbose && message != null)
        _debugLastRewindMessage = message;
      return true;
    });
    _current = _stack.removeLast();
  }

  void commit() {
    assert(_scope != null);
    _stack.removeLast();
  }

  void explode(Map<Token, List<Token>> mapping) {
    final TokenPosition current = position;
    if (!mapping.containsKey(current.token))
      return;
    final int line = current.line;
    int column = current.column;
    final List<TokenPosition> positions = <TokenPosition>[];
    for (Token token in mapping[currentToken]) {
      positions.add(new TokenPosition(token, line, column));
      column += token.runeCount;
    }
    assert(mapping[currentToken].fold(0, (int count, Token token) => count + token.runeCount) == current.token.runeCount);
    _buffer.replaceRange(_current, _current + 1, positions);
    if (_max > _current)
      _max += positions.length - 1;
  }

  int _debugVerboseDepth = 0;

  T scope<T>(ScopeCallback<T> callback) {
    assert(() {
      if (_debugVerbose) {
        String method = StackTrace.current.toString().split('\n')[3];
        final int cut1 = method.indexOf('.') + 1;
        final int dot = method.indexOf('.', cut1);
        final int space = method.indexOf(' ', cut1);
        int cut2;
        if (dot > 0 && dot < space)
          cut2 = dot;
        else
          cut2 = space;
        method = (' ' * _debugVerboseDepth + method.substring(cut1, cut2)).padRight(120);
        final String position = '${_buffer[_current]}'.padRight(30);
        print('$method $position');
        _debugVerboseDepth += 1;
      }
      return true;
    });
    final int oldScope = _scope;
    final int oldPosition = _stack.last;
    _scope = _stack.length;
    final T result = callback();
    assert(_stack.length == _scope, 'scope did not save and rewind/commit an equal number of times');
    assert(result != null || _stack.last == oldPosition, 'scope did not rewind but returned null');
    _scope = oldScope;
    assert(() {
      if (_debugVerbose) {
        _debugVerboseDepth -= 1;
        if (_debugLastRewindMessage != null)
          print(' ' * _debugVerboseDepth + ' <--- $_debugLastRewindMessage at $this');
        _debugLastRewindMessage = null;
      }
      return true;
    });
    return result;
  }

  @override
  String toString() {
    final String record = (_max > _current) ? ' (record was ${_buffer[_max]}))' : '';
    return '${_buffer[_current]}$record'; // \ntokens: ${_buffer.map((TokenPosition token) => token.token).join(" ")}';
  }

  // String errors() => _messages.join('\n');
}