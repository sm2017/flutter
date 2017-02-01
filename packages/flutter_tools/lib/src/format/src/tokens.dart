// Copyright 2017 The Chromium Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

abstract class Token {
  const Token({ this.runeCount });
  final int runeCount;
  @override
  bool operator ==(dynamic other) {
    return identical(this, other);
  }
  @override
  int get hashCode => identityHashCode(this);
  bool get constant => true;
  bool get isCommentStart => false;
}

class ValueToken extends Token {
  ValueToken(this.value) : super(runeCount: value.runes.length);
  final String value;
  @override
  String toString() => value;
  @override
  bool operator ==(dynamic other) {
    return (other.runtimeType == runtimeType) && (other.value == value);
  }
  @override
  int get hashCode => runtimeType.hashCode ^ value.hashCode;
  @override
  bool get constant => false;
}

class UnknownToken extends ValueToken {
  UnknownToken(int rune) : super(new String.fromCharCode(rune));
  @override
  String toString() => '<< UNKNOWN TOKEN: "$value" ${value.runes} >>';
}

class IdentifierToken extends ValueToken {
  IdentifierToken(String value) : super(value);
  @override
  String toString() => '#${super.toString()}';
}

class CommentBodyToken extends ValueToken {
  CommentBodyToken(String value) : super(value);
  @override
  String toString() => '/*${super.toString()}*/';
}

class StringLiteralSegmentToken extends ValueToken {
  StringLiteralSegmentToken(String value) : super(value);
  @override
  String toString() => '"${super.toString()}"';
}

class WordToken extends ValueToken {
  WordToken(String value) : super(value);
}

class EOFToken extends Token {
  const EOFToken() : super(runeCount: 0);
  @override
  String toString() => '␃';
}
class EndOfStringToken extends Token {
  const EndOfStringToken() : super(runeCount: 0);
  @override
  String toString() => '<< END OF STRING >>';
}
class OpBangEquals extends Token {
  const OpBangEquals() : super(runeCount: 2);
  @override
  String toString() => '!=';
}
class OpBang extends Token {
  const OpBang() : super(runeCount: 1);
  @override
  String toString() => '!';
}
class OpQuotQuotQuot extends Token {
  const OpQuotQuotQuot() : super(runeCount: 3);
  @override
  String toString() => '"""';
}
class OpQuot extends Token {
  const OpQuot() : super(runeCount: 1);
  @override
  String toString() => '"';
}
class OpHash extends Token {
  const OpHash() : super(runeCount: 1);
  @override
  String toString() => '#';
}
class OpDollar extends Token {
  const OpDollar() : super(runeCount: 1);
  @override
  String toString() => '\$';
}
class OpInterpolatedBlock extends Token {
  const OpInterpolatedBlock() : super(runeCount: 2);
  @override
  String toString() => '\${';
}
class OpModEquals extends Token {
  const OpModEquals() : super(runeCount: 2);
  @override
  String toString() => '%=';
}
class OpMod extends Token {
  const OpMod() : super(runeCount: 1);
  @override
  String toString() => '%';
}
class OpLogicalAndEquals extends Token {
  const OpLogicalAndEquals() : super(runeCount: 3);
  @override
  String toString() => '&&=';
}
class OpLogicalAnd extends Token {
  const OpLogicalAnd() : super(runeCount: 2);
  @override
  String toString() => '&&';
}
class OpBinaryAndEquals extends Token {
  const OpBinaryAndEquals() : super(runeCount: 2);
  @override
  String toString() => '&=';
}
class OpBinaryAnd extends Token {
  const OpBinaryAnd() : super(runeCount: 1);
  @override
  String toString() => '&';
}
class OpAposAposApos extends Token {
  const OpAposAposApos() : super(runeCount: 3);
  @override
  String toString() => '\'\'\'';
}
class OpApos extends Token {
  const OpApos() : super(runeCount: 1);
  @override
  String toString() => '\'';
}
class OpOpenParen extends Token {
  const OpOpenParen() : super(runeCount: 1);
  @override
  String toString() => '(';
}
class OpCloseParen extends Token {
  const OpCloseParen() : super(runeCount: 1);
  @override
  String toString() => ')';
}
class OpTimesEquals extends Token {
  const OpTimesEquals() : super(runeCount: 2);
  @override
  String toString() => '*=';
}
class OpTimes extends Token {
  const OpTimes() : super(runeCount: 1);
  @override
  String toString() => '*';
}
class OpPlusPlus extends Token {
  const OpPlusPlus() : super(runeCount: 2);
  @override
  String toString() => '++';
}
class OpPlusEquals extends Token {
  const OpPlusEquals() : super(runeCount: 2);
  @override
  String toString() => '+=';
}
class OpPlus extends Token {
  const OpPlus() : super(runeCount: 1);
  @override
  String toString() => '+';
}
class OpComma extends Token {
  const OpComma() : super(runeCount: 1);
  @override
  String toString() => ',';
}
class OpMinusMinus extends Token {
  const OpMinusMinus() : super(runeCount: 2);
  @override
  String toString() => '--';
}
class OpMinusEquals extends Token {
  const OpMinusEquals() : super(runeCount: 2);
  @override
  String toString() => '-=';
}
class OpMinus extends Token {
  const OpMinus() : super(runeCount: 1);
  @override
  String toString() => '-';
}
class OpDotDot extends Token {
  const OpDotDot() : super(runeCount: 2);
  @override
  String toString() => '..';
}
class OpDot extends Token {
  const OpDot() : super(runeCount: 1);
  @override
  String toString() => '.';
}
class OpDartDocBlockComment extends Token {
  const OpDartDocBlockComment() : super(runeCount: 3);
  @override
  String toString() => '/**';
  @override
  bool get isCommentStart => true;
}
class OpBlockComment extends Token {
  const OpBlockComment() : super(runeCount: 2);
  @override
  String toString() => '/*';
  @override
  bool get isCommentStart => true;
}
class OpDartDocLineComment extends Token {
  const OpDartDocLineComment() : super(runeCount: 3);
  @override
  String toString() => '///';
  @override
  bool get isCommentStart => true;
}
class OpLineComment extends Token {
  const OpLineComment() : super(runeCount: 2);
  @override
  String toString() => '//';
  @override
  bool get isCommentStart => true;
}
class OpSlashEquals extends Token {
  const OpSlashEquals() : super(runeCount: 2);
  @override
  String toString() => '/=';
}
class OpSlash extends Token {
  const OpSlash() : super(runeCount: 1);
  @override
  String toString() => '/';
}
class OpColon extends Token {
  const OpColon() : super(runeCount: 1);
  @override
  String toString() => ':';
}
class OpSemicolon extends Token {
  const OpSemicolon() : super(runeCount: 1);
  @override
  String toString() => ';';
}
class OpLeftShiftEquals extends Token {
  const OpLeftShiftEquals() : super(runeCount: 3);
  @override
  String toString() => '<<=';
}
class OpLeftShift extends Token {
  const OpLeftShift() : super(runeCount: 2);
  @override
  String toString() => '<<';
}
class OpLessThanOrEquals extends Token {
  const OpLessThanOrEquals() : super(runeCount: 2);
  @override
  String toString() => '<=';
}
class OpLessThan extends Token {
  const OpLessThan() : super(runeCount: 1);
  @override
  String toString() => '<';
}
class OpEqualsEquals extends Token {
  const OpEqualsEquals() : super(runeCount: 2);
  @override
  String toString() => '==';
}
class OpArrow extends Token {
  const OpArrow() : super(runeCount: 2);
  @override
  String toString() => '=>';
}
class OpEquals extends Token {
  const OpEquals() : super(runeCount: 1);
  @override
  String toString() => '=';
}
class OpRightShiftEquals extends Token {
  const OpRightShiftEquals() : super(runeCount: 3);
  @override
  String toString() => '>>=';
}
class OpRightShift extends Token {
  const OpRightShift() : super(runeCount: 2);
  @override
  String toString() => '>>';
}
class OpGreaterThanOrEquals extends Token {
  const OpGreaterThanOrEquals() : super(runeCount: 2);
  @override
  String toString() => '>=';
}
class OpGreaterThan extends Token {
  const OpGreaterThan() : super(runeCount: 1);
  @override
  String toString() => '>';
}
class OpElvisDot extends Token {
  const OpElvisDot() : super(runeCount: 2);
  @override
  String toString() => '?.';
}
class OpElvisEquals extends Token {
  const OpElvisEquals() : super(runeCount: 3);
  @override
  String toString() => '??=';
}
class OpElvis extends Token {
  const OpElvis() : super(runeCount: 2);
  @override
  String toString() => '??';
}
class OpQuery extends Token {
  const OpQuery() : super(runeCount: 1);
  @override
  String toString() => '?';
}
class OpAt extends Token {
  const OpAt() : super(runeCount: 1);
  @override
  String toString() => '@';
}
class OpArrayEquals extends Token {
  const OpArrayEquals() : super(runeCount: 3);
  @override
  String toString() => '[]=';
}
class OpArray extends Token {
  const OpArray() : super(runeCount: 2);
  @override
  String toString() => '[]';
}
class OpOpenBracket extends Token {
  const OpOpenBracket() : super(runeCount: 1);
  @override
  String toString() => '[';
}
class OpEscapeBackspace extends Token {
  const OpEscapeBackspace() : super(runeCount: 2);
  @override
  String toString() => '\\b';
}
class OpEscapeFormFeed extends Token {
  const OpEscapeFormFeed() : super(runeCount: 2);
  @override
  String toString() => '\\f';
}
class OpEscapeNewline extends Token {
  const OpEscapeNewline() : super(runeCount: 2);
  @override
  String toString() => '\\n';
}
class OpEscapeCarriageReturn extends Token {
  const OpEscapeCarriageReturn() : super(runeCount: 2);
  @override
  String toString() => '\\r';
}
class OpEscapeTab extends Token {
  const OpEscapeTab() : super(runeCount: 2);
  @override
  String toString() => '\\t';
}
class OpEscapeUnicode extends Token {
  const OpEscapeUnicode() : super(runeCount: 2);
  @override
  String toString() => '\\u';
}
class OpEscapeVerticalTab extends Token {
  const OpEscapeVerticalTab() : super(runeCount: 2);
  @override
  String toString() => '\\v';
}
class OpEscapeByte extends Token {
  const OpEscapeByte() : super(runeCount: 2);
  @override
  String toString() => '\\x';
}
class OpCloseBracket extends Token {
  const OpCloseBracket() : super(runeCount: 1);
  @override
  String toString() => ']';
}
class OpXorEquals extends Token {
  const OpXorEquals() : super(runeCount: 2);
  @override
  String toString() => '^=';
}
class OpXor extends Token {
  const OpXor() : super(runeCount: 1);
  @override
  String toString() => '^';
}
class OpRawQuot extends Token {
  const OpRawQuot() : super(runeCount: 2);
  @override
  String toString() => 'r"';
}
class OpRawApos extends Token {
  const OpRawApos() : super(runeCount: 2);
  @override
  String toString() => 'r\'';
}
class OpOpenBrace extends Token {
  const OpOpenBrace() : super(runeCount: 1);
  @override
  String toString() => '{';
}
class OpCloseBrace extends Token {
  const OpCloseBrace() : super(runeCount: 1);
  @override
  String toString() => '}';
}
class OpBinaryOrEquals extends Token {
  const OpBinaryOrEquals() : super(runeCount: 2);
  @override
  String toString() => '|=';
}
class OpLogicalOrEquals extends Token {
  const OpLogicalOrEquals() : super(runeCount: 3);
  @override
  String toString() => '||=';
}
class OpLogicalOr extends Token {
  const OpLogicalOr() : super(runeCount: 2);
  @override
  String toString() => '||';
}
class OpBinaryOr extends Token {
  const OpBinaryOr() : super(runeCount: 1);
  @override
  String toString() => '|';
}
class OpTildeSlashEquals extends Token {
  const OpTildeSlashEquals() : super(runeCount: 3);
  @override
  String toString() => '~/=';
}
class OpTildeSlash extends Token {
  const OpTildeSlash() : super(runeCount: 2);
  @override
  String toString() => '~/';
}
class OpTilde extends Token {
  const OpTilde() : super(runeCount: 1);
  @override
  String toString() => '~';
}

class TabToken extends Token {
  const TabToken() : super(runeCount: 1);
}

class SpaceToken extends Token {
  const SpaceToken(int length) : super(runeCount: length);
  int get length => runeCount;
  @override
  bool operator ==(dynamic other) {
    return (super == other) && (other.length == length);
  }
  @override
  int get hashCode => runtimeType.hashCode ^ length;
  @override
  bool get constant => false;
  @override
  String toString() => ' ' * length;
}

class LineBreakToken extends Token {
  const LineBreakToken() : super(runeCount: 1);
  @override
  String toString() => '␊';
  @override
  bool get isCommentStart => true; // TODO(ianh): See _handleInlineComments, this is partly bogus.
}

class NumericToken<T> extends Token {
  const NumericToken(this.value) : super(runeCount: null);
  final T value;
  @override
  bool operator ==(dynamic other) {
    return (other is NumericToken) && (other.value == value);
  }
  @override
  int get hashCode => value.hashCode;
  @override
  bool get constant => false;
}

class HexNumericToken extends NumericToken<int> {
  const HexNumericToken(int value) : super(value);
  @override
  String toString() {
    String result = value.toRadixString(16);
    result = result.padLeft(((result.runes.length ~/ 2) + 1) * 2, '0');
    return '0x$result';
  }
}

class IntegerNumericToken extends NumericToken<int> {
  IntegerNumericToken(int value) : super(value);
  @override
  String toString() => value.toString();
}

class DoubleNumericToken extends NumericToken<String> {
  DoubleNumericToken(String value) : super(value);
  // Weirdly, doubles can't actually precisely represent their own literals,
  // so we just store the string.
  @override
  String toString() => value;
}
