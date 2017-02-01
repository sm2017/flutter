// Copyright 2017 The Chromium Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

import 'dart:async';

import '../base/file_system.dart';
import 'src/parser.dart';

Future<String> reformat(File file, { bool verify: false }) async {
  String result;
  try {
    result = new ProgramParseContext().parseDartProgram(await file.readAsString()).toString();
  } catch (exception, stack) {
    if (verify) {
      result = '$exception\n$stack';
    } else {
      rethrow;
    }
  }
  if (verify) {
    final File golden = fs.file(fs.path.withoutExtension(file.path) + '.golden');
    if (!await golden.exists())
      throw new Exception('No golden file available for this file.');
    final String ideal = await golden.readAsString();
    if (result == ideal)
      return '';
    result = '// ${file.path}\n// FAILED: did not match golden file\n$result';
  }
  return result;
}

Future<Null> main(List<String> arguments) async {
  if (arguments.isNotEmpty) {
    for (String name in arguments)
      print(await reformat(fs.file(name)));
    return;
  }
  print('format.dart:\n-----8<-----');
  print(await reformat(fs.file('format.dart')));
  print('-----8<-----\n\nsrc/parser.dart:\n-----8<-----');
  print(await reformat(fs.file('src/parser.dart')));
  print('-----8<-----');
}
