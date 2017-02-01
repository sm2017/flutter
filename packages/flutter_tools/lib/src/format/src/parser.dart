// Copyright 2017 The Chromium Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

import 'dart:collection';

import 'package:meta/meta.dart';

import 'alternating_list.dart';
import 'classes.dart';
import 'comments.dart';
import 'expressions.dart';
import 'functions.dart';
import 'literals.dart';
import 'metadata.dart';
import 'program.dart';
import 'serializable_segments.dart';
import 'statements.dart';
import 'text_block.dart';
import 'text_span.dart';
import 'token_source.dart';
import 'tokenizer.dart';
import 'tokens.dart';
import 'types.dart';

// To enable a trace mode that helps debugging substantially, see _debugVerbose
// in token_source.dart.

typedef T ParserFunction<T>(TokenSource input);

class _ParameterDefaultPair {
  _ParameterDefaultPair(this.parameter, this.defaultValue);
  final Parameter parameter;
  final Expression defaultValue;
  @override
  String toString() => '<$parameter, $defaultValue>';
}

class InlineCommentStackEntry {
  InlineCommentStackEntry(this.parent, this.segment, this.depth);
  Object parent;
  final SerializableSegment segment;
  int depth;
  @override
  String toString() => '<$parent::$segment @ $depth>';
}

class InlineCommentStackTokenSource extends TokenSource {
  InlineCommentStackTokenSource(
    List<TokenPosition> buffer,
    this._output,
  ) : super(buffer) {
    _parents.add(null);
  }

  final Queue<Object> _parents = new Queue<Object>();
  final Expando<List<SerializableSegment>> _output;
  final List<InlineCommentStackEntry> _comments = <InlineCommentStackEntry>[];
  int _depth = 0;

  @override
  void save() {
    _depth += 1;
    _parents.add(_parents.last);
    super.save();
  }

  @override
  void rewind([String message]) {
    while (_comments.isNotEmpty && _comments.last.depth >= _depth)
      _comments.removeLast();
    _depth -= 1;
    assert(_depth > 0 || _comments.isEmpty);
    _parents.removeLast();
    super.rewind(message);
  }

  @override
  void commit() {
    _depth -= 1;
    if (_depth == 0) {
      for (InlineCommentStackEntry entry in _comments) {
        _output[entry.parent] ??= <SerializableSegment>[];
        _output[entry.parent].add(entry.segment);
      }
      _comments.clear();
    } else {
      for (InlineCommentStackEntry entry in _comments.reversed) {
        if (entry.depth <= _depth)
          break;
        entry.depth = _depth;
      }
    }
    assert(_depth > 0 || _comments.isEmpty);
    final Object parent = _parents.last;
    _parents
      ..removeLast()
      ..removeLast()
      ..add(parent);
    super.commit();
  }

  void replaceCommentParent(Object newParent) {
    final Object oldParent = _parents.removeLast();
    for (InlineCommentStackEntry entry in _comments) {
      if (entry.parent == oldParent)
        entry.parent = newParent;
    }
    _parents.add(newParent);
    _output[oldParent] = _output[newParent];
  }

  void setCommentParent(Object newParent) {
    assert(newParent is! ForwardReference || _parents.last is! ForwardReference);
    if (_parents.last is ForwardReference) {
      assert(newParent != null);
      final ForwardReference oldParent = _parents.last;
      oldParent.seal(newParent);
      replaceCommentParent(newParent);
    } else {
      _parents.removeLast();
      _parents.add(newParent);
    }
  }

  void setCommentParentIfClear(Object newParent) {
    if (_parents.last == null)
      setCommentParent(newParent);
  }

  void addComment(SerializableSegment segment) {
    final Object parent = _parents.last;
    assert(parent != null);
    if (_depth > 0) {
      _comments.add(new InlineCommentStackEntry(parent, segment, _depth));
    } else {
      _output[parent] ??= <SerializableSegment>[];
      _output[parent].add(segment);
    }
  }
}

class ProgramParseContext {
  final DartCodeTokenizer _tokenizer = new DartCodeTokenizer();

  Expando<List<SerializableSegment>> _inlineComments = new Expando<List<SerializableSegment>>();

  DartProgram parseDartProgram(String buffer) {
    final List<TokenPosition> tokens = _tokenizer.tokenize(buffer).toList();
    tokens.add(_tokenizer.terminate());
    final InlineCommentStackTokenSource input = new InlineCommentStackTokenSource(tokens, _inlineComments);
    final ForwardReference link = new ForwardReference('parseDartProgram');
    BlockSequence body;
    try {
      body = new BlockSequence(_parseBlockBody(input, link, topLevel: true));
    } catch (error, stack) {
      throw new Exception('failed to parse beyond $input:\nERROR: $error\n$stack'); // \n${input.errors()}
    }
    if (input.currentToken is! EOFToken)
      throw new Exception('failed to parse beyond $input'); // \n${input.errors()}
    link.seal(body);
    return new DartProgram(body, _inlineComments);
  }

  List<SerializableSegment> _parseBlockBody(InlineCommentStackTokenSource input, ForwardReference link, { bool topLevel: false, String className }) {
    assert(!topLevel || className == null);
    return input.scope<List<SerializableSegment>>(() {
      final List<SerializableSegment> body = <SerializableSegment>[];
      bool includeBlankLine = false;
      loop: while (input.currentToken is! EOFToken) {
        int blankLines = 0;
        while (input.currentToken is LineBreakToken) {
          input.consume();
          blankLines += 1;
          if (topLevel) {
            includeBlankLine = includeBlankLine || blankLines < 3;
          } else if (className != null) {
            includeBlankLine = includeBlankLine || blankLines == 2;
          } else {
            includeBlankLine = includeBlankLine || blankLines == 1;
          }
        }
        if (includeBlankLine) {
          body.add(new BlankLine(double: blankLines >= 2));
          includeBlankLine = false;
        }
        final List<SerializableSegment> commentary = _parseCommentary(input, link);
        assert(input.currentToken is! OpDartDocBlockComment);
        assert(input.currentToken is! OpBlockComment);
        assert(input.currentToken is! OpDartDocLineComment);
        assert(input.currentToken is! OpLineComment);
        assert(input.currentToken is! CommentBodyToken);
        input.setCommentParent(null);
        if (input.currentToken is LineBreakToken) {
          assert(commentary != null);
          body.add(new BlockSequence<SerializableSegment>(commentary));
          includeBlankLine = true;
        } else {
          SerializableSegment statement;
          if (topLevel) {
            statement = _parseTopLevel(input);
          } else if (className != null) {
            statement = _parseClassMemberDefinition(input, className);
          } else {
            statement = _parseStatement(input);
          }
          if (statement == null) {
            if (commentary != null)
              body.addAll(commentary);
            if (input.currentToken is! EOFToken)
              break;
          } else {
            if (commentary != null) {
              if (commentary.isNotEmpty)
                statement = new CommentedStatement(statement, new BlockSequence<SerializableSegment>(commentary));
            }
            body.add(statement);
            input.setCommentParentIfClear(body.last);
            _handleInlineComments(input);
          }
        }
      }
      if (body.isNotEmpty) {
        while (body.first is BlankLine)
          body.removeAt(0);
        while (body.last is BlankLine)
          body.removeLast();
      }
      return _normalizeImports(body);
    });
  }

  DartDocParseContext _currentDartDoc;
  CommentParseContext _currentComment;
  List<SerializableSegment> _pendingCommentary;

  List<SerializableSegment> _parseCommentary(InlineCommentStackTokenSource input, ForwardReference link) {
    assert(_currentDartDoc == null);
    assert(_currentComment == null);
    assert(_pendingCommentary == null);
    return input.scope<List<SerializableSegment>>(() {
      while (true) {
        input.save();
        // if (input.currentToken is LineBreakToken) {
        //   input.consume();
        //   if (_currentDartDoc != null) {
        //     _currentDartDoc.addInterruption(const BlankLine());
        //   } else {
        //     _openCommentary();
        //     if (_currentComment != null) {
        //       _pendingCommentary.addAll(_currentComment.close(link));
        //       assert(_pendingCommentary.isNotEmpty);
        //       _currentComment = null;
        //     }
        //     _pendingCommentary.add(const BlankLine());
        //   }
        //   input.commit();
        // } else {
          if (_parseBigComment(input, link)) {
            input.commit();
          } else {
            input.rewind();
            break;
          }
        // }
      }
      if (_currentDartDoc != null) {
        _pendingCommentary.addAll(_currentDartDoc.close(link));
        assert(_pendingCommentary.isNotEmpty);
        _currentDartDoc = null;
      }
      if (_currentComment != null) {
        _pendingCommentary.addAll(_currentComment.close(link));
        assert(_pendingCommentary.isNotEmpty);
        _currentComment = null;
      }
      if (_pendingCommentary == null)
        return null;
      assert(_pendingCommentary != null);
      assert(_pendingCommentary.isNotEmpty);
      final List<SerializableSegment> result = _pendingCommentary;
      _pendingCommentary = null;
      return result;
    });
  }

  bool _parseBigComment(InlineCommentStackTokenSource input, ForwardReference link) {
    return input.scope<bool>(() {
      switch ((input.currentToken).runtimeType) {
        case OpDartDocLineComment:
          input.consume();
          _openCommentary();
          if (_currentComment != null)
            _closeComment(input, link);
          _currentDartDoc ??= new DartDocParseContext();
          if (input.currentToken is CommentBodyToken) {
            final CommentBodyToken token = input.currentToken;
            _currentDartDoc.addBuffer(token.value, input.position);
            input.consume();
          }
          _currentDartDoc.endLine();
          input.setCommentParent(null);
          return true;
        case OpLineComment:
          input.consume();
          _openCommentary();
          _currentComment ??= new BlockCommentParseContext();
          if (input.currentToken is CommentBodyToken) {
            final CommentBodyToken token = input.currentToken;
            _currentComment.addBuffer(token.value, input.position);
            input.consume();
          }
          _currentComment.endLine();
          input.setCommentParent(null);
          return true;
        case OpDartDocBlockComment:
          input.consume();
          _openCommentary();
          if (_currentComment != null)
            _closeComment(input, link);
          _currentDartDoc ??= new DartDocParseContext();
          if (input.currentToken is CommentBodyToken) {
            final CommentBodyToken token = input.currentToken;
            _currentDartDoc.addBuffer(token.value, input.position);
            input.consume();
          }
          _currentDartDoc.endLine();
          input.setCommentParent(null);
          return true;
        case OpBlockComment:
          input.consume();
          if (_currentComment != null)
            _closeComment(input, link);
          _openCommentary();
          assert(_currentComment == null);
          _currentComment = new BlockCommentParseContext();
          if (input.currentToken is CommentBodyToken) {
            final CommentBodyToken token = input.currentToken;
            _currentComment.addBuffer(token.value, input.position);
            input.consume();
          }
          _closeComment(input, link);
          return true;
        default:
          return false;
      }
    });
  }

  void _openCommentary() {
    _pendingCommentary ??= <SerializableSegment>[];
  }

  void _closeComment(InlineCommentStackTokenSource input, ForwardReference link) {
    assert(_currentComment != null);
    assert(_pendingCommentary != null);
    final List<SerializableSegment> comment = _currentComment.close(link);
    assert(comment.isNotEmpty);
    _currentComment = null;
    if (_currentDartDoc != null) {
      for (SerializableSegment segment in comment)
        _currentDartDoc.addInterruption(segment);
    } else {
      _pendingCommentary.addAll(comment);
      input.setCommentParent(comment.last);
    }
  }

  Import _unwrapImport(SerializableSegment segment) {
    if (segment is Import)
      return segment;
    if (segment is CommentedStatement && segment.statement is Import)
      return segment.statement;
    return null;
  }

  List<SerializableSegment> _normalizeImports(List<SerializableSegment> raw) {
    final List<SerializableSegment> result = <SerializableSegment>[];
    final List<SerializableSegment> imports = <SerializableSegment>[];
    for (SerializableSegment import in raw.where((SerializableSegment segment) => _unwrapImport(segment) != null))
      imports.add(import);
    imports.sort((SerializableSegment a, SerializableSegment b) => _unwrapImport(a).url.value.compareTo(_unwrapImport(b).url.value));
    final List<SerializableSegment> dartImports = imports.where((SerializableSegment import) => _unwrapImport(import).category == ImportCategory.dart).toList();
    final List<SerializableSegment> packageImports = imports.where((SerializableSegment import) => _unwrapImport(import).category == ImportCategory.package).toList();
    final List<SerializableSegment> relativeImports = imports.where((SerializableSegment import) => _unwrapImport(import).category == ImportCategory.relative).toList();
    bool beforeImports = true;
    bool afterImports = false;
    for (SerializableSegment segment in raw) {
      if (beforeImports) {
        if (_unwrapImport(segment) is Import) {
          beforeImports = false;
          if (dartImports.isNotEmpty) {
            result.addAll(dartImports);
            if (packageImports.isNotEmpty || relativeImports.isNotEmpty)
              result.add(const BlankLine());
          }
          if (packageImports.isNotEmpty) {
            result.addAll(packageImports);
            if (relativeImports.isNotEmpty)
              result.add(const BlankLine());
          }
          if (relativeImports.isNotEmpty)
            result.addAll(relativeImports);
          result.add(const BlankLine());
          afterImports = true;
        } else {
          result.add(segment);
        }
      } else {
        if (afterImports && segment is! BlankLine && segment is! Import)
          afterImports = false;
        if (!afterImports && segment is! Import)
          result.add(segment);
      }
    }
    return result;
  }


  // Conventions for functions below:
  // They each take a InlineCommentStackTokenSource called input.
  // They are all async.
  // _parseFoo functions return successfully or return null.
  // _subparseFoo functions return successfully or throw a string indicating a parse error
  // _getStatement functions return successfully
  // _consumeFoo functions return true if Foo was consumed, false otherwise

  SerializableSegment _parseTopLevel(InlineCommentStackTokenSource input) {
    return input.scope<SerializableSegment>(() {
      final SerializableSegment statement = _parseUnlabeledStatement(input);
      if (statement != null)
        input.setCommentParentIfClear(statement);
      return statement;
    });
  }

  SerializableSegment _parseClassMemberDefinition(InlineCommentStackTokenSource input, String className) {
    return input.scope<SerializableSegment>(() {
      final SerializableSegment statement = _parseUnlabeledStatement(input, className: className);
      if (statement != null)
        input.setCommentParentIfClear(statement);
      return statement;
    });
  }

  SerializableSegment _parseStatement(InlineCommentStackTokenSource input) {
    return input.scope<SerializableSegment>(() {
      final SerializableSegment statement = _parseLabeledStatement(input) ??
                                            _parseUnlabeledStatement(input);
      if (statement != null)
        input.setCommentParentIfClear(statement);
      return statement;
    });
  }

  SerializableSegment _parseLabeledStatement(InlineCommentStackTokenSource input) {
    return input.scope<SerializableSegment>(() {
      input.save();
      final Label label = _parseLabel(input);
      if (label == null) {
        input.rewind();
        return null;
      }
      final SerializableSegment statement = _parseStatement(input);
      if (statement == null) {
        input.rewind();
        return null;
      }
      input.commit();
      return new LabeledStatement(label, statement);
    });
  }

  SerializableSegment _parseUnlabeledStatement(InlineCommentStackTokenSource input, { String className }) {
    return input.scope<SerializableSegment>(() {
      // To make the formatter more flexible in the face of dubious input, we treat many
      // top-level and class-level definitions and statements as interchangeable.
      return // Library definition:
             // - script tag // TODO(ianh): Implement.
             // - library name // TODO(ianh): Implement.
             _parseImport(input) ??
             // - exports // TODO(ianh): Implement.
             // - part directives // TODO(ianh): Implement.
             // Top-level definitions:
             _parseClassDefinition(input) ??
             // - enum // TODO(ianh): Implement.
             _parseTypedef(input) ??
             // Class member definitions:
             // - fields are handled by _parseLocalVariableDeclaration below
             // - constructors, operators, getters, and setters are handled by _parseFunctionDeclaration below
             // Statements:
             _parseBlockStatement(input) ??
             _parseForStatement(input) ??
             _parseWhileStatement(input) ??
             _parseDoWhileStatement(input) ??
             _parseSwitchStatement(input) ??
             _parseIfStatement(input) ??
             _parseTryStatement(input) ??
             _parseFlowControlStatements(input) ?? // return, yield, yield*, break, continue
             _parseFunctionDeclaration(input, className: className) ?? // also handles methods, constructors, operators, etc
             _parseExpressionStatement(input) ?? // "assert" and "rethrow" look like expression statements, so are handled here
             _parseLocalVariableDeclaration(input); // also handles fields in classes - this is last so it doesn't get confused with "return;" being a variable declaration
    });
  }

  Import _parseImport(InlineCommentStackTokenSource input) {
    return input.scope<Import>(() {
      input.save();
      input.setCommentParent(new ForwardReference('_parseImport'));
      if (!_consumeSpecificIdentifier(input, 'import')) {
        input.rewind();
        return null;
      }
      final StringLiteral url = _parseStringLiteral(input);
      if (url == null) {
        input.rewind('expected string literal in import statement');
        return null;
      }
      input.setCommentParent(url);
      Identifier identifier = _parseIdentifier(input);
      Identifier alias;
      if (identifier?.value == 'as') {
        identifier = _parseIdentifier(input);
        if (identifier == null) {
          input.rewind('expected identifier after "as" in import statement');
          return null;
        }
        alias = identifier;
        identifier = _parseIdentifier(input);
      }
      if (identifier != null) {
        input.rewind('unexpected identifier "$identifier" in import statement');
        return null;
      }
      if (!_consumeSpecificOperator(input, OpSemicolon)) {
        input.rewind('expected semicolon after import');
        return null;
      }
      input.commit();
      return new Import(url, alias);
    });
  }

  ClassDefinition _parseClassDefinition(InlineCommentStackTokenSource input) {
    return input.scope<ClassDefinition>(() {
      input.save();
      final MetadataList metadata = _parseMetadata(input);
      final bool isAbstract = _consumeSpecificIdentifier(input, 'abstract');
      if (!_consumeSpecificIdentifier(input, 'class')) {
        input.rewind();
        return null;
      }
      final Identifier identifier = _parseIdentifier(input);
      if (identifier == null) {
        input.rewind('expected identifier after "class" keyword');
        return null;
      }
      final TypeParameters typeParameters = _parseTypeParameters(input);
      TypeExpression superclass;
      if (_consumeSpecificIdentifier(input, 'extends') ||
          _consumeSpecificOperator(input, OpEquals)) {
        superclass = _parseType(input);
        if (superclass == null) {
          input.rewind('expected superclass in class definition');
          return null;
        }
      }
      CommaSeparatedList<TypeExpression> mixins;
      if (_consumeSpecificIdentifier(input, 'with')) {
        final List<TypeExpression> mixinTypes = _parseTypeList(input);
        if (mixinTypes == null) {
          input.rewind('expected type expressions after "with" keyword in class definition');
          return null;
        }
        mixins = new CommaSeparatedList<TypeExpression>(mixinTypes);
      }
      CommaSeparatedList<TypeExpression> interfaces;
      if (_consumeSpecificIdentifier(input, 'implements')) {
        final List<TypeExpression> interfaceTypes = _parseTypeList(input);
        if (interfaceTypes == null) {
          input.rewind('expected type expressions after "implements" keyword in class definition');
          return null;
        }
        interfaces = new CommaSeparatedList<TypeExpression>(interfaceTypes);
      }
      ClassDeclarationSequence body;
      if (!_consumeSpecificOperator(input, OpSemicolon)) {
        final ForwardReference link = new ForwardReference('_parseClassDefinition-body');
        final List<SerializableSegment> bodyItems = _parseRawBlock(input, link, className: identifier.value);
        if (bodyItems == null) {
          input.rewind('expected block after class definition');
          return null;
        }
        body = new ClassDeclarationSequence(bodyItems);
        link.seal(body);
      }
      input.commit();
      return new ClassDefinition(
        metadata: metadata,
        isAbstract: isAbstract,
        identifier: identifier,
        typeParameters: typeParameters,
        superclass: superclass,
        mixins: mixins,
        interfaces: interfaces,
        body: body,
      );
    });
  }

  Typedef _parseTypedef(InlineCommentStackTokenSource input) {
    return input.scope<Typedef>(() {
      input.save();
      final MetadataList metadata = _parseMetadata(input);
      if (!_consumeSpecificIdentifier(input, 'typedef')) {
        input.rewind();
        return null;
      }
      final Signature signature = _parseSignature(input);
      if (signature == null) {
        input.rewind('expected signature after "typedef"');
        return null;
      }
      if (!_consumeSpecificOperator(input, OpSemicolon)) {
        input.rewind('expected ";" after typedef');
        return null;
      }
      input.commit();
      return new Typedef(metadata, signature);
    });
  }

  SerializableSegment _parseBlockStatement(InlineCommentStackTokenSource input) {
    return input.scope<SerializableSegment>(() {
      final ForwardReference link = new ForwardReference('_parseBlockStatement');
      final List<SerializableSegment> block = _parseRawBlock(input, link);
      Block result;
      if (block != null) {
        result = new Block(new BlockSequence<SerializableSegment>(block));
      } else if (_consumeSpecificOperator(input, OpSemicolon)) {
        result = new Block(new BlockSequence<SerializableSegment>(<SerializableSegment>[]));
      }
      if (result != null)
        link.seal(result);
      return result;
    });
  }

  ForStatement _parseForStatement(InlineCommentStackTokenSource input) {
    return input.scope<ForStatement>(() {
      input.save();
      final bool hasAwait = _consumeSpecificIdentifier(input, 'await');
      if (!_consumeSpecificIdentifier(input, 'for')) {
        input.rewind();
        return null;
      }
      if (!_consumeSpecificOperator(input, OpOpenParen)) { // "("
        input.rewind('expected open paren after for keyword');
        return null;
      }
      ForCondition condition;
      final SerializableSegment part1 = _parseInitializedVariableDeclaration(input) ??
                                        _parseExpression(input);
      if (part1 == null) {
        input.rewind('expected variable declaration or expression in for loop parts');
        return null;
      }
      if (_consumeSpecificIdentifier(input, 'in')) {
        final Expression part2 = _parseExpression(input);
        condition = new ForInCondition(part1, part2);
      } else {
        if (!_consumeSpecificOperator(input, OpSemicolon)) {
          input.rewind('expected semicolon or "in" after first part of for loop');
          return null;
        }
        final Expression part2 = _parseExpression(input);
        if (!_consumeSpecificOperator(input, OpSemicolon)) {
          input.rewind('expected semicolon after second part of for loop');
          return null;
        }
        final CommaSeparatedList<Expression> part3 = new CommaSeparatedList<Expression>(
          _parseExpressionList(input)
        );
        condition = new TraditionalForCondition(part1, part2, part3);
      }
      if (!_consumeSpecificOperator(input, OpCloseParen)) {
        input.rewind('expected close paren after for loop parts');
        return null;
      }
      SerializableSegment body = _parseStatement(input);
      if (body == null) {
        input.rewind('expected statement part of "for" loop');
        return null;
      } else if (body is Block) {
        final Block blockBody = body;
        body = blockBody.unwrapped;
      }
      input.commit();
      return new ForStatement(condition, body, hasAwait: hasAwait);
    });
  }

  WhileStatement _parseWhileStatement(InlineCommentStackTokenSource input) {
    return input.scope<WhileStatement>(() {
      input.save();
      if (!_consumeSpecificIdentifier(input, 'while')) {
        input.rewind();
        return null;
      }
      final NestedExpression expression = _parseNestedExpression(input);
      if (expression == null) {
        input.rewind('expected parenthetical expression after "while" keyword');
        return null;
      }
      SerializableSegment body = _parseStatement(input);
      if (body == null) {
        input.rewind('expected statement after "while" expression');
        return null;
      } else if (body is Block) {
        final Block blockBody = body;
        body = blockBody.unwrapped;
      }
      input.commit();
      return new WhileStatement(expression, body);
    });
  }

  DoWhileStatement _parseDoWhileStatement(InlineCommentStackTokenSource input) {
    return input.scope<DoWhileStatement>(() {
      input.save();
      if (!_consumeSpecificIdentifier(input, 'do')) {
        input.rewind();
        return null;
      }
      SerializableSegment body = _parseStatement(input);
      if (body == null) {
        input.rewind('expected statement after "do" keyword');
        return null;
      } else if (body is Block) {
        final Block blockBody = body;
        body = blockBody.unwrapped;
      }
      if (!_consumeSpecificIdentifier(input, 'while')) {
        input.rewind('expected "while" keyword after "do" statement');
        return null;
      }
      final NestedExpression expression = _parseNestedExpression(input);
      if (expression == null) {
        input.rewind('expected parenthetical expression after "while" keyword');
        return null;
      }
      if (!_consumeSpecificOperator(input, OpSemicolon)) {
        input.rewind('expected semicolon after "do" loop expression');
        return null;
      }
      input.commit();
      return new DoWhileStatement(expression, body);
    });
  }

  SwitchStatement _parseSwitchStatement(InlineCommentStackTokenSource input) {
    return input.scope<SwitchStatement>(() {
      input.save();
      if (!_consumeSpecificIdentifier(input, 'switch')) {
        input.rewind();
        return null;
      }
      final NestedExpression expression = _parseNestedExpression(input);
      if (expression == null) {
        input.rewind('expected parenthetical expression after "if" keyword');
        return null;
      }
      if (!_consumeSpecificOperator(input, OpOpenBrace)) {
        input.rewind('expected open brace after switch expression');
        return null;
      }
      List<SwitchCase> cases;
      DefaultCase defaultCase;
      SwitchCaseBase lastCase;
      do {
        lastCase = _parseSwitchCase(input);
        if (lastCase is DefaultCase) {
          if (defaultCase != null) {
            input.rewind('unexpectedly parsed two default cases in switch statement');
            return null;
          }
          defaultCase = lastCase;
        } else if (lastCase != null) {
          cases ??= <SwitchCase>[];
          cases.add(lastCase);
        }
      } while (lastCase != null);
      if (!_consumeSpecificOperator(input, OpCloseBrace)) {
        input.rewind('expected close brace after case statements');
        return null;
      }
      input.commit();
      return new SwitchStatement(expression: expression, cases: cases, defaultCase: defaultCase);
    });
  }

  SwitchCaseBase _parseSwitchCase(InlineCommentStackTokenSource input) {
    return input.scope<SwitchCaseBase>(() {
      input.save();
      List<Label> labels;
      Label label = _parseLabel(input);
      while (label != null) {
        labels ??= <Label>[];
        labels.add(label);
        label = _parseLabel(input);
      }
      Expression expression;
      if (_consumeSpecificIdentifier(input, 'case')) {
        expression = _parseExpression(input);
      } else if (_consumeSpecificIdentifier(input, 'default')) {
        // no expression in default case
      } else {
        input.rewind('expected "case" or "default"');
        return null;
      }
      if (!_consumeSpecificOperator(input, OpColon)) {
        input.rewind('expected colon after "case" or "default" label');
        return null;
      }
      List<SerializableSegment> statements;
      SerializableSegment statement = _parseStatement(input);
      while (statement != null) {
        statements ??= <SerializableSegment>[];
        statements.add(statement);
        statement = _parseStatement(input);
      }
      input.commit();
      if (expression != null) {
        return new SwitchCase(labels: labels, expression: expression, statements: statements);
      } else {
        return new DefaultCase(labels: labels, statements: statements);
      }
    });
  }

  IfStatement _parseIfStatement(InlineCommentStackTokenSource input) {
    return input.scope<IfStatement>(() {
      input.save();
      input.setCommentParent(new ForwardReference('_parseIfStatement-expr'));
      if (!_consumeSpecificIdentifier(input, 'if')) {
        input.rewind();
        return null;
      }
      final NestedExpression expression = _parseNestedExpression(input);
      input.setCommentParent(expression);
      if (expression == null) {
        input.rewind('expected parenthetical expression after "if" keyword');
        return null;
      }
      SerializableSegment body = _parseStatement(input);
      if (body == null) {
        input.rewind('expected statement after "if" expression');
        return null;
      }
      input.setCommentParent(body);
      if (body is Block) {
        final Block blockBody = body;
        body = blockBody.unwrapped;
      }
      SerializableSegment elseBody;
      input.save();
      input.setCommentParent(new ForwardReference('_parseIfStatement-else'));
      if (_consumeSpecificIdentifier(input, 'else')) {
        // TODO(ianh): need to be able to put a comment after the "else" keyword in
        // if (foo) { } else /*here*/ { }
        elseBody = _parseStatement(input);
        if (elseBody == null) {
          input.rewind('expected statement after "else"');
        } else {
          input.commit();
          if (elseBody is Block) {
            final Block blockElseBody = elseBody;
            elseBody = blockElseBody.unwrapped;
          }
          input.setCommentParent(elseBody);
        }
      } else {
        input.rewind();
      }
      input.commit();
      return new IfStatement(expression, body, elseBody);
    });
  }

  TryStatement _parseTryStatement(InlineCommentStackTokenSource input) {
    return input.scope<TryStatement>(() {
      input.save();
      if (!_consumeSpecificIdentifier(input, 'try')) {
        input.rewind();
        return null;
      }
      final Block block = _parseBlock(input);
      if (block == null) {
        input.rewind('expected block after "try" keyword');
        return null;
      }
      final List<CatchPart> catchParts = <CatchPart>[];
      while (true) {
        TypeExpression onType;
        if (_consumeSpecificIdentifier(input, 'on')) {
          onType = _parseType(input);
        }
        CommaSeparatedList<Identifier> catchIdentifiers;
        if (_consumeSpecificIdentifier(input, 'catch')) {
          if (!_consumeSpecificOperator(input, OpOpenParen)) {
            input.rewind('expected open parenthesis after "catch" keyword');
            return null;
          }
          final List<Identifier> identifiers = <Identifier>[];
          do {
            final Identifier identifier = _parseIdentifier(input);
            if (identifier == null) {
              input.rewind('expected identifier in "catch" part');
              return null;
            }
            identifiers.add(identifier);
          } while (_consumeSpecificOperator(input, OpComma));
          if (!_consumeSpecificOperator(input, OpCloseParen)) {
            input.rewind('expected close parenthesis in "catch" part');
            return null;
          }
          catchIdentifiers = new CommaSeparatedList<Identifier>(identifiers);
        }
        if (onType != null || catchIdentifiers != null) {
          final Block catchBlock = _parseBlock(input);
          if (catchBlock == null) {
            input.rewind('expected block in "catch" part');
            return null;
          }
          catchParts.add(new CatchPart(onType, catchIdentifiers, catchBlock));
        } else {
          // no catch block
          break;
        }
      }
      Block finallyBlock;
      if (_consumeSpecificIdentifier(input, 'finally')) {
        finallyBlock = _parseBlock(input);
        if (finallyBlock == null) {
          input.rewind('expected block in "finally" part');
          return null;
        }
      }
      input.commit();
      return new TryStatement(block, catchParts, finallyBlock);
    });
  }

  KeywordStatement _parseFlowControlStatements(InlineCommentStackTokenSource input) {
    return input.scope<KeywordStatement>(() {
      input.save();
      input.setCommentParent(new ForwardReference('_parseFlowControlStatements'));
      Identifier keyword = _parseIdentifier(input);
      bool needExpression;
      if (keyword?.value == 'return' ||
          keyword?.value == 'break' ||
          keyword?.value == 'continue') {
        needExpression = false;
      } else if (keyword?.value == 'yield') {
        needExpression = true;
        if (_consumeSpecificOperator(input, OpTimes)) // "*"
          keyword = const Identifier('yield*');
      }
      if (needExpression == null) {
        input.rewind();
        return null;
      }
      assert(keyword != null);
      input.setCommentParent(keyword);
      final Expression expression = _parseExpression(input);
      if (needExpression && expression == null) {
        input.rewind('expected expression after $keyword');
        return null;
      }
      if (expression != null)
        input.setCommentParent(expression);
      if (!_consumeSpecificOperator(input, OpSemicolon)) {
        if (expression != null) {
          input.rewind('expected semicolon after expression $expression after $keyword');
        } else {
          input.rewind('expected semicolon after $keyword');
        }
        return null;
      }
      input.commit();
      assert(keyword != null);
      if (keyword.value == 'yield')
        return new YieldStatement(keyword, expression);
      if (keyword.value == 'yield*')
        return new YieldAllStatement(keyword, expression);
      if (keyword.value == 'break')
        return new BreakStatement(keyword, expression);
      if (keyword.value == 'continue')
        return new ContinueStatement(keyword, expression);
      assert(keyword.value == 'return');
      return new ReturnStatement(keyword, expression);
    });
  }

  ExpressionStatement _parseExpressionStatement(InlineCommentStackTokenSource input) {
    return input.scope<ExpressionStatement>(() {
      input.save();
      final Expression expression = _parseExpression(input);
      if (expression == null) {
        input.rewind();
        return null;
      }
      if (!_consumeSpecificOperator(input, OpSemicolon)) {
        input.rewind('could not find semicolon after expression ($expression)');
        return null;
      }
      input.commit();
      return new ExpressionStatement(expression);
    });
  }

  List<SerializableSegment> _parseRawBlock(InlineCommentStackTokenSource input, ForwardReference link, { String className }) {
    return input.scope<List<SerializableSegment>>(() {
      input.save();
      if (!_consumeSpecificOperator(input, OpOpenBrace)) { // U+007B LEFT CURLY BRACKET character ({)
        input.rewind();
        return null;
      }
      _handleInlineComments(input);
      final List<SerializableSegment> block = _parseBlockBody(input, link, className: className);
      if (!_consumeSpecificOperator(input, OpCloseBrace)) { // U+007D RIGHT CURLY BRACKET character (})
        input.rewind('expected statement or "}" in block');
        return null;
      }
      input.commit();
      return block;
    });
  }

  Block _parseBlock(InlineCommentStackTokenSource input) {
    return input.scope<Block>(() {
      input.save();
      final ForwardReference link = new ForwardReference('_parseBlock');
      final List<SerializableSegment> bodyItems = _parseRawBlock(input, link);
      if (bodyItems == null) {
        input.rewind();
        return null;
      }
      final BlockSequence body = new BlockSequence(bodyItems);
      link.seal(body);
      input.commit();
      return new Block(body);
    });
  }

  ExpressionStatement _parseLocalVariableDeclaration(InlineCommentStackTokenSource input) {
    return input.scope<ExpressionStatement>(() {
      input.save();
      final InitializedVariableDeclaration result = _parseInitializedVariableDeclaration(input);
      if (result == null) {
        input.rewind();
        return null;
      }
      if (!_consumeSpecificOperator(input, OpSemicolon)) {
        input.rewind('expected ";" after initialized variable declaration');
        return null;
      }
      input.commit();
      return new ExpressionStatement(result);
    });
  }

  InitializedVariableDeclaration _parseInitializedVariableDeclaration(InlineCommentStackTokenSource input) {
    return input.scope<InitializedVariableDeclaration>(() {
      input.save();
      final MetadataList metadata = _parseMetadata(input);
      bool isStatic = false;
      bool isFinal = false;
      bool isConst = false;
      loop: while (true) {
        input.save();
        final Identifier identifier = _parseIdentifier(input);
        switch (identifier?.value) {
          case 'static':
            if (isStatic) {
              input.rewind();
              input.rewind('saw keyword "static" twice when trying to parse initialized variable declaration');
              return null;
            }
            isStatic = true;
            break;
          case 'final':
            if (isFinal) {
              input.rewind();
              input.rewind('saw keyword "final" twice when trying to parse initialized variable declaration');
              return null;
            }
            isFinal = true;
            break;
          case 'const':
            if (isConst) {
              input.rewind();
              input.rewind('saw keyword "const" twice when trying to parse initialized variable declaration');
              return null;
            }
            isConst = true;
            break;
          default:
            input.rewind();
            break loop;
        }
        input.commit();
      }
      input.save();
      TypeExpression type = _parseType(input);
      if (type != null) {
        input.setCommentParent(type);
        input.save();
        if (_parseIdentifier(input) == null) {
          // in principle, this is only valid if isFinal or ifConst is true,
          // otherwise it should go through the expression (via
          // assignableExpression).
          type = null;
        }
        input.rewind();
      }
      if (type == null) {
        input.rewind();
      } else {
        if (type.isVar) {
          type = const TypeExpression(const QualifiedIdentifier(const Identifier('dynamic')));
          input.replaceCommentParent(type);
        }
        input.commit();
      }
      final List<Initializer> initializers = <Initializer>[];
      do {
        final Identifier identifier = _parseIdentifier(input);
        if (identifier != null) {
          input.save();
          Expression value;
          if (_consumeSpecificOperator(input, OpEquals)) {
            value = _parseExpression(input);
            if (value == null) {
              input.rewind('expected expression');
            } else {
              input.commit();
            }
          } else {
            input.rewind();
          }
          initializers.add(new Initializer(identifier, value));
        }
      } while (_consumeSpecificOperator(input, OpComma));
      if (initializers.isEmpty) {
        input.rewind();
        return null;
      }
      input.commit();
      return new InitializedVariableDeclaration(
        metadata: metadata,
        isStatic: isStatic,
        isFinal: isFinal,
        isConst: isConst,
        type: type,
        initializers: new CommaSeparatedList<Initializer>(initializers),
      );
    });
  }

  FunctionDeclaration _parseFunctionDeclaration(InlineCommentStackTokenSource input, { String className }) {
    return input.scope<FunctionDeclaration>(() {
      input.save();
      bool isExternal = false;
      bool isConst = false;
      bool isStatic = false;
      bool foundKeyword = false;
      loop: while (true) {
        input.save();
        final Identifier identifier = _parseIdentifier(input);
        switch (identifier?.value) {
          case 'external':
            if (isExternal) {
              input.rewind();
              input.rewind('saw keyword "external" twice when trying to parse initialized function declaration');
              return null;
            }
            isExternal = true;
            foundKeyword = true;
            break;
          case 'static':
            if (isStatic) {
              input.rewind();
              input.rewind('saw keyword "static" twice when trying to parse initialized function declaration');
              return null;
            }
            isStatic = true;
            foundKeyword = true;
            break;
          case 'const':
            // TODO(ianh): disallow if className == null
            if (isConst) {
              input.rewind();
              input.rewind('saw keyword "const" twice when trying to parse initialized function declaration');
              return null;
            }
            isConst = true;
            foundKeyword = true;
            break;
          // TODO(ianh): Implement "factory" if className != null
          default:
            input.rewind();
            break loop;
        }
        input.commit();
      }
      final Signature signature = _parseSignature(input, className: className);
      if (signature == null) {
        if (foundKeyword) {
          input.rewind('could not parse signature when trying to parse function declaration');
        } else {
          input.rewind();
        }
        return null;
      }
      final CommaSeparatedList<Expression> initializers = _parseInitializers(input);
      final FunctionBody body = _parseFunctionBody(input, isInExpression: false, canBeAbstract: className != null, canBeRedirection: true);
      if (body == null) {
        input.rewind('could not parse function body when trying to parse function declaration');
        return null;
      }
      input.commit();
      return new FunctionDeclaration(
        isExternal: isExternal,
        isStatic: isStatic,
        isConst: isConst,
        signature: signature,
        initializers: initializers,
        body: body,
      );
    });
  }

  Signature _parseSignature(InlineCommentStackTokenSource input, { bool allowMetadata: true, bool allowFinal: false, bool mightBeFieldFormalParameter: false, String className }) {
    return input.scope<Signature>(() {
      input.save();
      final MetadataList metadata = allowMetadata ? _parseMetadata(input) : null;
      bool isFinal = false;
      if (allowFinal) {
        input.save();
        final Identifier identifier = _parseIdentifier(input);
        if (identifier?.value == 'final') {
          isFinal = true;
          input.commit();
        } else {
          input.rewind();
        }
      }
      input.save();
      final TypeExpression returnType = _parseType(input, allowVar: false);
      if (returnType != null) {
        final Signature result = _parseSignatureRightHandSide(
          input,
          metadata: metadata,
          isFinal: isFinal,
          returnType: returnType,
          mightBeFieldFormalParameter: mightBeFieldFormalParameter,
          className: className,
        );
        if (result != null) {
          input.commit();
          input.commit();
          return result;
        }
      }
      input.rewind();
      final Signature result = _parseSignatureRightHandSide(
        input,
        metadata: metadata,
        isFinal: isFinal,
        mightBeFieldFormalParameter: mightBeFieldFormalParameter,
        className: className,
      );
      if (result != null) {
        input.commit();
        return result;
      }
      input.rewind();
      return null;
    });
  }

  Signature _parseSignatureRightHandSide(InlineCommentStackTokenSource input, {
    @required MetadataList metadata,
    @required bool isFinal,
    TypeExpression returnType,
    @required bool mightBeFieldFormalParameter,
    @required String className,
  }) {
    assert(!mightBeFieldFormalParameter || className == null);
    return input.scope<Signature>(() {
      input.save();
      QualifiedIdentifier identifier;
      bool isConstructor = false;
      if (mightBeFieldFormalParameter) {
        // field formal parameters in constructors can be of the form "this.bar"
        identifier = _parseQualifiedIdentifier(input);
        if (identifier == null || (identifier.isQualified && !identifier.isFromThis)) {
          input.rewind();
          return null;
        }
      } else if (className != null) {
        // constructors can be of the form "foo.bar" where "foo" is the class name
        // we have to tell if it's a constructor or not because constructors don't have return types
        identifier = _parseQualifiedIdentifier(input);
        if (identifier == null || (identifier.isQualified && (!identifier.isFrom(className) || returnType != null))) {
          input.rewind();
          return null;
        }
        isConstructor = true;
      } else {
        final Identifier name = _parseIdentifier(input);
        if (name != null)
          identifier = new QualifiedIdentifier(name);
      }
      if (identifier == null) {
        input.rewind();
        return null;
      }
      if (returnType == null && !isConstructor)
        returnType = const TypeExpression(const QualifiedIdentifier(const Identifier('dynamic')));
      input.setCommentParent(identifier);
      bool needsParameters = true;
      bool foundKeyword = false;
      Identifier keyword;
      if (identifier.asSingleIdentifier?.value == 'operator') {
        _handleInlineComments(input);
        final Token token = input.currentToken;
        if (token is OpLessThan ||
            token is OpGreaterThan ||
            token is OpLessThanOrEquals ||
            token is OpGreaterThanOrEquals ||
            token is OpEqualsEquals ||
            token is OpMinus ||
            token is OpPlus ||
            token is OpSlash ||
            token is OpTildeSlash ||
            token is OpTimes ||
            token is OpMod ||
            token is OpBinaryOr ||
            token is OpXor ||
            token is OpBinaryAnd ||
            token is OpLeftShift ||
            token is OpRightShift ||
            token is OpArrayEquals ||
            token is OpArray ||
            token is OpTilde) {
          input.consume();
          identifier = new QualifiedIdentifier(new Identifier('operator $token'));
          input.replaceCommentParent(identifier);
          foundKeyword = true;
        }
      } else if (identifier.asSingleIdentifier?.value == 'get') {
        keyword = const Identifier('get');
        needsParameters = false;
        identifier = null;
        foundKeyword = true;
      } else if (identifier.asSingleIdentifier?.value == 'set') {
        keyword = const Identifier('set');
        identifier = null;
        foundKeyword = true;
      }
      if (identifier == null) {
        identifier = _parseQualifiedIdentifier(input); // qualified because... symmetry, i guess?
        if (identifier == null) {
          if (foundKeyword) {
            input.rewind('expected identifier when trying to parse function signature');
          } else {
            input.rewind();
          }
          return null;
        }
      }
      ParameterList parameters;
      if (needsParameters) {
        parameters = _parseParameters(input, mightBeFieldFormalParameter: isConstructor);
        if (parameters == null) {
          if (foundKeyword) {
            input.rewind('expected parameter list when trying to parse function signature');
          } else {
            input.rewind();
          }
          return null;
        }
      }
      input.commit();
      return new Signature(
        metadata: metadata,
        isFinal: isFinal,
        returnType: returnType,
        keyword: keyword,
        identifier: identifier,
        parameters: parameters,
      );
    });
  }

  CommaSeparatedList<Expression> _parseInitializers(InlineCommentStackTokenSource input) {
    return input.scope<CommaSeparatedList<Expression>>(() {
      input.save();
      if (!_consumeSpecificOperator(input, OpColon)) {
        input.rewind();
        return null;
      }
      final List<Expression> initializers = <Expression>[];
      do {
        final Expression expression = _parseExpression(input);
        if (expression != null)
          initializers.add(expression);
      } while (_consumeSpecificOperator(input, OpComma));
      if (initializers.isEmpty) {
        input.rewind('expected expressions in initializer list');
        return null;
      }
      input.commit();
      return new CommaSeparatedList<Expression>(initializers);
    });
  }

  FunctionBody _parseFunctionBody(InlineCommentStackTokenSource input, { @required bool isInExpression, @required bool canBeAbstract, @required bool canBeRedirection }) {
    return input.scope<FunctionBody>(() {
      if (canBeAbstract && _consumeSpecificOperator(input, OpSemicolon))
        return const AbstractFunction();
      input.save();
      if (canBeRedirection && _consumeSpecificOperator(input, OpEquals)) {
        final QualifiedIdentifier identifier = _parseQualifiedIdentifier(input);
        if (identifier != null) {
          input.commit();
          return new RedirectImplementation(identifier);
        }
        input.rewind('expected identifier after "=" in method, function, or constructor declaration');
        return null;
      }
      input.save();
      final Identifier keyword = _parseIdentifier(input);
      bool asynchronous = false;
      bool generator = false;
      if (keyword?.value == 'async' || keyword?.value == 'sync') {
        input.commit();
        asynchronous = keyword.value == 'async';
        if (_consumeSpecificOperator(input, OpTimes))
          generator = true;
      } else {
        input.rewind();
      }
      if (_consumeSpecificOperator(input, OpArrow)) { // =>
        final Expression expression = _parseExpression(input);
        if (expression == null) {
          input.rewind('failed to parse expression after "=>" in function body');
          return null;
        }
        if (isInExpression || _consumeSpecificOperator(input, OpSemicolon)) {
          input.commit();
          return new FunctionImplementation(
            new Block(
              new BlockSequence(
                <SerializableSegment>[ new ReturnStatement.fromExpression(expression) ]
              )
            ),
            asynchronous: asynchronous,
            generator: generator,
            isInExpression: isInExpression,
          );
        }
      } else if (_consumeSpecificOperator(input, OpEquals)) {
        input.rewind('parsing of redirecting body not yet supported');
        return null;
      }
      final ForwardReference link = new ForwardReference('_parseFunctionBody-block');
      final List<SerializableSegment> body = _parseRawBlock(input, link);
      if (body != null) {
        input.commit();
        final BlockSequence block = new BlockSequence(body);
        link.seal(block);
        return new FunctionImplementation(
          new Block(block),
          asynchronous: asynchronous,
          generator: generator,
          isInExpression: isInExpression,
        );
      }
      input.rewind();
      return null;
    });
  }

  ParameterList _parseParameters(InlineCommentStackTokenSource input, { bool mightBeFieldFormalParameter: false }) {
    return input.scope<ParameterList>(() {
      input.save();
      final TypeParameters typeParameters = _parseTypeParameters(input);
      final List<_ParameterDefaultPair> parameters = <_ParameterDefaultPair>[];
      int positionals = 0;
      bool optionalsAreNamed;
      if (!_consumeSpecificOperator(input, OpOpenParen)) { // U+0028 LEFT PARENTHESIS character (()
        input.rewind();
        return null;
      }
      parameters.addAll(_subparseParameterList(input, mightBeFieldFormalParameter: mightBeFieldFormalParameter));
      positionals = parameters.length;
      if (_consumeSpecificOperator(input, OpOpenBracket)) {  // U+005B LEFT SQUARE BRACKET character ([)
        optionalsAreNamed = false;
        parameters.addAll(_subparseParameterList(input, mightBeFieldFormalParameter: mightBeFieldFormalParameter));
        if (!_consumeSpecificOperator(input, OpCloseBracket)) { // U+005D RIGHT SQUARE BRACKET character (])
          input.rewind('expected "]" after optional parameters');
          return null;
        }
      } else if (_consumeSpecificOperator(input, OpOpenBrace)) { // U+007B LEFT CURLY BRACKET character ({)
        optionalsAreNamed = true;
        parameters.addAll(_subparseParameterList(input, mightBeFieldFormalParameter: mightBeFieldFormalParameter));
        if (!_consumeSpecificOperator(input, OpCloseBrace)) { // U+007D RIGHT CURLY BRACKET character (})
          input.rewind('expected "}" after optional parameters');
          return null;
        }
      }
      if (!_consumeSpecificOperator(input, OpCloseParen)) { // U+0029 RIGHT PARENTHESIS character ())
        input.rewind('expected ")" at end of parameter list');
        return null;
      }
      input.commit();
      if (parameters.isEmpty)
        return new ParameterList(typeParameters: typeParameters);
      assert(positionals <= parameters.length);
      for (int index = 0; index < positionals; index += 1) {
        if (parameters[index].defaultValue != null) {
          positionals = index;
          break;
        }
      }
      if (optionalsAreNamed == null && positionals < parameters.length)
        optionalsAreNamed = true;
      CommaSeparatedList<Parameter> positionalParameters;
      if (positionals > 0) {
        positionalParameters = new CommaSeparatedList<Parameter>(
          parameters.take(positionals).map<Parameter>((_ParameterDefaultPair data) => data.parameter).toList()
        );
      }
      if (optionalsAreNamed == null) {
        assert(positionals == parameters.length);
        assert(positionals > 0);
        return new ParameterList(typeParameters: typeParameters, positionalParameters: positionalParameters);
      }
      if (optionalsAreNamed) {
        return new ParameterList(
          typeParameters: typeParameters,
          positionalParameters: positionalParameters,
          namedParameters: new CommaSeparatedList<OptionalNamedParameter>(
            parameters.skip(positionals).map<OptionalNamedParameter>((_ParameterDefaultPair data) => new OptionalNamedParameter(
              data.parameter,
              data.defaultValue,
            )).toList()
          ),
        );
      }
      return new ParameterList(
        typeParameters: typeParameters,
        positionalParameters: positionalParameters,
        optionalParameters: new CommaSeparatedList<OptionalPositionalParameter>(
          parameters.skip(positionals).map<OptionalPositionalParameter>((_ParameterDefaultPair data) => new OptionalPositionalParameter(
            data.parameter,
            data.defaultValue,
          )).toList()
        ),
      );
    });
  }

  List<_ParameterDefaultPair> _subparseParameterList(InlineCommentStackTokenSource input, { @required bool mightBeFieldFormalParameter }) {
    return input.scope<List<_ParameterDefaultPair>>(() {
      input.save();
      final List<_ParameterDefaultPair> result = <_ParameterDefaultPair>[];
      try {
        do {
          // parse the formal parameter
          Parameter parameter;
          final Signature signature = _parseSignature(input, allowFinal: true, mightBeFieldFormalParameter: mightBeFieldFormalParameter);
          if (signature != null) {
            parameter = new FunctionSignatureParameter(signature);
          } else {
            input.save();
            final MetadataList metadata = _parseMetadata(input);
            bool isFinal = false;
            input.save();
            final Identifier keyword = _parseIdentifier(input);
            if (keyword?.value == 'final') {
              isFinal = true;
              input.commit();
            } else {
              input.rewind();
            }
            input.save();
            TypeExpression type = _parseType(input);
            QualifiedIdentifier identifier;
            if (type != null) {
              identifier = _parseQualifiedIdentifier(input);
              if (identifier != null) {
                input.commit();
              } else {
                type = const TypeExpression(const QualifiedIdentifier(const Identifier('dynamic')));
                input.rewind();
              }
            } else {
              input.rewind();
            }
            identifier ??= _parseQualifiedIdentifier(input);
            if (identifier != null) {
              parameter = new FieldFormalParameter(metadata, isFinal, type, identifier);
              input.commit();
            } else {
              input.rewind();
            }
          }
          if (parameter != null) {
            input.save();
            Expression defaultValue;
            if ((_consumeSpecificOperator(input, OpColon)) || // U+003A COLON character (:)
                (_consumeSpecificOperator(input, OpEquals))) { // U+003D EQUALS SIGN character (=)
              defaultValue = _parseExpression(input);
              if (defaultValue != null) {
                input.commit();
              } else {
                input.rewind();
              }
            } else {
              input.rewind();
            }
            result.add(new _ParameterDefaultPair(parameter, defaultValue));
          }
        } while (_consumeSpecificOperator(input, OpComma)); // ","
      } on String catch(message) {
        input.rewind(message);
        return <_ParameterDefaultPair>[];
      }
      input.commit();
      return result;
    });
  }

  Expression _parseExpression(InlineCommentStackTokenSource input, { bool withoutCascade: false }) {
    return input.scope<Expression>(() {
      Expression result = _parseAssignment(input, withoutCascade: withoutCascade);
      result ??= _parseThrowExpression(input, withoutCascade: withoutCascade);
      if (result == null) {
        if (withoutCascade)
          result = _parseConditionalExpression(input);
        else
          result = _parseCascadedExpression(input);
      }
      return result;
    });
  }

  List<Expression> _parseExpressionList(InlineCommentStackTokenSource input) {
    return input.scope<List<Expression>>(() {
      final List<Expression> result = <Expression>[];
      do {
        final Expression item = _parseExpression(input);
        if (item != null)
          result.add(item);
      } while (_consumeSpecificOperator(input, OpComma)); // ","
      return result;
    });
  }

  Expression _parseAssignment(InlineCommentStackTokenSource input, { bool withoutCascade: false }) {
    return input.scope<Expression>(() {
      input.save();
      final Expression expression = _parseAssignableExpression(input);
      if (expression == null) {
        input.rewind();
        return null;
      }
      final AlternatingList<Operator, Expression> chain = _parseRightHandSide(input, withoutCascade: withoutCascade);
      if (chain == null) {
        input.rewind();
        return null;
      }
      input.commit();
      return new ExpressionOperatorChain(expression, chain);
    });
  }

  Expression _parseAssignableExpression(InlineCommentStackTokenSource input) {
    return input.scope<Expression>(() {
      final Expression expression = _parsePrimary(input);
      if (expression == null)
        return null;
      input.save();
      final List<SelectorOrArgumentChainComponent> chain = _parseSelectorOrArgumentChain(input);
      if (chain == null) {
        input.rewind();
        return expression;
      }
      input.commit();
      return new AssignableExpression(expression, chain);
    });
  }

  Expression _parsePrimary(InlineCommentStackTokenSource input) {
    return input.scope<Expression>(() {
      Expression expression;
      input.save();
      final ParameterList parameters = _parseParameters(input);
      if (parameters != null) {
        final FunctionBody body = _parseFunctionBody(input, isInExpression: true, canBeAbstract: false, canBeRedirection: false);
        if (body != null) {
          input.commit();
          return new FunctionExpression(parameters, body);
        }
        input.rewind('no function body found after what looked like parameters');
        input.save();
      }
      expression = _parseNestedExpression(input) ??
                   _parseNumericLiteral(input) ??
                   _parseStringLiteral(input) ??
                   // _parseSymbolLiteral(input) ?? // TODO(ianh): Implement
                   _parseMapLiteral(input) ??
                   _parseListLiteral(input);
      if (expression != null) {
        input.commit();
        return expression;
      }
      final Identifier keyword = _parseIdentifier(input);
      if (keyword?.value == 'const' || keyword?.value == 'new') {
        // newExpression or constObjectExpression (they are identical except for the keyword)
        final QualifiedIdentifier className = _parseQualifiedIdentifier(input);
        if (className != null) {
          final TypeArguments typeArguments = _parseTypeArguments(input);
          Identifier constructorName;
          if (_consumeSpecificOperator(input, OpDot)) {
            constructorName = _parseIdentifier(input);
            if (constructorName == null) {
              input.rewind('no constructor name found after period after qualified identifier after $keyword');
              return null;
            }
          }
          final Arguments arguments = _parseArguments(input);
          if (arguments != null) {
            input.commit();
            return new Constructor(keyword, className, constructorName, typeArguments, arguments);
          }
        }
        input.rewind('no constructor call found after $keyword');
        return null;
      }
      if (keyword != null) {
        // this, super, null, true, and false are all treated like any arbitrary
        // identifier. Technically, "super" should only be allowed if followed by a
        // selector, but we allow it as a lone identifier because it makes many of
        // the expression parsing functions not have to special-case it. It also
        // makes the formatter more forgiving.
        input.commit();
        return keyword;
      }
      input.rewind();
      return null;
    });
  }

  NestedExpression _parseNestedExpression(InlineCommentStackTokenSource input) {
    return input.scope<NestedExpression>(() {
      input.save();
      if (!_consumeSpecificOperator(input, OpOpenParen)) { // U+0028 LEFT PARENTHESIS character (()
        input.rewind();
        return null;
      }
      final Expression expression = _parseExpression(input);
      if (expression == null || !_consumeSpecificOperator(input, OpCloseParen)) { // U+0029 RIGHT PARENTHESIS character ())
        input.rewind('no nested expression found after open paren');
        return null;
      }
      input.commit();
      return new NestedExpression(expression);
    });
  }

  List<SelectorOrArgumentChainComponent> _parseSelectorOrArgumentChain(InlineCommentStackTokenSource input) {
    return input.scope<List<SelectorOrArgumentChainComponent>>(() {
      List<SelectorOrArgumentChainComponent> result;
      while (true) {
        SelectorOrArgumentChainComponent item = _parseArgumentsSelector(input);
        if (item == null)
          item = _parseSelector(input);
        if (item == null)
          return result;
        result ??= <SelectorOrArgumentChainComponent>[];
        result.add(item);
      }
    });
  }

  ArgumentsSelector _parseArgumentsSelector(InlineCommentStackTokenSource input) {
    return input.scope<ArgumentsSelector>(() {
      input.save();
      final TypeArguments typeArguments = _parseTypeArguments(input);
      final Arguments arguments = _parseArguments(input);
      if (arguments != null) {
        input.commit();
        return new ArgumentsSelector(typeArguments, arguments);
      }
      input.rewind();
      return null;
    });
  }

  Arguments _parseArguments(InlineCommentStackTokenSource input) {
    return input.scope<Arguments>(() {
      input.save();
      if (!_consumeSpecificOperator(input, OpOpenParen)) { // "("
        input.rewind();
        return null;
      }
      final List<Argument> arguments = <Argument>[];
      do {
        final Argument argument = _parseArgument(input);
        if (argument != null)
          arguments.add(argument);
      } while (_consumeSpecificOperator(input, OpComma)); // ","
      if (!_consumeSpecificOperator(input, OpCloseParen)) { // ")"
        input.rewind('no close paren for arguments');
        return null;
      }
      input.commit();
      return new Arguments(arguments);
    });
  }

  Argument _parseArgument(InlineCommentStackTokenSource input) {
    return input.scope<Argument>(() {
      input.save();
      input.save();
      Identifier identifier = _parseIdentifier(input);
      if (identifier != null) {
        if (_consumeSpecificOperator(input, OpColon)) { // U+003A COLON character (:)
          input.commit();
        } else {
          input.rewind();
          identifier = null;
        }
      } else {
        input.commit();
      }
      final Expression value = _parseExpression(input);
      if (value != null) {
        input.commit();
        return new Argument(name: identifier, value: value);
      }
      input.rewind();
      return null;
    });
  }

  Selector _parseSelector(InlineCommentStackTokenSource input) {
    return input.scope<Selector>(() {
      input.save();
      if (_consumeSpecificOperator(input, OpOpenBracket)) { // "["
        final Expression expression = _parseExpression(input);
        if (expression == null) {
          input.rewind('expected expression after "["');
          return null;
        }
        if (_consumeSpecificOperator(input, OpCloseBracket)) { // "]"
          input.commit();
          return new ArraySelector(expression);
        }
        input.rewind('expected "]" after expression after "["');
        return null;
      }
      Operator op;
      if (_consumeSpecificOperator(input, OpDot)) {
        op = const Operator('.');
      } else if (_consumeSpecificOperator(input, OpElvisDot)) {
        op = const Operator('?.');
      } else {
        input.rewind();
        return null;
      }
      final Identifier identifier = _parseIdentifier(input);
      if (identifier == null) {
        input.rewind('expected identifier after $op');
        return null;
      }
      input.commit();
      return new OperatorSelector(op, identifier);
    });
  }

  Expression _parseCascadedExpression(InlineCommentStackTokenSource input) {
    return input.scope<Expression>(() {
      final Expression expression = _parseConditionalExpression(input);
      if (expression == null)
        return null;
      input.save();
      final List<CascadeSection> cascades = _parseCascadeSections(input);
      if (cascades == null) {
        input.rewind();
        return expression;
      }
      input.commit();
      return new CascadedExpression(expression, cascades);
    });
  }

  List<CascadeSection> _parseCascadeSections(InlineCommentStackTokenSource input) {
    return input.scope<List<CascadeSection>>(() {
      List<CascadeSection> result;
      input.save();
      while (_consumeSpecificOperator(input, OpDotDot)) { // ".."
        final CascadeSection next = _parseCascadeSection(input);
        if (next == null) {
          input.rewind('expected cascade section after ".." operator');
          return result;
        }
        result ??= <CascadeSection>[];
        result.add(next);
        input.commit();
        input.save();
      }
      input.rewind();
      return result;
    });
  }

  CascadeSection _parseCascadeSection(InlineCommentStackTokenSource input) {
    return input.scope<CascadeSection>(() {
      final CascadeSelector selector = _parseCascadeSelector(input);
      if (selector == null)
        return null;
      input.save();
      final List<SelectorOrArgumentChainComponent> chain1 = _parseSelectorOrArgumentChain(input);
      if (chain1 != null) {
        input.commit();
        input.save();
      }
      final AlternatingList<Operator, Expression> chain2 = _parseRightHandSide(input, withoutCascade: true);
      if (chain2 != null) {
        input.commit();
      } else {
        input.rewind();
      }
      return new CascadeSection(selector, chain1, chain2);
    });
  }

  CascadeSelector _parseCascadeSelector(InlineCommentStackTokenSource input) {
    return input.scope<CascadeSelector>(() {
      input.save();
      final CascadeSelector value = _parseIdentifier(input);
      if (value != null) {
        input.commit();
        return value;
      }
      if (!_consumeSpecificOperator(input, OpOpenBracket)) { // "["
        input.rewind();
        return null;
      }
      final Expression expression = _parseExpression(input);
      if (!_consumeSpecificOperator(input, OpCloseBracket)) { // "]"
        input.rewind();
        return null;
      }
      input.commit();
      return new ArraySelector(expression);
    });
  }

  Expression _parseThrowExpression(InlineCommentStackTokenSource input, { bool withoutCascade: false }) {
    return input.scope<Expression>(() {
      input.save();
      if (!_consumeSpecificIdentifier(input, 'throw')) {
        input.rewind();
        return null;
      }
      final Expression expression = _parseExpression(input, withoutCascade: withoutCascade);
      if (expression == null) {
        input.rewind('expected expression after keyword "throw"');
        return null;
      }
      input.commit();
      return new PrefixKeywordExpression(const Identifier('throw'), expression);
    });
  }

  Expression _parseConditionalExpression(InlineCommentStackTokenSource input) {
    return input.scope<Expression>(() {
      Expression expression = _parseIfNullExpression(input);
      if (expression == null)
        return null;
      input.save();
      if (_consumeSpecificOperator(input, OpQuery)) { // U+003F QUESTION MARK character (?)
        final Expression part1 = _parseExpression(input, withoutCascade: true);
        if (part1 == null) {
          input.rewind('expected expression after question mark in conditional expression');
        } else {
          if (!_consumeSpecificOperator(input, OpColon)) { // U+003A COLON character (:)
            input.rewind('expected colon after expression in conditional expression');
          } else {
            final Expression part2 = _parseExpression(input, withoutCascade: true);
            if (part2 == null) {
              input.rewind('expected expression after colon in conditional expression');
            } else {
              expression = new ConditionalExpression(expression, part1, part2);
              input.commit();
            }
          }
        }
      } else {
        input.rewind();
      }
      return expression;
    });
  }

  Expression _parseIfNullExpression(InlineCommentStackTokenSource input) {
    return input.scope<Expression>(() {
      return _parseOperatorExpression(input, const OpElvis(), _parseLogicalOrExpression);
    });
  }

  Expression _parseLogicalOrExpression(InlineCommentStackTokenSource input) {
    return input.scope<Expression>(() {
      return _parseOperatorExpression(input, const OpLogicalOr(), _parseLogicalAndExpression);
    });
  }

  Expression _parseLogicalAndExpression(InlineCommentStackTokenSource input) {
    return input.scope<Expression>(() {
      return _parseOperatorExpression(input, const OpLogicalAnd(), _parseEqualityExpression);
    });
  }

  Expression _parseEqualityExpression(InlineCommentStackTokenSource input) {
    return input.scope<Expression>(() {
      Expression expression = _parseRelationalExpression(input);
      // expression can be a lone "super", handling "super == expression" and "super != expression"
      input.save();
      Operator op;
      if (_consumeSpecificOperator(input, OpEqualsEquals)) {
        op = const Operator('==');
      } else if (_consumeSpecificOperator(input, OpBangEquals)) {
        op = const Operator('!=');
      } else {
        input.rewind();
        return expression;
      }
      assert(op != null);
      final Expression subexpression = _parseRelationalExpression(input);
      if (subexpression != null) {
        input.commit();
        expression = new ExpressionOperatorChain(
          expression,
          new AlternatingList<Operator, Expression>.pair(op, subexpression)..seal(),
        );
      } else {
        input.rewind();
      }
      return expression;
    });
  }

  Expression _parseRelationalExpression(InlineCommentStackTokenSource input) {
    return input.scope<Expression>(() {
      // This matches "super is foo" which isn't technically valid but which it is
      // harmless for us to handle in the formatter in case it comes up for some
      // reason.
      final Expression expression = _parseBitwiseOrExpression(input);
      if (expression == null)
        return null;
      input.save();
      Operator op;
      if (_consumeSpecificIdentifier(input, 'is')) {
        if (_consumeSpecificOperator(input, OpBang)) { // "!"
          // TODO(ianh): Handle comment(s) between the "is" and the "!".
          // Ideally not by actually serializing them there, because that is crazy.
          op = const Operator('is!');
        } else {
          op = const Operator('is');
        }
        final TypeExpression type = _parseType(input);
        if (type != null) {
          input.commit();
          return new ExpressionOperatorChain(
            expression,
            new AlternatingList<Operator, Expression>.pair(op, type)..seal(),
          );
        }
      } else if (_consumeSpecificIdentifier(input, 'as')) { // "as"
        op = const Operator('as');
        final TypeExpression type = _parseType(input);
        if (type != null) {
          input.commit();
          return new ExpressionOperatorChain(
            expression,
            new AlternatingList<Operator, Expression>.pair(op, type)..seal(),
          );
        }
      } else {
        if (_consumeSpecificOperator(input, OpGreaterThanOrEquals)) { // ">="
          op = const Operator('>=');
        } else if (_consumeSpecificOperator(input, OpGreaterThan)) { // ">"
          op = const Operator('>');
        } else if (_consumeSpecificOperator(input, OpLessThanOrEquals)) { // "<="
          op = const Operator('<=');
        } else if (_consumeSpecificOperator(input, OpLessThan)) { // "<"
          op = const Operator('<');
        }
        if (op != null) {
          final Expression rightHandSide = _parseBitwiseOrExpression(input);
          input.commit();
          return new ExpressionOperatorChain(
            expression,
            new AlternatingList<Operator, Expression>.pair(op, rightHandSide)..seal(),
          );
        }
      }
      input.rewind();
      return expression;
    });
  }

  Expression _parseBitwiseOrExpression(InlineCommentStackTokenSource input) {
    return input.scope<Expression>(() {
      return _parseOperatorExpression(input, const OpBinaryOr(), _parseBitwiseXorExpression);
    });
  }

  Expression _parseBitwiseXorExpression(InlineCommentStackTokenSource input) {
    return input.scope<Expression>(() {
      return _parseOperatorExpression(input, const OpXor(), _parseBitwiseAndExpression);
    });
  }

  Expression _parseBitwiseAndExpression(InlineCommentStackTokenSource input) {
    return input.scope<Expression>(() {
      return _parseOperatorExpression(input, const OpBinaryAnd(), _parseShiftExpression);
    });
  }

  Expression _parseShiftExpression(InlineCommentStackTokenSource input) {
    return input.scope<Expression>(() {
      return _parseMultipleOperatorExpression(input, const <Token>[const OpLeftShift(), const OpRightShift()], _parseAdditiveExpression);
    });
  }

  Expression _parseAdditiveExpression(InlineCommentStackTokenSource input) {
    return input.scope<Expression>(() {
      return _parseMultipleOperatorExpression(input, const <Token>[const OpPlus(), const OpMinus()], _parseMultiplicativeExpression);
    });
  }

  Expression _parseMultiplicativeExpression(InlineCommentStackTokenSource input) {
    return input.scope<Expression>(() {
      return _parseMultipleOperatorExpression(input, const <Token>[const OpTimes(), const OpSlash(), const OpMod(), const OpTildeSlash()], _parseUnaryExpression);
    });
  }

  Expression _parseUnaryExpression(InlineCommentStackTokenSource input) {
    return input.scope<Expression>(() {
      input.save();
      Operator op;
      Expression expression;
      if (_consumeSpecificOperator(input, OpMinus)) {
        op = const Operator('-');
      } else if (_consumeSpecificOperator(input, OpBang)) {
        op = const Operator('!');
      } else if (_consumeSpecificOperator(input, OpTilde)) {
        op = const Operator('~');
      }
      if (op != null) {
        expression = _parseUnaryExpression(input);
        if (expression != null) {
          input.commit();
          return new PrefixOperatorExpression(op, expression);
        }
        input.rewind();
        input.save();
        op = null;
      }
      if (_consumeSpecificIdentifier(input, 'await')) {
        expression = _parseUnaryExpression(input);
        if (expression != null) {
          input.commit();
          return new PrefixKeywordExpression(const Identifier('await'), expression);
        }
        input.rewind();
        input.save();
      }
      expression = _parsePostfixExpression(input);
      if (expression != null) {
        input.commit();
        return expression;
      }
      if (_consumeSpecificOperator(input, OpMinus)) { // "-"
        op = const Operator('-');
      } else if (_consumeSpecificOperator(input, OpTilde)) { // "~"
        op = const Operator('~');
      }
      if (op != null) {
        if (_consumeSpecificIdentifier(input, 'super')) {
          input.commit();
          return new PrefixOperatorExpression(op, const Identifier('super'));
        }
        input.rewind();
        input.save();
        op = null;
      }
      if (_consumeSpecificOperator(input, OpPlusPlus)) { // "++"
        op = const Operator('++');
      } else if (_consumeSpecificOperator(input, OpMinusMinus)) { // "--"
        op = const Operator('--');
      }
      if (op != null) {
        expression = _parseAssignableExpression(input);
        if (expression != null) {
          input.commit();
          return new PrefixOperatorExpression(op, expression);
        }
      }
      input.rewind();
      return null;
    });
  }

  Expression _parsePostfixExpression(InlineCommentStackTokenSource input) {
    return input.scope<Expression>(() {
      final Expression expression = _parseAssignableExpression(input);
      // AssignableExpression handles the case of primary + arguments
      if (expression == null)
        return null;
      input.save();
      Operator op;
      if (_consumeSpecificOperator(input, OpPlusPlus)) { // "++"
        op = const Operator('++');
      } else if (_consumeSpecificOperator(input, OpMinusMinus)) { // "--"
        op = const Operator('--');
      }
      // TODO(ianh): parse symbols
      if (op != null) {
        input.commit();
        return new PostfixOperatorExpression(expression, op);
      }
      input.rewind();
      return expression;
    });
  }

  AlternatingList<Operator, Expression> _parseRightHandSide(InlineCommentStackTokenSource input, { bool withoutCascade: false }) {
    return input.scope<AlternatingList<Operator, Expression>>(() {
      input.save();
      _handleInlineComments(input);
      final Token token = input.currentToken;
      if (token is OpEquals ||
          token is OpTimesEquals ||
          token is OpSlashEquals ||
          token is OpTildeSlashEquals ||
          token is OpModEquals ||
          token is OpPlusEquals ||
          token is OpMinusEquals ||
          token is OpLeftShiftEquals ||
          token is OpRightShiftEquals ||
          token is OpBinaryAndEquals ||
          token is OpLogicalAndEquals ||
          token is OpXorEquals ||
          token is OpBinaryOrEquals ||
          token is OpLogicalOrEquals ||
          token is OpElvisEquals) {
        input.consume();
        final Expression expression = _parseExpression(input, withoutCascade: withoutCascade);
        if (expression == null) {
          input.rewind('expected expression after assignment operator');
          return null;
        }
        input.commit();
        return new AlternatingList<Operator, Expression>.pair(new Operator('$token'), expression)..seal();
      }
      input.rewind();
      return null;
    });
  }

  Expression _parseOperatorExpression(InlineCommentStackTokenSource input, Token opToken, ParserFunction<Expression> nextParser) {
    assert(opToken.constant);
    return input.scope<Expression>(() {
      Expression expression = nextParser(input);
      if (expression == null)
        return null;
      input.save();
      input.setCommentParent(expression);
      List<Expression> expressions;
      while (_consumeSpecificOperator(input, opToken.runtimeType)) {
        final Expression candidate = nextParser(input);
        if (candidate == null) {
          input.rewind('expected expression after operator');
          input.save();
          break;
        }
        input.setCommentParent(candidate);
        expressions ??= <Expression>[];
        expressions.add(candidate);
        input.commit();
        input.save();
      }
      input.commit();
      if (expressions != null) {
        final Operator op = new Operator('$opToken');
        final AlternatingList<Operator, Expression> chain = new AlternatingList<Operator, Expression>();
        for (Expression subexpression in expressions)
          chain.addPair(op, subexpression);
        expression = new ExpressionOperatorChain(expression, chain..seal());
      }
      return expression;
    });
  }

  Expression _parseMultipleOperatorExpression(InlineCommentStackTokenSource input, List<Token> opList, ParserFunction<Expression> nextParser) {
    return input.scope<Expression>(() {
      final Expression expression = nextParser(input);
      if (expression == null)
        return null;
      input.save();
      AlternatingList<Operator, Expression> chain;
      loop: while (true) {
        for (Token opToken in opList) {
          if (_consumeSpecificOperator(input, opToken.runtimeType)) {
            final Expression candidate = nextParser(input);
            if (candidate == null) {
              input.rewind('expected expression after operator');
              input.save();
              break loop;
            }
            chain ??= new AlternatingList<Operator, Expression>();
            chain.addPair(new Operator('$opToken'), candidate);
            input.commit();
            input.save();
            continue loop;
          }
        }
        break;
      }
      input.commit();
      if (chain != null)
        return new ExpressionOperatorChain(expression, chain..seal());
      return expression;
    });
  }

  MetadataList _parseMetadata(InlineCommentStackTokenSource input) {
    return input.scope<MetadataList>(() {
      List<Metadata> metadatas;
      input.save();
      loop: while (_consumeSpecificOperator(input, OpAt)) {
        final TriplyQualifiedIdentifier name = _parseTriplyQualifiedIdentifier(input);
        if (name == null)
          break loop;
        final Arguments arguments = _parseArguments(input);
        input.commit();
        metadatas ??= <Metadata>[];
        metadatas.add(new Metadata(name, arguments));
        input.save();
      }
      input.rewind();
      if (metadatas == null)
        return null;
      assert(metadatas.isNotEmpty);
      return new MetadataList(metadatas);
    });
  }

  Label _parseLabel(InlineCommentStackTokenSource input) {
    return input.scope<Label>(() {
      input.save();
      input.setCommentParent(new ForwardReference('_parseLabel'));
      final Identifier name = _parseIdentifier(input);
      if (name == null || !_consumeSpecificOperator(input, OpColon)) { // ":"
        input.rewind();
        return null;
      }
      input.setCommentParent(name);
      input.commit();
      return new Label(name);
    });
  }

  TypeExpression _parseType(InlineCommentStackTokenSource input, { bool allowVar: true }) {
    return input.scope<TypeExpression>(() {
      input.save();
      final QualifiedIdentifier baseType = _parseQualifiedIdentifier(input);
      if (baseType == null || (!allowVar && baseType.isVar)) {
        input.rewind();
        return null;
      }
      input.commit();
      final TypeArguments arguments = _parseTypeArguments(input);
      return new TypeExpression(baseType, arguments);
    });
  }

  TypeArguments _parseTypeArguments(InlineCommentStackTokenSource input) {
    return input.scope<TypeArguments>(() {
      if (_consumeSpecificOperator(input, OpLessThan)) { // "<"
        input.save();
        final List<TypeExpression> subtypes = <TypeExpression>[];
        do {
          final TypeExpression subtype = _parseType(input);
          if (subtype != null)
            subtypes.add(subtype);
        } while (_consumeSpecificOperator(input, OpComma)); // ","
        input.explode(<Token, List<Token>>{
          const OpRightShift(): const <Token>[const OpGreaterThan(), const OpGreaterThan()],
          const OpRightShiftEquals(): const <Token>[const OpGreaterThan(), const OpGreaterThanOrEquals()],
          const OpGreaterThanOrEquals(): const <Token>[const OpGreaterThan(), const OpEquals()],
        });
        if (!_consumeSpecificOperator(input, OpGreaterThan)) { // ">"
          input.rewind('missing ">" after type arguments');
          return null;
        }
        input.commit();
        return new TypeArguments(subtypes);
      }
      return null;
    });
  }

  List<TypeExpression> _parseTypeList(InlineCommentStackTokenSource input) {
    return input.scope<List<TypeExpression>>(() {
      final List<TypeExpression> result = <TypeExpression>[];
      do {
        final TypeExpression item = _parseType(input);
        if (item != null)
          result.add(item);
      } while (_consumeSpecificOperator(input, OpComma)); // ","
      return result;
    });
  }

  TypeParameters _parseTypeParameters(InlineCommentStackTokenSource input) {
    return input.scope<TypeParameters>(() {
      input.save();
      if (!_consumeSpecificOperator(input, OpLessThan)) { // "<"
        input.rewind();
        return null;
      }
      final List<TypeParameter> parameters = <TypeParameter>[];
      do {
        final TypeParameter next = _parseTypeParameter(input);
        if (next != null)
          parameters.add(next);
      } while (_consumeSpecificOperator(input, OpComma)); // ","
      if (!_consumeSpecificOperator(input, OpGreaterThan)) { // ">"
        input.rewind('expected ">" at end of type parameter list');
        return null;
      }
      input.commit();
      return new TypeParameters(parameters);
    });
  }

  TypeParameter _parseTypeParameter(InlineCommentStackTokenSource input) {
    return input.scope<TypeParameter>(() {
      input.save();
      final MetadataList metadata = _parseMetadata(input);
      final Identifier identifier = _parseIdentifier(input);
      if (identifier == null) {
        input.rewind();
        return null;
      }
      TypeExpression upperBound;
      if (_consumeSpecificIdentifier(input, 'extends')) {
        upperBound = _parseType(input);
        if (upperBound == null) {
          input.rewind('expected type after "extends" in type parameter');
          return null;
        }
      }
      input.commit();
      return new TypeParameter(metadata, identifier, upperBound);
    });
  }

  MapLiteral _parseMapLiteral(InlineCommentStackTokenSource input) {
    return input.scope<MapLiteral>(() {
      input.save();
      final bool isConst = _consumeSpecificIdentifier(input, 'const');
      final TypeArguments type = _parseTypeArguments(input);
      if (_consumeSpecificOperator(input, OpOpenBrace)) { // "{"
        final List<MapLiteralEntry> values = <MapLiteralEntry>[];
        do {
          input.save();
          input.setCommentParent(new ForwardReference('_parseMapLiteral-expr1'));
          final Expression expression1 = _parseExpression(input);
          if (expression1 == null) {
            input.rewind();
            continue;
          }
          input.setCommentParent(expression1);
          if (!_consumeSpecificOperator(input, OpColon)) {
            input.rewind();
            continue;
          }
          input.setCommentParent(new ForwardReference('_parseMapLiteral-expr2'));
          final Expression expression2 = _parseExpression(input);
          if (expression2 == null) {
            input.rewind();
            continue;
          }
          input.setCommentParent(expression2);
          values.add(new MapLiteralEntry(expression1, expression2));
          input.commit();
        } while (_consumeSpecificOperator(input, OpComma)); // ","
        if (_consumeSpecificOperator(input, OpCloseBrace)) { // "}"
          input.commit();
          return new MapLiteral(isConst, type, new CommaSeparatedList<MapLiteralEntry>(values));
        }
      }
      input.rewind();
      return null;
    });
  }

  ListLiteral _parseListLiteral(InlineCommentStackTokenSource input) {
    return input.scope<ListLiteral>(() {
      input.save();
      final bool isConst = _consumeSpecificIdentifier(input, 'const');
      final TypeArguments type = _parseTypeArguments(input);
      if (_consumeSpecificOperator(input, OpArray)) { // "[]"
        input.commit();
        return new ListLiteral(isConst, type, new CommaSeparatedList<Expression>(const <Expression>[]));
      } else if (_consumeSpecificOperator(input, OpOpenBracket)) { // "["
        final List<Expression> values = <Expression>[];
        do {
          final Expression expression = _parseExpression(input);
          if (expression != null)
            values.add(expression);
        } while (_consumeSpecificOperator(input, OpComma)); // ","
        if (_consumeSpecificOperator(input, OpCloseBracket)) { // "]"
          input.commit();
          return new ListLiteral(isConst, type, new CommaSeparatedList<Expression>(values));
        }
      }
      input.rewind();
      return null;
    });
  }

  NumericLiteral _parseNumericLiteral(InlineCommentStackTokenSource input) {
    return input.scope<NumericLiteral>(() {
      input.save();
      _handleInlineComments(input);
      final Token token = input.currentToken;
      switch (token.runtimeType) {
        case HexNumericToken:
        case IntegerNumericToken:
        case DoubleNumericToken:
          input.consume();
          input.commit();
          return new NumericLiteral(token.toString());
          break;
        default:
          input.rewind();
          return null;
      }
    });
  }

  StringLiteral _parseStringLiteral(InlineCommentStackTokenSource input) {
    return input.scope<StringLiteral>(() {
      List<StringLiteralSegment> body;
      loop: while (true) {
        switch (input.currentToken.runtimeType) {
          case OpQuot:
          case OpQuotQuotQuot:
          case OpRawQuot:
          case OpApos:
          case OpAposAposApos:
          case OpRawApos:
            body ??= <StringLiteralSegment>[];
            input.consume();
            while (true) {
              if (input.currentToken is StringLiteralSegmentToken) {
                final StringLiteralSegmentToken token = input.currentToken;
                input.consume();
                body.add(new StringLiteralText(token.value));
              } else if (input.currentToken is OpInterpolatedBlock) {
                input.consume();
                input.save();
                final Expression expression = _parseExpression(input);
                _handleInlineComments(input);
                if (input.currentToken is! OpCloseBrace) {
                  input.rewind('expected closing brace after interpolated expression in string literal');
                  throw 'unsure how to parse interpolated block in string literal at $input';
                }
                input.consume(); // the closing brace
                input.commit();
                body.add(new StringLiteralInterpolation(expression));
              } else if (input.currentToken is OpDollar) {
                input.consume();
                assert(input.currentToken is IdentifierToken);
                final IdentifierToken token = input.currentToken;
                input.consume();
                body.add(new StringLiteralInterpolation(new Identifier(token.value)));
              } else {
                break;
              }
            }
            break;
          default:
            break loop;
        }
      }
      if (body == null)
        return null;
      return new StringLiteral(body);
    });
  }

  QualifiedIdentifier _parseQualifiedIdentifier(InlineCommentStackTokenSource input) {
    return input.scope<QualifiedIdentifier>(() {
      final Identifier identifier1 = _parseIdentifier(input);
      if (identifier1 == null)
        return null;
      input.save();
      if (_consumeSpecificOperator(input, OpDot)) { // U+002E FULL STOP character (.)
        final Identifier identifier2 = _parseIdentifier(input);
        if (identifier2 == null) {
          input.rewind('expected identifier after period in qualified identifier');
          return new QualifiedIdentifier(identifier1);
        }
        input.commit();
        return new QualifiedIdentifier(identifier1, identifier2);
      }
      input.rewind();
      return new QualifiedIdentifier(identifier1);
    });
  }

  TriplyQualifiedIdentifier _parseTriplyQualifiedIdentifier(InlineCommentStackTokenSource input) {
    return input.scope<TriplyQualifiedIdentifier>(() {
      final Identifier identifier1 = _parseIdentifier(input);
      if (identifier1 != null) {
        input.save();
        if (_consumeSpecificOperator(input, OpDot)) { // U+002E FULL STOP character (.)
          final Identifier identifier2 = _parseIdentifier(input);
          if (identifier2 != null) {
            input.commit();
            input.save();
            if (_consumeSpecificOperator(input, OpDot)) { // U+002E FULL STOP character (.)
              final Identifier identifier3 = _parseIdentifier(input);
              if (identifier3 != null) {
                input.commit();
                return new TriplyQualifiedIdentifier(identifier1, identifier2, identifier3);
              }
            }
            input.rewind();
            return new TriplyQualifiedIdentifier(identifier1, identifier2);
          }
        }
        input.rewind();
        return new TriplyQualifiedIdentifier(identifier1);
      }
      return null;
    });
  }

  bool _consumeSpecificIdentifier(InlineCommentStackTokenSource input, String keyword) {
    // This function is hot so we start with some fast paths.
    if (input.currentToken is IdentifierToken) {
      final IdentifierToken identifier = input.currentToken;
      if (identifier.value != keyword)
        return false;
      input.consume();
      return true;
    }
    if (!input.currentToken.isCommentStart)
      return false;
    // We have a comment to deal with so now let's do the slower path.
    return input.scope<bool>(() {
      input.save();
      _handleInlineComments(input);
      final Token token = input.currentToken;
      if (token is! IdentifierToken) {
        input.rewind();
        return false;
      }
      final IdentifierToken identifier = token;
      if (identifier.value != keyword) {
        input.rewind();
        return false;
      }
      input.consume();
      input.commit();
      return true;
    });
  }

  bool _consumeSpecificOperator(InlineCommentStackTokenSource input, Type token) {
    // This function is hot so we start with some fast paths.
    if (!input.currentToken.isCommentStart && input.currentToken.runtimeType != token)
      return false;
    return input.scope<bool>(() {
      input.save();
      _handleInlineComments(input);
      if (input.currentToken.runtimeType == token) {
        input.consume();
        input.commit();
        return true;
      }
      input.rewind();
      return false;
    });
  }

  Identifier _parseIdentifier(InlineCommentStackTokenSource input) {
    // This function is hot so we start with some fast paths.
    if (!input.currentToken.isCommentStart && input.currentToken is! IdentifierToken)
      return null;
    return input.scope<Identifier>(() {
      input.save();
      _handleInlineComments(input);
      final Token token = input.currentToken;
      if (token is! IdentifierToken) {
        input.rewind();
        return null;
      }
      input.consume();
      input.commit();
      final IdentifierToken identifier = token;
      return new Identifier(identifier.value);
    });
  }

  void _handleInlineComments(InlineCommentStackTokenSource input) {
    if (!input.currentToken.isCommentStart)
      return;
    if (input.currentToken is LineBreakToken) {
      // TODO(ianh): This doesn't handle a newline followed by an inline
      // comment in the middle of an expression.
      input.consume();
      return;
    }
    Type tokenType;
    InlineCommentParseContext commentContext;
    void flush() {
      if (commentContext == null)
        return;
      final List<SerializableSegment> segments = commentContext.close();
      assert(segments.length == 1);
      final SerializableSegment comment = segments.single;
      input.addComment(comment);
      commentContext = null;
    }
    input.scope<Null>(() {
      while (true) {
        final Type currentTokenType = (input.currentToken).runtimeType;
        switch (currentTokenType) {
          case OpDartDocBlockComment:
          case OpBlockComment:
          case OpDartDocLineComment:
          case OpLineComment:
            assert(input.currentToken.isCommentStart);
            if (currentTokenType != tokenType)
              flush();
            input.consume();
            if (input.currentToken is CommentBodyToken) {
              final CommentBodyToken body = input.currentToken;
              input.consume();
              commentContext ??= new InlineCommentParseContext();
              commentContext.addBuffer(body.value, input.position);
              tokenType = currentTokenType;
            } // else comment was empty, ignore it
            break;
          default:
            assert(input.currentToken is LineBreakToken || !input.currentToken.isCommentStart);
            flush();
            return;
        }
      }
    });
  }
}

class InterruptionToken extends Token {
  InterruptionToken(this.segment);
  final SerializableSegment segment;
  @override
  String toString() => segment.toString();
  @override
  bool operator ==(dynamic other) {
    return (other.runtimeType == runtimeType) && (other.segment == segment);
  }
  @override
  int get hashCode => runtimeType.hashCode ^ segment.hashCode;
  @override
  bool get constant => false;
}

abstract class SecondaryParseContext {
  SecondaryParseContext() {
    _tokenizer = createTokenizer();
  }

  AbstractTokenizer _tokenizer;
  List<TokenPosition> _tokenStream = <TokenPosition>[];
  List<SerializableSegment> _interruptions;

  @protected
  AbstractTokenizer createTokenizer();

  void addBuffer(String value, TokenPosition start) {
    if (value.trim().isEmpty) {
      endLine();
      endLine();
    } else {
      _tokenStream.addAll(_tokenizer.tokenize(value, start: start));
    }
  }

  void endLine() {
    _tokenStream.add(_tokenizer.wrap(const LineBreakToken()));
  }

  void addInterruption(SerializableSegment segment) {
    _tokenStream.add(_tokenizer.wrap(new InterruptionToken(segment)));
    _interruptions ??= <SerializableSegment>[];
    _interruptions.add(segment);
  }

  List<SerializableSegment> close([ForwardReference parent]) {
    _tokenStream.add(_tokenizer.terminate());
    final List<SerializableSegment> result = <SerializableSegment>[
      parse(new TokenSource(_tokenStream), parent),
    ];
    if (_interruptions != null)
      result.addAll(_interruptions);
    return result;
  }

  @protected
  SerializableSegment parse(TokenSource input, ForwardReference parent);
}

abstract class CommentParseContext extends SecondaryParseContext {
  @override
  AbstractTokenizer createTokenizer() {
    return new CommentTokenizer();
  }

  TextSpanSequence parseParagraphBody(TokenSource input) {
    return input.scope<TextSpanSequence>(() {
      final List<TextSpan> body = <TextSpan>[];
      loop: while (input.currentToken is! EOFToken) {
        switch (input.currentToken.runtimeType) {
          case LineBreakToken:
            input.consume();
            if (body.isNotEmpty && body.first is Word) {
              final Word firstWord = body.first;
              if (firstWord.value == 'Copyright') {
                body.add(const HardLineBreak());
              }
            }
            if (input.currentToken is LineBreakToken) {
              input.consume();
              break loop;
            }
            if (input.currentToken is SpaceToken) {
              input.save();
              input.consume();
              if (consumeBullet(input)) {
                input.rewind();
                break loop;
              }
              input.rewind();
            }
            break;
          case SpaceToken:
            final SpaceToken token = input.currentToken;
            if (token.length > 1)
              body.add(new Word(' ' * (token.length - 2)));
            input.consume();
            break;
          case WordToken:
            final WordToken token = input.currentToken;
            body.add(new Word(token.value));
            input.consume();
            break;
        }
      }
      return new TextSpanSequence(body);
    });
  }

  bool consumeBullet(TokenSource input) {
    return input.scope<bool>(() {
      if (input.currentToken is WordToken) {
        final WordToken word = input.currentToken;
        if (word.value == '*' || word.value == '-') {
          input.consume();
          if (input.currentToken is SpaceToken) {
            final SpaceToken spaceToken = input.currentToken;
            if (spaceToken.length == 1)
              input.consume();
          }
          return true;
        }
      }
      return false;
    });
  }

  int consumeIndent(TokenSource input) {
    return input.scope<int>(() {
      if (input.currentToken is SpaceToken) {
        final SpaceToken indentToken = input.currentToken;
        input.consume();
        assert(input.currentToken is! SpaceToken);
        return indentToken.length ~/ 2;
      }
      return 0;
    });
  }
}

class BlockCommentParseContext extends CommentParseContext {
  @override
  SerializableSegment parse(TokenSource input, ForwardReference parent) {
    return input.scope<Comment>(() {
      final List<TextBlock> paragraphs = <TextBlock>[];
      while (input.currentToken is! EOFToken) {
        final int indent = consumeIndent(input);
        final bool bulleted = consumeBullet(input);
        final TextSpanSequence body = parseParagraphBody(input);
        paragraphs.add(new Paragraph(body, indentLevel: indent, bulleted: bulleted));
      }
      assert(input.currentToken is EOFToken);
      input.consume();
      assert(input.atEnd);
      return new Comment(new BlockSequence(paragraphs, paragraphs: true));
    });
  }
}

class InlineCommentParseContext extends BlockCommentParseContext {
  @override
  SerializableSegment parse(TokenSource input, ForwardReference parent) {
    return input.scope<SerializableSegment>(() {
      input.save();
      SerializableSegment result = new InlineComment(parseParagraphBody(input));
      if (input.currentToken is EOFToken) {
        input.consume();
        input.commit();
        assert(input.atEnd);
        return result;
      } else {
        assert(!input.atEnd);
      }
      input.rewind();
      result = super.parse(input, parent);
      assert(input.atEnd);
      return result;
    });
  }
}

class DartDocParseContext extends SecondaryParseContext {
  @override
  AbstractTokenizer createTokenizer() {
    return new DartDocTokenizer();
  }

  @override
  SerializableSegment parse(TokenSource input, ForwardReference parent) {
    // TODO(ianh): Parse the dartdoc.
    print('failed to parse a dartdoc');
    return throw null;
  }
}
