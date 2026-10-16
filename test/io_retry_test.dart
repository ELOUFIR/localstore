import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:localstore/localstore.dart';
// ignore: implementation_imports
import 'package:localstore/src/utils/io.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final tempDir = Directory.systemTemp.createTempSync('localstore_io_test');
  const MethodChannel channel =
      MethodChannel('plugins.flutter.io/path_provider');
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(channel, (MethodCall methodCall) async {
    return tempDir.path;
  });

  tearDownAll(() {
    if (tempDir.existsSync()) tempDir.deleteSync(recursive: true);
  });

  final db = Localstore.instance;
  final utils = Utils.instance;

  File fileOf(DocumentRef doc) => File('${tempDir.path}${doc.path}');
  Map<String, dynamic> onDisk(DocumentRef doc) =>
      json.decode(fileOf(doc).readAsStringSync()) as Map<String, dynamic>;

  test('set then get gives the same data', () async {
    final data = {'uid': 'a1', 'name': 'Round trip', 'list': [1, 2, 3]};
    final doc = db.collection('roundtrip').doc('a1');
    await utils.set(data, doc.path);
    expect(await utils.get(doc.path), data);
    expect(onDisk(doc), data);
  });

  test('two sets without await keep the second data', () async {
    final doc = db.collection('twosets').doc('d');
    final first = utils.set({'v': 1}, doc.path);
    final second = utils.set({'v': 2}, doc.path);
    await Future.wait([first!, second!]);
    expect(onDisk(doc), {'v': 2});
  });

  test('a retry of an old write does not overwrite a newer write', () async {
    final doc = db.collection('retry').doc('d');
    await utils.set({'v': 0}, doc.path);

    // Another handle holds the lock : the first write fails and waits to retry
    final blocker = fileOf(doc).openSync(mode: FileMode.append);
    blocker.lockSync();
    final old = utils.set({'v': 1}, doc.path);
    await Future.delayed(const Duration(milliseconds: 20));
    blocker.unlockSync();
    blocker.closeSync();

    await utils.set({'v': 2}, doc.path);
    await old;
    await Future.delayed(const Duration(milliseconds: 400));
    expect(onDisk(doc), {'v': 2});
  }, skip: !Platform.isWindows ? 'lock of the same process only conflicts on Windows' : false);

  test('a write still locked after the retries throws and leaves the data',
      () async {
    final doc = db.collection('locked').doc('d');
    await utils.set({'v': 0}, doc.path);

    final blocker = fileOf(doc).openSync(mode: FileMode.append);
    blocker.lockSync();
    try {
      await expectLater(
          utils.set({'v': 1}, doc.path), throwsA(isA<FileSystemException>()));
    } finally {
      blocker.unlockSync();
      blocker.closeSync();
    }
    expect(onDisk(doc), {'v': 0});

    // The handle of the failed write is closed : a new write works
    await utils.set({'v': 2}, doc.path);
    expect(onDisk(doc), {'v': 2});
  }, skip: !Platform.isWindows ? 'lock of the same process only conflicts on Windows' : false);

  test('get of a collection gives every doc and leaves no handle open',
      () async {
    final col = db.collection('three');
    for (final id in ['a', 'b', 'c']) {
      await utils.set({'id': id}, col.doc(id).path);
    }
    final all = await utils.get(col.path, true);
    expect(all!.length, 3);
    expect(all.values.map((e) => e['id']).toSet(), {'a', 'b', 'c'});

    final dir = Directory('${tempDir.path}${col.path}');
    expect(() => dir.deleteSync(recursive: true), returnsNormally);
    expect(dir.existsSync(), isFalse);
  });
}
