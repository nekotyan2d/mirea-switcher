import 'dart:convert';
import 'package:mirea_switcher/data/models/account.dart';
import 'package:shared_preferences/shared_preferences.dart';

class AccountRepository {
  static const _key = 'accounts';
  final SharedPreferences _prefs;

  AccountRepository(this._prefs);

  List<Account> getAll() {
    final raw = _prefs.getString(_key) ?? '[]';
    final list = jsonDecode(raw) as List<dynamic>;
    return list.map((e) => Account.fromJson(e as Map<String, dynamic>)).toList();
  }

  Future<void> save(List<Account> accounts) async {
    final encoded = jsonEncode(accounts.map((a) => a.toJson()).toList());
    await _prefs.setString(_key, encoded);
  }

  Future<bool> addIfAbsent(String name, String token) async {
    final accounts = getAll();
    if(accounts.any((a) => a.token == token)) return false;
    accounts.add(Account(name: name, token: token));
    await save(accounts);
    return true;
  }

  Future<bool> remove(String token) async {
    final accounts = getAll()..removeWhere((a) => a.token == token);
    await save(accounts);
    return true;
  }
}