import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../models/contact.dart';

/// Storage boundary for contacts. Swap [LocalContactRepository] for an
/// HTTP-backed implementation once the backend API is available.
abstract class ContactRepository {
  Future<List<Contact>> loadAll();
  Future<void> saveAll(List<Contact> contacts);
}

class LocalContactRepository implements ContactRepository {
  LocalContactRepository({this._userId});

  final String? Function()? _userId;

  String get _key {
    final id = _userId?.call();
    return id == null || id.isEmpty ? 'orbit.contacts.guest' : 'orbit.contacts.$id';
  }

  @override
  Future<List<Contact>> loadAll() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_key);
    if (raw == null) return [];
    try {
      final list = jsonDecode(raw) as List;
      return list.map((e) => Contact.fromJson(Map<String, dynamic>.from(e as Map))).toList();
    } catch (_) {
      return [];
    }
  }

  @override
  Future<void> saveAll(List<Contact> contacts) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_key, jsonEncode(contacts.map((c) => c.toJson()).toList()));
  }
}
