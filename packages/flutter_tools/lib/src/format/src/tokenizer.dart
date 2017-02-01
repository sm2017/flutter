// Copyright 2017 The Chromium Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

import 'dart:collection';

import 'package:meta/meta.dart';

import 'tokens.dart';

class TokenPosition {
  const TokenPosition(this.token, this.line, this.column);
  final Token token;
  final int line;
  final int column;
  @override
  String toString() => 'line $line column $column ($token)';
}

abstract class AbstractTokenizer {
  RuneIterator _iterator;
  int _line;
  int _column;

  bool _terminated = false;

  Iterable<TokenPosition> tokenize(String buffer, { TokenPosition start }) sync* {
    assert(_iterator == null);
    assert(!_terminated);
    _iterator = buffer.runes.iterator
      ..moveNext();
    _line = start?.line ?? 1;
    _column = start?.column ?? 1;
    final Iterator<Token> tokenIterator = tokenizerLoop().iterator;
    Token token;
    while (true) {
      final int line = _line;
      final int column = _column;
      if (!tokenIterator.moveNext())
        break;
      token = tokenIterator.current;
      yield new TokenPosition(token, line, column);
    }
    assert(_iterator.current == null);
    assert(!_iterator.moveNext());
    _iterator = null;
  }

  TokenPosition terminate() {
    assert(!_terminated);
    _terminated = true;
    return wrap(const EOFToken());
  }

  TokenPosition wrap(Token token) {
    return new TokenPosition(token, _line, _column);
  }

  @protected
  void advance() {
    assert(_iterator.current != null);
    if (_iterator.current == 0x0A) {
      _line += 1;
      _column = 0;
    }
    _iterator.moveNext();
    _column += 1;
  }

  @protected
  void reverse() { // You cannot reverse over a line break.
    _column -= 1;
    _iterator.movePrevious();
    assert(_column >= 1);
  }

  @protected
  int get current => _iterator.current;

  @protected
  Iterable<Token> tokenizerLoop();
}

enum _TokenizerMode {
  code,
  blockComment,
  lineComment,
  blockStringQuot,
  lineStringQuot,
  rawStringQuot,
  blockStringApos,
  lineStringApos,
  rawStringApos,
  interpolatedIdentifier,
}

class DartCodeTokenizer extends AbstractTokenizer {
  @override
  Iterable<Token> tokenizerLoop() sync* {
    assert(_stack.isEmpty);
    _stack.addLast(_TokenizerMode.code);
    Token token;
    while (_stack.isNotEmpty) {
      switch (_stack.last) {
        case _TokenizerMode.code:
          token = _getNextCodeToken();
          break;
        case _TokenizerMode.blockComment:
          token = _getBlockCommentToken();
          assert(token is CommentBodyToken);
          break;
        case _TokenizerMode.lineComment:
          token = _getLineCommentToken();
          assert(token is CommentBodyToken);
          break;
        case _TokenizerMode.blockStringQuot:
        case _TokenizerMode.lineStringQuot:
        case _TokenizerMode.rawStringQuot:
        case _TokenizerMode.blockStringApos:
        case _TokenizerMode.lineStringApos:
        case _TokenizerMode.rawStringApos:
          token = _getNextStringToken();
          break;
        case _TokenizerMode.interpolatedIdentifier:
          token = _getInterpolatedIdentifierToken();
          assert(token is IdentifierToken);
          break;
      }
      if (token != null) {
        yield token;
      } else {
        _stack.removeLast();
      }
    }
  }

  final Queue<_TokenizerMode> _stack = new Queue<_TokenizerMode>();

  Token _getNextCodeToken() {
    loop: while (true) {
      final int rune = current;
      if (rune == null)
        return null;
      switch (rune) {
        case 0x09: // U+0009 HORIZONTAL TAB
        case 0x20: // U+0020 SPACE
          // skip
          advance();
          continue loop;
        case 0x0A: // U+000A LINE FEED
          advance();
          return const LineBreakToken();
        case 0x21: // U+0021 EXCLAMATION MARK character (!)
          advance();
          switch (current) {
            case 0x3D: // U+003D EQUALS SIGN character (=)
              advance();
              return const OpBangEquals();
          }
          return const OpBang();
        case 0x22: // U+0022 QUOTATION MARK character (")
          advance();
          switch (current) {
            case 0x22: // U+0022 QUOTATION MARK character (")
              advance();
              switch (current) {
                case 0x22: // U+0022 QUOTATION MARK character (")
                  advance();
                  _stack.addLast(_TokenizerMode.blockStringQuot);
                  return const OpQuotQuotQuot();
              }
              reverse();
          }
          _stack.addLast(_TokenizerMode.lineStringQuot);
          return const OpQuot();
        case 0x23: // U+0023 NUMBER SIGN character (#)
          advance();
          return const OpHash();
        case 0x24: // U+0024 DOLLAR SIGN character ($)
          return _tokenizeIdentifier();
        case 0x25: // U+0025 PERCENT SIGN character (%)
          advance();
          switch (current) {
            case 0x3D: // U+003D EQUALS SIGN character (=)
              advance();
              return const OpModEquals();
          }
          return const OpMod();
        case 0x26: // U+0026 AMPERSAND character (&)
          advance();
          switch (current) {
            case 0x26: // U+0026 AMPERSAND character (&)
              advance();
              switch (current) {
                case 0x3D: // U+003D EQUALS SIGN character (=)
                  advance();
                  return const OpLogicalAndEquals();
              }
              return const OpLogicalAnd();
            case 0x3D: // U+003D EQUALS SIGN character (=)
              advance();
              return const OpBinaryAndEquals();
          }
          return const OpBinaryAnd();
        case 0x27: // U+0027 APOSTROPHE character (')
          advance();
          switch (current) {
            case 0x27: // U+0027 APOSTROPHE character (')
              advance();
              switch (current) {
                case 0x27: // U+0027 APOSTROPHE character (')
                  advance();
                  _stack.addLast(_TokenizerMode.blockStringApos);
                  return const OpAposAposApos();
              }
              reverse();
          }
          _stack.addLast(_TokenizerMode.lineStringApos);
          return const OpApos();
        case 0x28: // U+0028 LEFT PARENTHESIS character (()
          advance();
          return const OpOpenParen();
        case 0x29: // U+0029 RIGHT PARENTHESIS character ())
          advance();
          return const OpCloseParen();
        case 0x2A: // U+002A ASTERISK character (*)
          advance();
          switch (current) {
            case 0x3D: // U+003D EQUALS SIGN character (=)
              advance();
              return const OpTimesEquals();
          }
          return const OpTimes();
        case 0x2B: // U+002B PLUS SIGN character (+)
          advance();
          switch (current) {
            case 0x2B: // U+002B PLUS SIGN character (+)
              advance();
              return const OpPlusPlus();
            case 0x3D: // U+003D EQUALS SIGN character (=)
              advance();
              return const OpPlusEquals();
          }
          return const OpPlus();
        case 0x2C: // U+002C COMMA character (,)
          advance();
          return const OpComma();
        case 0x2D: // U+002D HYPHEN-MINUS character (-)
          advance();
          switch (current) {
            case 0x2D: // U+002D HYPHEN-MINUS character (-)
              advance();
              return const OpMinusMinus();
            case 0x3D: // U+003D EQUALS SIGN character (=)
              advance();
              return const OpMinusEquals();
          }
          return const OpMinus();
        case 0x2E: // U+002E FULL STOP character (.)
          advance();
          switch (current) {
            case 0x30: // 0
            case 0x31: // 1
            case 0x32: // 2
            case 0x33: // 3
            case 0x34: // 4
            case 0x35: // 5
            case 0x36: // 6
            case 0x37: // 7
            case 0x38: // 8
            case 0x39: // 9
              reverse(); // get us back to the dot
              return _tokenizeDecimalNumber();
            case 0x2E: // U+002E FULL STOP character (.)
              advance();
              return const OpDotDot();
          }
          return const OpDot();
        case 0x2F: // U+002F SOLIDUS character (/)
          advance();
          switch (current) {
            case 0x2A: // U+002A ASTERISK character (*)
              advance();
              _stack.addLast(_TokenizerMode.blockComment);
              switch (current) {
                case 0x2A: // U+002A ASTERISK character (*)
                  advance();
                  return const OpDartDocBlockComment();
              }
              return const OpBlockComment();
            case 0x2F: // U+002F SOLIDUS character (/)
              advance();
              _stack.addLast(_TokenizerMode.lineComment);
              switch (current) {
                case 0x2F: // U+002F SOLIDUS character (/)
                  advance();
                  return const OpDartDocLineComment();
              }
              return const OpLineComment();
            case 0x3D: // U+003D EQUALS SIGN character (=)
              advance();
              return const OpSlashEquals();
          }
          return const OpSlash();
        case 0x3A: // U+003A COLON character (:)
          advance();
          return const OpColon();
        case 0x3B: // U+003B SEMICOLON character (;)
          advance();
          return const OpSemicolon();
        case 0x3C: // U+003C LESS-THAN SIGN character (<)
          advance();
          switch (current) {
            case 0x3C: // U+003C LESS-THAN SIGN character (<)
              advance();
              switch (current) {
                case 0x3D: // U+003D EQUALS SIGN character (=)
                  advance();
                  return const OpLeftShiftEquals();
              }
              return const OpLeftShift();
            case 0x3D: // U+003D EQUALS SIGN character (=)
              advance();
              return const OpLessThanOrEquals();
          }
          return const OpLessThan();
        case 0x3D: // U+003D EQUALS SIGN character (=)
          advance();
          switch (current) {
            case 0x3D: // U+003D EQUALS SIGN character (=)
              advance();
              return const OpEqualsEquals();
            case 0x3E: // U+003E GREATER-THAN SIGN character (>)
              advance();
              return const OpArrow();
          }
          return const OpEquals();
        case 0x3E: // U+003E GREATER-THAN SIGN character (>)
          advance();
          switch (current) {
            case 0x3E: // U+003E GREATER-THAN SIGN character (>)
              advance();
              switch (current) {
                case 0x3D: // U+003D EQUALS SIGN character (=)
                  advance();
                  return const OpRightShiftEquals();
              }
              return const OpRightShift();
            case 0x3D: // U+003E GREATER-THAN SIGN character (>)
              advance();
              return const OpGreaterThanOrEquals();
          }
          return const OpGreaterThan();
        case 0x3F: // U+003F QUESTION MARK character (?)
          advance();
          switch (current) {
            case 0x2E: // U+002E FULL STOP character (.)
              advance();
              return const OpElvisDot();
            case 0x3F: // U+003F QUESTION MARK character (?)
              advance();
              switch (current) {
                case 0x3D: // U+003D EQUALS SIGN character (=)
                  advance();
                  return const OpElvisEquals();
              }
              return const OpElvis();
          }
          return const OpQuery();
        case 0x40: // U+0040 COMMERCIAL AT character (@)
          advance();
          return const OpAt();
        case 0x5B: // U+005B LEFT SQUARE BRACKET character ([)
          advance();
          switch (current) {
            case 0x5D: // U+005D RIGHT SQUARE BRACKET character (])
              advance();
              switch (current) {
                case 0x3D: // U+003D EQUALS SIGN character (=)
                  advance();
                  return const OpArrayEquals();
              }
              return const OpArray();
          }
          return const OpOpenBracket();
        case 0x5D: // U+005D RIGHT SQUARE BRACKET character (])
          advance();
          return const OpCloseBracket();
        case 0x5E: // U+005E CIRCUMFLEX ACCENT character (^)
          advance();
          switch (current) {
            case 0x3D: // U+003D EQUALS SIGN character (=)
              advance();
              return const OpXorEquals();
          }
          return const OpXor();
        case 0x5F: // U+005F LOW LINE character (_)
          return _tokenizeIdentifier();
        case 0x72: // U+0072 LATIN SMALL LETTER R character
          advance();
          switch (current) {
            case 0x22: // U+0022 QUOTATION MARK character (")
              advance();
              _stack.addLast(_TokenizerMode.rawStringQuot);
              return const OpRawQuot();
            case 0x27: // U+0027 APOSTROPHE character (')
              advance();
              _stack.addLast(_TokenizerMode.rawStringApos);
              return const OpRawApos();
          }
          reverse();
          return _tokenizeIdentifier();
        case 0x7B: // U+007B LEFT CURLY BRACKET character ({)
          advance();
          _stack.addLast(_TokenizerMode.code);
          return const OpOpenBrace();
        case 0x7D: // U+007D RIGHT CURLY BRACKET character (})
          advance();
          if (_stack.length > 1)
            _stack.removeLast();
          return const OpCloseBrace();
        case 0x7C: // U+007C VERTICAL LINE character (|)
          advance();
          switch (current) {
            case 0x3D: // U+003D EQUALS SIGN character (=)
              advance();
              return const OpBinaryOrEquals();
            case 0x7C: // U+007C VERTICAL LINE character (|)
              advance();
              switch (current) {
                case 0x3D: // U+003D EQUALS SIGN character (=)
                  advance();
                  return const OpLogicalOrEquals();
              }
              return const OpLogicalOr();
          }
          return const OpBinaryOr();
        case 0x7E: // U+007E TILDE character (~)
          advance();
          switch (current) {
            case 0x2F: // U+002F SOLIDUS character (/)
              advance();
              switch (current) {
                case 0x3D: // U+003D EQUALS SIGN character (=)
                  advance();
                  return const OpTildeSlashEquals();
              }
              return const OpTildeSlash();
          }
          return const OpTilde();
      }
      if (rune >= 0x30 && rune <= 0x39) // 0-9
        return _tokenizeNumber();
      if ((rune >= 0x41 && rune <= 0x5A) || // A-Z
          (rune >= 0x61 && rune <= 0x7A)) // a-z
        return _tokenizeIdentifier();
      advance();
      return new UnknownToken(rune);
    }
  }

  Token _getNextStringToken() {
    bool block = false;
    bool raw = false;
    int punctuation;
    switch (_stack.last) {
      case _TokenizerMode.blockStringQuot:
        block = true;
        continue quot;
      case _TokenizerMode.rawStringQuot:
        raw = true;
        continue quot;
      quot:
      case _TokenizerMode.lineStringQuot:
        punctuation = 0x22;
        break;
      case _TokenizerMode.blockStringApos:
        block = true;
        continue apos;
      case _TokenizerMode.rawStringApos:
        raw = true;
        continue apos;
      apos:
      case _TokenizerMode.lineStringApos:
        punctuation = 0x27;
        break;
      default:
        assert(false);
    }
    assert(punctuation != null);
    int rune = current;
    if (rune == null)
      return null;
    if (rune == punctuation) {
      advance();
      if (block) {
        if (current == punctuation) {
          advance();
          if (current == punctuation) {
            advance();
            return null;
          }
          reverse();
        }
        reverse();
      } else {
        return null;
      }
    }
    if (rune == 0x24) { // U+0024 DOLLAR SIGN character ($)
      advance();
      rune = current;
      if (rune == 0x7B) { // U+007B LEFT CURLY BRACKET character ({)
        advance();
        _stack.addLast(_TokenizerMode.code);
        return const OpInterpolatedBlock();
      } else if ((rune >= 0x41 && rune <= 0x5A) || // A-Z
                 (rune >= 0x61 && rune <= 0x7A) || // a-z
                 (rune == 0x5F)) { // U+005F LOW LINE character (_)
        _stack.addLast(_TokenizerMode.interpolatedIdentifier);
        return const OpDollar();
      }
    }
    final List<int> buffer = <int>[];
    loop: do {
      if (!raw && rune == 0x5C) { // U+005C REVERSE SOLIDUS character (\)
        advance();
        if (current == null) {
          // Unexpected end of file.
          // Not really sure what to do in this case, so just leave the trailing backslash and move on.
          buffer.add(0x5C);
        } else {
          switch (current) {
            case 0x62: buffer.add(0x08); break; // \b
            case 0x66: buffer.add(0x0C); break; // \n
            case 0x6E: buffer.add(0x0A); break; // \f
            case 0x72: buffer.add(0x0D); break; // \r
            case 0x74: buffer.add(0x09); break; // \t
            case 0x76: buffer.add(0x0B); break; // \v
            default: buffer.add(current);
          }
          advance();
        }
      } else {
        buffer.add(rune);
        advance();
      }
      rune = current;
    } while (rune != null && rune != punctuation && rune != 0x24 && (block || rune != 0x0A)); // 0x24 is $, 0x0A is LF
    return new StringLiteralSegmentToken(new String.fromCharCodes(buffer));
  }

  Token _getInterpolatedIdentifierToken() {
    _stack.removeLast();
    return _tokenizeIdentifier(allowDollar: false);
  }

  IdentifierToken _tokenizeIdentifier({ bool allowDollar: true }) {
    final List<int> runes = <int>[current];
    advance();
    while (_isIdentifierCharacter(current, allowDollar: allowDollar)) {
      runes.add(current);
      advance();
    }
    return new IdentifierToken(new String.fromCharCodes(runes));
  }

  bool _isIdentifierCharacter(int code, { bool allowDollar: true }) {
    return (code >= 0x30 && code <= 0x39) // 0-9
        || (code >= 0x41 && code <= 0x5A) // A-Z
        || (code >= 0x61 && code <= 0x7A) // a-z
        || (code == 0x5F) // U+005F LOW LINE character (_)
        || (allowDollar && code == 0x24); // U+0024 DOLLAR SIGN character ($)
  }

  Token _tokenizeNumber() {
    if (current == 0x30) { // 0
      final Token token = _tokenizeHexNumber();
      if (token != null)
        return token;
    }
    return _tokenizeDecimalNumber();
  }

  Token _tokenizeHexNumber() {
    assert(current == 0x30);
    advance();
    if (current != 0x58 && current != 0x78) { // X/x
      reverse();
      return null;
    }
    advance();
    final List<int> buffer = <int>[];
    while (_isHexDigitCharacter(current)) {
      buffer.add(current);
      advance();
    }
    if (buffer.isEmpty) {
      reverse();
      reverse();
      return null;
    }
    return new HexNumericToken(int.parse(new String.fromCharCodes(buffer), radix: 16));
  }

  bool _isHexDigitCharacter(int code) {
    return (code >= 0x30 && code <= 0x39) // 0-9
        || (code >= 0x61 && code <= 0x66) // a-f
        || (code >= 0x41 && code <= 0x46); // A-F
  }

  Token _tokenizeDecimalNumber() {
    assert(_isDecimalDigitCharacter(current) ||
           current == 0x2E); // U+002E FULL STOP character (.)
    final List<int> buffer = <int>[];
    while (_isDecimalDigitCharacter(current)) {
      buffer.add(current);
      advance();
    }
    bool isDouble = false;
    if (current == 0x2E) { // U+002E FULL STOP character (.)
      advance();
      if (!_isDecimalDigitCharacter(current)) {
        reverse();
        assert(buffer.isNotEmpty);
        return new IntegerNumericToken(int.parse(new String.fromCharCodes(buffer), radix: 10));
      }
      if (buffer.isEmpty)
        buffer.add(0x30); // U+0030 DIGIT ZERO character (0)
      buffer.add(0x2E); // U+002E FULL STOP character (.)
      while (_isDecimalDigitCharacter(current)) {
        buffer.add(current);
        advance();
      }
      isDouble = true;
    }
    assert(buffer.isNotEmpty);
    if (current == 0x45 || current == 0x65) { // U+0045 LATIN CAPITAL LETTER E character, U+0065 LATIN SMALL LETTER E character
      advance();
      bool negative = false;
      int reverses = 1;
      if (current == 0x2B) { // U+002B PLUS SIGN character (+)
        advance();
        reverses += 1;
      } else if (current == 0x2D) { // U+002D HYPHEN-MINUS character (-)
        advance();
        negative = true;
        reverses += 1;
      }
      if (!_isDecimalDigitCharacter(current)) {
        for (int index = 0; index < reverses; index += 1)
          reverse();
        if (isDouble)
          return new DoubleNumericToken(new String.fromCharCodes(buffer));
        return new IntegerNumericToken(int.parse(new String.fromCharCodes(buffer), radix: 10));
      }
      buffer.add(0x45); // U+0045 LATIN CAPITAL LETTER E character
      if (negative)
        buffer.add(0x2D); // U+002D HYPHEN-MINUS character (-)
      while (_isDecimalDigitCharacter(current)) {
        buffer.add(current);
        advance();
      }
      isDouble = true;
    }
    if (isDouble)
      return new DoubleNumericToken(new String.fromCharCodes(buffer));
    return new IntegerNumericToken(int.parse(new String.fromCharCodes(buffer), radix: 10));
  }

  bool _isDecimalDigitCharacter(int code) {
    return (code >= 0x30 && code <= 0x39); // 0-9
  }

  Token _getLineCommentToken() {
    _stack.removeLast(); // always pop right away
    final List<int> runes = <int>[];
    while (current != null && current != 0x0A) {
      runes.add(current);
      advance();
    }
    if (current == 0x0A)
      advance();
    return new CommentBodyToken(new String.fromCharCodes(runes));
  }

  Token _getBlockCommentToken() {
    _stack.removeLast(); // always pop right away
    final List<int> runes = <int>[];
    while (current != null) {
      if (current == 0x2A) { // U+002A ASTERISK character (*)
        advance();
        if (current == 0x2F) { // U+002F SOLIDUS character (/)
          advance();
          return new CommentBodyToken(new String.fromCharCodes(runes));
        }
        reverse();
      }
      runes.add(current);
      advance();
    }
    return new CommentBodyToken(new String.fromCharCodes(runes));
  }
}

class CommentTokenizer extends AbstractTokenizer {
  @override
  Iterable<Token> tokenizerLoop() sync* {
    while (current != null)
      yield tokenizeOneToken();
  }

  @protected
  Token tokenizeOneToken() {
    switch (current) {
      case 0x0A: // line feed
        advance();
        return const LineBreakToken();
      case 0x20: // spaces
      case 0x09: // tabs
        int count = 0;
        do {
          if (current == 0x09) {
            count += 8;
          } else {
            count += 1;
          }
          advance();
        } while (current == 0x20 || current == 0x09);
        return new SpaceToken(count);
      default:
        final StringBuffer word = new StringBuffer();
        do {
          word.write(new String.fromCharCode(current));
          advance();
        } while (current != null && current != 0x0A && current != 0x20 && current != 0x09);
        return new WordToken(word.toString());
    }
  }
}

class DartDocTokenizer extends CommentTokenizer {
  // TODO(ianh): parse dartdocs
}
