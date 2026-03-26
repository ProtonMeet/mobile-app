import 'package:meet/managers/secure.storage/secure.storage.interface.dart';

class SecureStorageMemory implements SecureStorageInterface {
  final Map<String, String> _storage = {};

  @override
  Future<void> write(String key, String value) async {
    _storage[key] = value;
  }

  @override
  Future<String> read(String key) async {
    return _storage[key] ?? '';
  }

  @override
  Future<bool> containsKey(String key) async {
    return _storage.containsKey(key);
  }

  @override
  Future<void> delete(String key) async {
    _storage.remove(key);
  }

  @override
  Future<void> deleteAll() async {
    _storage.clear();
  }
}
