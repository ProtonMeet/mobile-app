import 'package:hive/hive.dart';
import 'package:meet/constants/constants.dart';
import 'package:meet/helper/logger.dart' as l;
import 'package:meet/managers/preferences/preferences.keys.dart';

import 'preferences.interface.dart';

class HivePreferenceImpl implements PreferencesInterface {
  late Box storage;

  HivePreferenceImpl();

  Future<void> init() async {
    storage = await Hive.openBox(hiveFilesName);
    l.logger.d("hive storage.path: ${storage.path}");
  }

  @override
  Map<dynamic, dynamic> toMap() {
    return storage.toMap();
  }

  @override
  Future<void> delete(String key) async {
    await storage.delete(key);
  }

  @override
  Future<void> deleteAll({required bool clearAll}) async {
    if (clearAll) {
      await storage.clear();
    } else {
      /// remove all that are not per-install
      final keys = storage.keys.toList();
      for (final key in keys) {
        if (appPerInstallPreferenceKeys.contains(key)) {
          continue;
        }
        await storage.delete(key);
      }
    }
  }

  @override
  Future read(String key) async {
    return await storage.get(key);
  }

  @override
  Future<void> write(String key, value) async {
    await storage.put(key, value);
  }

  @override
  void addPerInstallKey(String key) {
    appPerInstallPreferenceKeys.add(key);
  }
}
