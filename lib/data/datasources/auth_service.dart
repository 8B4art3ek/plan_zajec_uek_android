// lib/data/datasources/auth_service.dart

import 'package:flutter_secure_storage/flutter_secure_storage.dart';

class AuthService {
  static const _usernameKey = 'uek_username';
  static const _passwordKey = 'uek_password';

  final FlutterSecureStorage _storage;

  AuthService({FlutterSecureStorage? storage})
      : _storage = storage ??
            const FlutterSecureStorage(
              aOptions: AndroidOptions(encryptedSharedPreferences: true),
            );

  Future<void> saveCredentials(String username, String password) async {
    await _storage.write(key: _usernameKey, value: username);
    await _storage.write(key: _passwordKey, value: password);
  }

  Future<Credentials?> getCredentials() async {
    final username = await _storage.read(key: _usernameKey);
    final password = await _storage.read(key: _passwordKey);
    if (username == null || password == null) return null;
    return Credentials(username: username, password: password);
  }

  Future<bool> hasCredentials() async {
    final creds = await getCredentials();
    return creds != null;
  }

  Future<void> clearCredentials() async {
    await _storage.delete(key: _usernameKey);
    await _storage.delete(key: _passwordKey);
  }
}

class Credentials {
  final String username;
  final String password;

  const Credentials({required this.username, required this.password});
}
