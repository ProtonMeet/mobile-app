import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:meet/constants/constants.dart';
import 'package:meet/managers/preferences/hive.preference.impl.dart';
import 'package:meet/managers/preferences/preferences.keys.dart';

import '../../helper.dart';

void main() {
  late Directory tempDir;
  late HivePreferenceImpl prefs;

  setUpAll(() async {
    tempDir = await Directory.systemTemp.createTemp('meet_hive_prefs_test');
    Hive.init(tempDir.path);
  });

  setUp(() async {
    prefs = HivePreferenceImpl();
    await prefs.init();
  });

  tearDown(() async {
    await prefs.deleteAll(clearAll: true);
    await Hive.close();
    Hive.init(tempDir.path);
  });

  tearDownAll(() async {
    await Hive.deleteBoxFromDisk(hiveFilesName);
    await tempDir.delete(recursive: true);
  });

  testUnit('deleteAll(clearAll: true) clears all keys', () async {
    await prefs.write('a', 1);
    await prefs.write('keep_key', 2);

    await prefs.deleteAll(clearAll: true);

    expect(await prefs.read('a'), isNull);
    expect(await prefs.read('keep_key'), isNull);
  });

  testUnit('deleteAll(clearAll: false) preserves per-install keys', () async {
    prefs.addPerInstallKey('keep_key');
    prefs.addPerInstallKey('keep_key_2');
    await prefs.write('keep_key', 100);
    await prefs.write('keep_key_2', 200);
    await prefs.write('temp_key', 'value');

    await prefs.deleteAll(clearAll: false);

    expect(await prefs.read('keep_key'), 100);
    expect(await prefs.read('keep_key_2'), 200);
    expect(await prefs.read('temp_key'), isNull);
  });

  testUnit('write and read persist values', () async {
    await prefs.write('test_key', 'test_value');
    await prefs.write('int_key', 42);
    await prefs.write('bool_key', true);

    expect(await prefs.read('test_key'), 'test_value');
    expect(await prefs.read('int_key'), 42);
    expect(await prefs.read('bool_key'), isTrue);
  });

  testUnit('delete removes key', () async {
    await prefs.write('test_key', 'value');
    expect(await prefs.read('test_key'), 'value');

    await prefs.delete('test_key');

    expect(await prefs.read('test_key'), isNull);
  });

  testUnit('toMap returns all stored values', () async {
    await prefs.write('key1', 'value1');
    await prefs.write('key2', 42);

    final map = prefs.toMap();

    expect(map['key1'], 'value1');
    expect(map['key2'], 42);
  });

  testUnit('addPerInstallKey adds to set', () {
    expect(appPerInstallPreferenceKeys.contains('new_key'), isFalse);

    prefs.addPerInstallKey('new_key');

    expect(appPerInstallPreferenceKeys.contains('new_key'), isTrue);
  });

  testUnit('read returns null for non-existent key', () async {
    expect(await prefs.read('non_existent'), isNull);
  });
}
