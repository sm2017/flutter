// Copyright 2017 The Chromium Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

// Rolls the dev channel.
// Only tested on Linux.
//
// See: https://github.com/flutter/flutter/wiki/Release-process

import 'dart:io';

import 'package:args/args.dart';
import 'archive_publisher.dart';

const String kIncrement = 'increment';
const String kX = 'x';
const String kY = 'y';
const String kZ = 'z';
const String kHelp = 'help';

void main(List<String> args) {
  // Set the cwd to the repo root, since we know where this script is located.
  final Directory scriptLocation = new Directory(Platform.script.toFilePath());
  Directory.current = scriptLocation.parent.parent.parent;

  final ArgParser argParser = new ArgParser(allowTrailingOptions: false);
  argParser.addOption(
    kIncrement,
    help: 'Specifies which part of the x.y.z version number to increment. Required.',
    valueHelp: 'level',
    allowed: <String>[kX, kY, kZ],
    allowedHelp: <String, String>{
      kX: 'Indicates a major development, e.g. typically changed after a big press event.',
      kY: 'Indicates a minor development, e.g. typically changed after a beta release.',
      kZ: 'Indicates the least notable level of change. You normally want this.',
    },
  );
  argParser.addFlag(kHelp, negatable: false, help: 'Show this help message.', hide: true);
  ArgResults argResults;
  try {
    argResults = argParser.parse(args);
  } on ArgParserException catch (error) {
    print(error.message);
    print(argParser.usage);
    exit(1);
  }

  final String level = argResults[kIncrement];
  final bool help = argResults[kHelp];

  if (help || level == null) {
    print('roll_dev.dart --increment=x • update the version tags and roll a new dev build.\n');
    print(argParser.usage);
    exit(0);
  }

  runGit('checkout master', 'switch to master branch');

  if (getGitOutput('status --porcelain', 'check status of your local checkout') != '') {
    print('Your git repository is not clean. Try running "git clean -fd". Warning, this ');
    print('will delete files! Run with -n to find out which ones.');
    exit(1);
  }

  String version = getFullTag();
  final Match match = parseFullTag(version);
  if (match == null) {
    print('Could not determine the version for this build.');
    if (version.isNotEmpty)
      print('Git reported the latest version as "$version", which does not fit the expected pattern.');
    exit(1);
  }

  final List<int> parts = match.groups(<int>[1, 2, 3]).map(int.parse).toList();

  if (match.group(4) == '0') {
    print('This commit has already been released, as version ${parts.join(".")}.');
    exit(0);
  }

  switch (level) {
    case kX:
      parts[0] += 1;
      parts[1] = 0;
      parts[2] = 0;
      break;
    case kY:
      parts[1] += 1;
      parts[2] = 0;
      break;
    case kZ:
      parts[2] += 1;
      break;
    default:
      print('Unknown increment level. The valid values are "$kX", "$kY", and "$kZ".');
      exit(1);
  }
  version = parts.join('.');

  runGit('fetch upstream', 'fetch upstream');
  runGit('reset upstream/master --hard', 'check out master branch');
  runGit('tag v$version', 'tag the commit with the version label');
  final String hash = getGitOutput('rev-parse HEAD', 'Get git hash for $version tag');

  print('Your tree is ready to publish Flutter $version (${hash.substring(0, 10)}) '
    'to the "dev" channel.');
  stdout.write('Are you? [yes/no] ');
  if (stdin.readLineSync() != 'yes') {
    runGit('tag -d v$version', 'remove the tag you did not want to publish');
    print('The dev roll has been aborted.');
    exit(0);
  }

  // Publish the archive before pushing the tag so that if something fails in
  // the publish step, we can clean up.
  try {
    new ArchivePublisher(hash, version, Channel.dev)..publishArchive();
  } on ArchivePublisherException catch (e) {
    print('Archive publishing failed.\n$e');
    runGit('tag -d $version', 'remove the tag that was not published');
    print('The dev roll has been aborted.');
    exit(0);
  }

  runGit('push upstream v$version', 'publish the version');
  runGit('push upstream HEAD:dev', 'land the new version on the "dev" branch');
  print('Flutter version $version has been rolled to the "dev" channel!');
}

String getFullTag() {
  return getGitOutput(
    'describe --match v*.*.* --first-parent --long --tags',
    'obtain last released version number',
  );
}

Match parseFullTag(String version) {
  final RegExp versionPattern = new RegExp('^v([0-9]+)\.([0-9]+)\.([0-9]+)-([0-9]+)-g([a-f0-9]+)\$');
  return versionPattern.matchAsPrefix(version);
}

String getGitOutput(String command, String explanation) {
  final ProcessResult result = _runGit(command);
  if (result.stderr.isEmpty && result.exitCode == 0)
    return result.stdout.trim();
  _reportGitFailureAndExit(result, explanation);
  return null; // for the analyzer's sake
}

void runGit(String command, String explanation) {
  final ProcessResult result = _runGit(command);
  if (result.exitCode != 0)
    _reportGitFailureAndExit(result, explanation);
}

ProcessResult _runGit(String command) {
  return Process.runSync('git', command.split(' '));
}

void _reportGitFailureAndExit(ProcessResult result, String explanation) {
  if (result.exitCode != 0) {
    print('Failed to $explanation. Git exitted with error code ${result.exitCode}.');
  } else {
    print('Failed to $explanation.');
  }
  if (result.stdout.isNotEmpty)
    print('stdout from git:\n${result.stdout}\n');
  if (result.stderr.isNotEmpty)
    print('stderr from git:\n${result.stderr}\n');
  exit(1);
}
