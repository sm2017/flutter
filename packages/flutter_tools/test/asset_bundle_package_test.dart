// Copyright 2017 The Chromium Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

import 'dart:async';
import 'dart:convert';

import 'package:file/file.dart';
import 'package:file/memory.dart';

import 'package:flutter_tools/src/asset.dart';
import 'package:flutter_tools/src/base/file_system.dart';
import 'package:flutter_tools/src/base/platform.dart';
import 'package:flutter_tools/src/cache.dart';
import 'package:flutter_tools/src/flutter_manifest.dart';

import 'src/common.dart';
import 'src/context.dart';

void main() {
  // These tests do not use a memory file system because we want to ensure that
  // asset bundles work correctly on Windows and Posix systems.
  // DO NOT RELY ON SETTING THE CURRENT DIRECTORY. Doing so would affect all
  // the other tests running at the same time. Instead, use filename() below.
  Directory tempDir;

  setUp(() async {
    tempDir = fs.systemTempDirectory.createTempSync('flutter_asset_bundle_test.');
  });

  tearDown(() {
    tryToDelete(tempDir);
  });

  /// Makes a path that points at relativePath inside the tempDir.
  String filename(String relativePath) {
    return fs.path.join(tempDir.path, relativePath);
  }

  void writePubspecFile(String path, String name, {List<String> assets}) {
    String assetsSection;
    if (assets == null) {
      assetsSection = '';
    } else {
      final StringBuffer buffer = new StringBuffer();
      buffer.write('''
flutter:
     assets:
''');

      for (String asset in assets) {
        buffer.write('''
       - $asset
''');
      }
      assetsSection = buffer.toString();
    }

    final Uri uri = new Uri.file(path, windows: platform.isWindows);

    fs.file(uri)
      ..createSync(recursive: true)
      ..writeAsStringSync('''
name: $name
dependencies:
  flutter:
    sdk: flutter
$assetsSection
''');
  }

  void establishFlutterRoot() {
    Cache.flutterRoot = getFlutterRoot();
  }

  void writePackagesFile(String packages) {
    fs.file(filename('.packages'))
      ..createSync()
      ..writeAsStringSync(packages);
  }

  Future<Null> buildAndVerifyAssets(
    List<String> assets,
    List<String> packages,
    String expectedAssetManifest,
  ) async {
    final AssetBundle bundle = AssetBundleFactory.instance.createBundle();
    await bundle.build(manifestPath: filename('pubspec.yaml'));

    for (String packageName in packages) {
      for (String asset in assets) {
        final String entryKey = Uri.encodeFull('packages/$packageName/$asset');
        expect(bundle.entries.containsKey(entryKey), true, reason: 'Cannot find key on bundle: $entryKey');
        expect(
          utf8.decode(await bundle.entries[entryKey].contentsAsBytes()),
          asset,
        );
      }
    }

    expect(
      utf8.decode(await bundle.entries['AssetManifest.json'].contentsAsBytes()),
      expectedAssetManifest,
    );
  }

  void writeAssets(String path, List<String> assets) {
    for (String asset in assets) {
      final String fullPath = fs.path.join(path, asset); // posix compatible

      final String normalizedFullPath = // posix and windows compatible over MemoryFileSystem
      new Uri.file(fullPath, windows: platform.isWindows)
        .toFilePath(windows: platform.isWindows);

      print('$normalizedFullPath => $asset');
      fs.file(normalizedFullPath)
        ..createSync(recursive: true)
        ..writeAsStringSync(asset);
    }
  }

  group('AssetBundle assets from packages', () {
    testUsingContext('No assets are bundled when the package has no assets', () async {
      establishFlutterRoot();

      writePubspecFile(filename('pubspec.yaml'), 'test');
      writePackagesFile(filename('test_package:p/p/lib/'));
      writePubspecFile(filename('p/p/pubspec.yaml'), 'test_package');

      final AssetBundle bundle = AssetBundleFactory.instance.createBundle();
      await bundle.build(manifestPath: filename('pubspec.yaml'));
      expect(bundle.entries.length, 3); // LICENSE, AssetManifest, FontManifest
      const String expectedAssetManifest = '{}';
      expect(
        utf8.decode(await bundle.entries['AssetManifest.json'].contentsAsBytes()),
        expectedAssetManifest,
      );
      expect(
        utf8.decode(await bundle.entries['FontManifest.json'].contentsAsBytes()),
        '[]',
      );
    });

    testUsingContext('No assets are bundled when the package has an asset that is not listed', () async {
      establishFlutterRoot();

      writePubspecFile(filename('pubspec.yaml'), 'test');
      writePackagesFile(filename('test_package:p/p/lib/'));
      writePubspecFile(filename('p/p/pubspec.yaml'), 'test_package');

      final List<String> assets = <String>['a/foo'];
      writeAssets(filename('p/p/'), assets);

      final AssetBundle bundle = AssetBundleFactory.instance.createBundle();
      await bundle.build(manifestPath: filename('pubspec.yaml'));
      expect(bundle.entries.length, 3); // LICENSE, AssetManifest, FontManifest
      const String expectedAssetManifest = '{}';
      expect(
        utf8.decode(await bundle.entries['AssetManifest.json'].contentsAsBytes()),
        expectedAssetManifest,
      );
      expect(
        utf8.decode(await bundle.entries['FontManifest.json'].contentsAsBytes()),
        '[]',
      );
    });

    testUsingContext('One asset is bundled when the package has and lists one asset its pubspec', () async {
      establishFlutterRoot();

      writePubspecFile(filename('pubspec.yaml'), 'test');
      writePackagesFile(filename('test_package:p/p/lib/'));

      final List<String> assets = <String>['a/foo'];
      writePubspecFile(
        filename('p/p/pubspec.yaml'),
        'test_package',
        assets: assets,
      );

      writeAssets(filename('p/p/'), assets);

      const String expectedAssetManifest = '{"packages/test_package/a/foo":'
          '["packages/test_package/a/foo"]}';
      await buildAndVerifyAssets(
        assets,
        <String>['test_package'],
        expectedAssetManifest,
      );
    });

    testUsingContext("One asset is bundled when the package has one asset, listed in the app's pubspec", () async {
      establishFlutterRoot();

      final List<String> assetEntries = <String>['packages/test_package/a/foo'];
      writePubspecFile(
        filename('pubspec.yaml'),
        'test',
        assets: assetEntries,
      );
      writePackagesFile('test_package:p/p/lib/');
      writePubspecFile(filename('p/p/pubspec.yaml'), 'test_package');

      final List<String> assets = <String>['a/foo'];
      writeAssets(filename('p/p/lib/'), assets);

      const String expectedAssetManifest = '{"packages/test_package/a/foo":'
          '["packages/test_package/a/foo"]}';
      await buildAndVerifyAssets(
        assets,
        <String>['test_package'],
        expectedAssetManifest,
      );
    });

    testUsingContext('One asset and its variant are bundled when the package has an asset and a variant, and lists the asset in its pubspec', () async {
      establishFlutterRoot();

      writePubspecFile(filename('pubspec.yaml'), 'test');
      writePackagesFile('test_package:p/p/lib/');
      writePubspecFile(
        filename('p/p/pubspec.yaml'),
        'test_package',
        assets: <String>['a/foo'],
      );

      final List<String> assets = <String>['a/foo', 'a/v/foo'];
      writeAssets(filename('p/p/'), assets);

      const String expectedManifest = '{"packages/test_package/a/foo":'
          '["packages/test_package/a/foo","packages/test_package/a/v/foo"]}';

      await buildAndVerifyAssets(
        assets,
        <String>['test_package'],
        expectedManifest,
      );
    });

    testUsingContext('One asset and its variant are bundled when the package has an asset and a variant, and the app lists the asset in its pubspec', () async {
      establishFlutterRoot();

      writePubspecFile(
        filename('pubspec.yaml'),
        'test',
        assets: <String>['packages/test_package/a/foo'],
      );
      writePackagesFile('test_package:p/p/lib/');
      writePubspecFile(
        filename('p/p/pubspec.yaml'),
        'test_package',
      );

      final List<String> assets = <String>['a/foo', 'a/v/foo'];
      writeAssets(filename('p/p/lib/'), assets);

      const String expectedManifest = '{"packages/test_package/a/foo":'
          '["packages/test_package/a/foo","packages/test_package/a/v/foo"]}';

      await buildAndVerifyAssets(
        assets,
        <String>['test_package'],
        expectedManifest,
      );
    });

    testUsingContext('Two assets are bundled when the package has and lists two assets in its pubspec', () async {
      establishFlutterRoot();

      writePubspecFile(filename('pubspec.yaml'), 'test');
      writePackagesFile('test_package:p/p/lib/');

      final List<String> assets = <String>['a/foo', 'a/bar'];
      writePubspecFile(
        filename('p/p/pubspec.yaml'),
        'test_package',
        assets: assets,
      );

      writeAssets(filename('p/p/'), assets);
      const String expectedAssetManifest =
          '{"packages/test_package/a/bar":["packages/test_package/a/bar"],'
          '"packages/test_package/a/foo":["packages/test_package/a/foo"]}';

      await buildAndVerifyAssets(
        assets,
        <String>['test_package'],
        expectedAssetManifest,
      );
    });

    testUsingContext("Two assets are bundled when the package has two assets, listed in the app's pubspec", () async {
      establishFlutterRoot();

      final List<String> assetEntries = <String>[
        'packages/test_package/a/foo',
        'packages/test_package/a/bar',
      ];
      writePubspecFile(
        filename('pubspec.yaml'),
        'test',
         assets: assetEntries,
      );
      writePackagesFile('test_package:p/p/lib/');

      final List<String> assets = <String>['a/foo', 'a/bar'];
      writePubspecFile(
        filename('p/p/pubspec.yaml'),
        'test_package',
      );

      writeAssets(filename('p/p/lib/'), assets);
      const String expectedAssetManifest =
          '{"packages/test_package/a/bar":["packages/test_package/a/bar"],'
          '"packages/test_package/a/foo":["packages/test_package/a/foo"]}';

      await buildAndVerifyAssets(
        assets,
        <String>['test_package'],
        expectedAssetManifest,
      );
    });

    testUsingContext('Two assets are bundled when two packages each have and list an asset their pubspec', () async {
      establishFlutterRoot();

      writePubspecFile(
        filename('pubspec.yaml'),
        'test',
      );
      writePackagesFile('test_package:p/p/lib/\ntest_package2:p2/p/lib/');
      writePubspecFile(
        filename('p/p/pubspec.yaml'),
        'test_package',
        assets: <String>['a/foo'],
      );
      writePubspecFile(
        filename('p2/p/pubspec.yaml'),
        'test_package2',
        assets: <String>['a/foo'],
      );

      final List<String> assets = <String>['a/foo', 'a/v/foo'];
      writeAssets(filename('p/p/'), assets);
      writeAssets(filename('p2/p/'), assets);

      const String expectedAssetManifest =
          '{"packages/test_package/a/foo":'
          '["packages/test_package/a/foo","packages/test_package/a/v/foo"],'
          '"packages/test_package2/a/foo":'
          '["packages/test_package2/a/foo","packages/test_package2/a/v/foo"]}';

      await buildAndVerifyAssets(
        assets,
        <String>['test_package', 'test_package2'],
        expectedAssetManifest,
      );
    });

    testUsingContext("Two assets are bundled when two packages each have an asset, listed in the app's pubspec", () async {
      establishFlutterRoot();

      final List<String> assetEntries = <String>[
        'packages/test_package/a/foo',
        'packages/test_package2/a/foo',
      ];
      writePubspecFile(
        filename('pubspec.yaml'),
        'test',
        assets: assetEntries,
      );
      writePackagesFile('test_package:p/p/lib/\ntest_package2:p2/p/lib/');
      writePubspecFile(
        filename('p/p/pubspec.yaml'),
        'test_package',
      );
      writePubspecFile(
        filename('p2/p/pubspec.yaml'),
        'test_package2',
      );

      final List<String> assets = <String>['a/foo', 'a/v/foo'];
      writeAssets(filename('p/p/lib/'), assets);
      writeAssets(filename('p2/p/lib/'), assets);

      const String expectedAssetManifest =
          '{"packages/test_package/a/foo":'
          '["packages/test_package/a/foo","packages/test_package/a/v/foo"],'
          '"packages/test_package2/a/foo":'
          '["packages/test_package2/a/foo","packages/test_package2/a/v/foo"]}';

      await buildAndVerifyAssets(
        assets,
        <String>['test_package', 'test_package2'],
        expectedAssetManifest,
      );
    });

    testUsingContext('One asset is bundled when the app depends on a package, listing in its pubspec an asset from another package', () async {
      establishFlutterRoot();
      writePubspecFile(
        filename('pubspec.yaml'),
        'test',
      );
      writePackagesFile('test_package:p/p/lib/\ntest_package2:p2/p/lib/');
      writePubspecFile(
        filename('p/p/pubspec.yaml'),
        'test_package',
        assets: <String>['packages/test_package2/a/foo'],
      );
      writePubspecFile(
        filename('p2/p/pubspec.yaml'),
        'test_package2',
      );

      final List<String> assets = <String>['a/foo', 'a/v/foo'];
      writeAssets(filename('p2/p/lib/'), assets);

      const String expectedAssetManifest =
          '{"packages/test_package2/a/foo":'
          '["packages/test_package2/a/foo","packages/test_package2/a/v/foo"]}';

      await buildAndVerifyAssets(
        assets,
        <String>['test_package2'],
        expectedAssetManifest,
      );
    });
  });

  testUsingContext('Asset paths can contain URL reserved characters', () async {
    establishFlutterRoot();

    writePubspecFile(filename('pubspec.yaml'), 'test');
    writePackagesFile('test_package:p/p/lib/');

    final List<String> assets = <String>['a/foo', 'a/foo[x]'];
    writePubspecFile(
      filename('p/p/pubspec.yaml'),
      'test_package',
      assets: assets,
    );

    writeAssets(filename('p/p/'), assets);
    const String expectedAssetManifest =
        '{"packages/test_package/a/foo":["packages/test_package/a/foo"],'
        '"packages/test_package/a/foo%5Bx%5D":["packages/test_package/a/foo%5Bx%5D"]}';

    await buildAndVerifyAssets(
      assets,
      <String>['test_package'],
      expectedAssetManifest,
    );
  });

  group('AssetBundle assets from scanned paths', () {
    testUsingContext(
        'Two assets are bundled when scanning their directory', () async {
      establishFlutterRoot();

      writePubspecFile(filename('pubspec.yaml'), 'test');
      writePackagesFile('test_package:p/p/lib/');

      final List<String> assetsOnDisk = <String>['a/foo', 'a/bar'];
      final List<String> assetsOnManifest = <String>['a/'];

      writePubspecFile(
        filename('p/p/pubspec.yaml'),
        'test_package',
        assets: assetsOnManifest,
      );

      writeAssets(filename('p/p/'), assetsOnDisk);
      const String expectedAssetManifest =
          '{"packages/test_package/a/bar":["packages/test_package/a/bar"],'
          '"packages/test_package/a/foo":["packages/test_package/a/foo"]}';

      await buildAndVerifyAssets(
        assetsOnDisk,
        <String>['test_package'],
        expectedAssetManifest,
      );
    });

    testUsingContext(
        'Two assets are bundled when listing one and scanning second directory', () async {
      establishFlutterRoot();

      writePubspecFile(filename('pubspec.yaml'), 'test');
      writePackagesFile('test_package:p/p/lib/');

      final List<String> assetsOnDisk = <String>['a/foo', 'abc/bar'];
      final List<String> assetOnManifest = <String>['a/foo', 'abc/'];

      writePubspecFile(
        filename('p/p/pubspec.yaml'),
        'test_package',
        assets: assetOnManifest,
      );

      writeAssets(filename('p/p/'), assetsOnDisk);
      const String expectedAssetManifest =
          '{"packages/test_package/abc/bar":["packages/test_package/abc/bar"],'
          '"packages/test_package/a/foo":["packages/test_package/a/foo"]}';

      await buildAndVerifyAssets(
        assetsOnDisk,
        <String>['test_package'],
        expectedAssetManifest,
      );
    });

    testUsingContext(
        'One asset is bundled with variant, scanning wrong directory', () async {
      establishFlutterRoot();

      writePubspecFile(filename('pubspec.yaml'), 'test');
      writePackagesFile('test_package:p/p/lib/');

      final List<String> assetsOnDisk = <String>['a/foo','a/b/foo','a/bar'];
      final List<String> assetOnManifest = <String>['a','a/bar']; // can't list 'a' as asset, should be 'a/'

      writePubspecFile(
        filename('p/p/pubspec.yaml'),
        'test_package',
        assets: assetOnManifest,
      );

      writeAssets(filename('p/p/'), assetsOnDisk);

      final AssetBundle bundle = AssetBundleFactory.instance.createBundle();
      await bundle.build(manifestPath: filename('pubspec.yaml'));
      assert(bundle.entries['AssetManifest.json'] == null,'Invalid pubspec.yaml should not generate AssetManifest.json'  );
    });
  });

  group('AssetBundle assets from scanned paths with MemoryFileSystem', () {
    String readSchemaPath(FileSystem fs) {
      final String schemaPath = buildSchemaPath(fs);
      final File schemaFile = fs.file(schemaPath);

      return schemaFile.readAsStringSync();
    }

    void writeSchema(String schema, FileSystem filesystem) {
      final String schemaPath = buildSchemaPath(filesystem);
      final File schemaFile = filesystem.file(schemaPath);

      final Directory schemaDir = filesystem.directory(
          buildSchemaDir(filesystem));

      schemaDir.createSync(recursive: true);
      schemaFile.writeAsStringSync(schema);
    }

    void testUsingContextAndFs(String description, dynamic testMethod(),) {
      final FileSystem windowsFs = new MemoryFileSystem(style: FileSystemStyle.windows);
      final FileSystem posixFs = new MemoryFileSystem(style: FileSystemStyle.posix);

      const String _kFlutterRoot = '/flutter/flutter';
      establishFlutterRoot();

      final String schema = readSchemaPath(fs);

      testUsingContext('$description - on windows FS', () async {
        establishFlutterRoot();
        writeSchema(schema, windowsFs);
        await testMethod();
      }, overrides: <Type, Generator>{
        FileSystem: () => windowsFs,
        Platform: () =>
        new FakePlatform(
            environment: <String, String>{'FLUTTER_ROOT': _kFlutterRoot,},
            operatingSystem: 'windows')
      });

      testUsingContext('$description - on posix FS', () async {
        establishFlutterRoot();
        writeSchema(schema, posixFs);
        await testMethod();
      }, overrides: <Type, Generator>{
        FileSystem: () => posixFs,
        Platform: () =>
        new FakePlatform(
            environment: <String, String>{ 'FLUTTER_ROOT': _kFlutterRoot,},
            operatingSystem: 'linux')
      });

      testUsingContext('$description - on original FS', () async {
        establishFlutterRoot();
        await testMethod();
      });
    }

    testUsingContextAndFs('One asset is bundled with variant, scanning directory', () async {
      establishFlutterRoot();

      writePubspecFile(filename('pubspec.yaml'), 'test');
      writePackagesFile('test_package:p/p/lib/');

      final List<String> assetsOnDisk = <String>['a/foo','a/b/foo'];
      final List<String> assetOnManifest = <String>['a/',];

      writePubspecFile(
        filename('p/p/pubspec.yaml'),
        'test_package',
        assets: assetOnManifest,
      );

      writeAssets(filename('p/p/'), assetsOnDisk);
      const String expectedAssetManifest =
          '{"packages/test_package/a/foo":["packages/test_package/a/foo","packages/test_package/a/b/foo"]}';

      await buildAndVerifyAssets(
        assetsOnDisk,
        <String>['test_package'],
        expectedAssetManifest,
      );
    });

    testUsingContextAndFs('No asset is bundled with variant, no assets or directories are listed', () async {
      establishFlutterRoot();

      writePubspecFile(filename('pubspec.yaml'), 'test');
      writePackagesFile('test_package:p/p/lib/');

      final List<String> assetsOnDisk = <String>['a/foo', 'a/b/foo'];
      final List<String> assetOnManifest = <String>[];

      writePubspecFile(
        filename('p/p/pubspec.yaml'),
        'test_package',
        assets: assetOnManifest,
      );

      writeAssets(filename('p/p/'), assetsOnDisk);
      const String expectedAssetManifest = '{}';

      await buildAndVerifyAssets(
        assetOnManifest,
        <String>['test_package'],
        expectedAssetManifest,
      );
    });

    testUsingContextAndFs('Expect error generating manifest, wrong non-existing directory is listed', () async {
      establishFlutterRoot();

      writePubspecFile(filename('pubspec.yaml'), 'test');
      writePackagesFile('test_package:p/p/lib/');

      final List<String> assetOnManifest = <String>['c/'];

      writePubspecFile(
        filename('p/p/pubspec.yaml'),
        'test_package',
        assets: assetOnManifest,
      );

      try {
        await buildAndVerifyAssets(
          assetOnManifest,
          <String>['test_package'],
          null,
        );

        final Function watchdog = () async {
          assert(false, 'Code failed to detect missing directory. Test failed.');
        };
        watchdog();
      } catch (e) {
        // Test successful
      }
    });

  });
}
