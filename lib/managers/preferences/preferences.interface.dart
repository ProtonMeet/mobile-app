abstract class PreferencesInterface {
  Future<void> write(String key, dynamic value);
  Future<dynamic> read(String key);
  Future<void> delete(String key);
  Future<void> deleteAll({required bool clearAll});
  Map<dynamic, dynamic> toMap();

  void addPerInstallKey(String key);
}
