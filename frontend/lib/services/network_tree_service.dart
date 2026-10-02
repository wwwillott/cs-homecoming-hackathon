import 'dart:convert';

import 'package:http/http.dart' as http;

import '../models/contact.dart';
import '../models/network_tree.dart';

class NetworkTreeService {
  NetworkTreeService({
    String apiUrl = const String.fromEnvironment(
      'ORBIT_API_URL',
      defaultValue: 'http://127.0.0.1:8000',
    ),
    String? Function()? userId,
    http.Client? client,
  })  : _apiUri = Uri.parse(apiUrl),
        _userId = userId,
        _client = client ?? http.Client();

  final Uri _apiUri;
  final String? Function()? _userId;
  final http.Client _client;

  Map<String, String> get _headers {
    final id = _userId?.call();
    return {
      'Content-Type': 'application/json',
      if (id != null && id.isNotEmpty) 'X-User-Id': id,
    };
  }

  Uri _api(String path, [Map<String, String>? query]) => _apiUri.replace(
        path: path,
        queryParameters: query,
        fragment: null,
      );

  Future<List<NetworkTree>> listTrees() async {
    final response = await _client.get(_api('/api/network-trees'), headers: _headers);
    final body = _decode(response);
    if (response.statusCode >= 300) {
      throw StateError(_error(body, response.statusCode));
    }
    return [
      for (final item in body as List)
        NetworkTree.fromJson(Map<String, dynamic>.from(item as Map)),
    ];
  }

  Future<NetworkShareCode> exportTree(String treeId) async {
    final response = await _client.post(
      _api('/api/network-trees/$treeId/export'),
      headers: _headers,
    );
    final body = Map<String, dynamic>.from(_decode(response) as Map);
    if (response.statusCode >= 300) {
      throw StateError(_error(body, response.statusCode));
    }
    return NetworkShareCode(
      token: body['share_token'] as String,
      expiresAt: DateTime.tryParse(body['expires_at'] as String? ?? ''),
    );
  }

  Future<NetworkTree> importTree(String shareToken) async {
    final response = await _client.post(
      _api('/api/network-trees/import'),
      headers: _headers,
      body: jsonEncode({'share_token': shareToken.trim().toUpperCase()}),
    );
    final body = Map<String, dynamic>.from(_decode(response) as Map);
    if (response.statusCode >= 300) {
      throw StateError(_error(body, response.statusCode));
    }
    return NetworkTree.fromJson(body);
  }

  Future<List<Contact>> loadTreeContacts(String treeId) async {
    final response = await _client.get(
      _api('/api/network', {'tree_id': treeId}),
      headers: _headers,
    );
    final body = Map<String, dynamic>.from(_decode(response) as Map);
    if (response.statusCode >= 300) {
      throw StateError(_error(body, response.statusCode));
    }
    return contactsFromNetwork(body, readOnly: true);
  }

  Future<void> syncContact(Contact contact) async {
    final response = await _client.post(
      _api('/api/people'),
      headers: _headers,
      body: jsonEncode({
        'name': contact.name,
        'alpha_score': contact.strength,
        'how_met': contact.metAt.isEmpty ? null : contact.metAt,
        'where_met': contact.location.isEmpty ? contact.metAt : contact.location,
        'met_at': contact.metOn?.toIso8601String(),
        'contact_methods': [
          if (contact.email.isNotEmpty)
            {'kind': 'email', 'value': contact.email, 'is_primary': true},
          if (contact.phone.isNotEmpty) {'kind': 'phone', 'value': contact.phone},
          if (contact.linkedin.isNotEmpty)
            {'kind': 'other', 'value': contact.linkedin, 'label': 'LinkedIn'},
        ],
        'organizations': [
          if (contact.company.isNotEmpty)
            {
              'name': contact.company,
              'kind': 'company',
              'role': contact.title.isEmpty ? null : contact.title,
            },
        ],
        'interests': [...contact.tags, ...contact.skills],
      }),
    );
    if (response.statusCode >= 300) {
      throw StateError(_error(_decode(response), response.statusCode));
    }
  }

  Future<List<Map<String, dynamic>>> introductionSuggestions({
    String mode = 'same_tree',
    String? treeId,
  }) async {
    final response = await _client.get(
      _api('/api/network/introduction-suggestions', {
        'mode': mode,
        if (treeId != null) 'tree_id': treeId,
      }),
      headers: _headers,
    );
    final body = _decode(response);
    if (response.statusCode >= 300) {
      throw StateError(_error(body, response.statusCode));
    }
    return [
      for (final item in body as List) Map<String, dynamic>.from(item as Map),
    ];
  }

  static List<Contact> contactsFromNetwork(Map<String, dynamic> body, {required bool readOnly}) {
    final nodes = [
      for (final item in body['nodes'] as List? ?? const [])
        Map<String, dynamic>.from(item as Map),
    ];
    final edges = [
      for (final item in body['edges'] as List? ?? const [])
        Map<String, dynamic>.from(item as Map),
    ];
    final links = <String, List<String>>{};
    for (final edge in edges) {
      final a = edge['person_a_id'] as String?;
      final b = edge['person_b_id'] as String?;
      if (a == null || b == null) continue;
      links.putIfAbsent(a, () => []).add(b);
      links.putIfAbsent(b, () => []).add(a);
    }
    return [
      for (final node in nodes)
        if (node['is_self'] != true) contactFromPerson(node, links[node['id'] as String] ?? const [], readOnly: readOnly),
    ];
  }

  static Contact contactFromPerson(
    Map<String, dynamic> person,
    List<String> connectedIds, {
    required bool readOnly,
  }) {
    final organizations = [
      for (final item in person['organizations'] as List? ?? const [])
        Map<String, dynamic>.from(item as Map),
    ];
    final contacts = [
      for (final item in person['contact_methods'] as List? ?? const [])
        Map<String, dynamic>.from(item as Map),
    ];
    final notes = [
      for (final item in person['notes'] as List? ?? const [])
        Map<String, dynamic>.from(item as Map),
    ];
    String method(String kind) =>
        contacts.where((item) => item['kind'] == kind).map((item) => item['value'] as String? ?? '').firstWhere(
              (value) => value.isNotEmpty,
              orElse: () => '',
            );
    final org = organizations.isEmpty ? null : organizations.first;
    final noteText = notes
        .map((item) => [item['general_note'], item['next_steps'], item['how_to_serve']])
        .expand((item) => item)
        .whereType<String>()
        .where((item) => item.isNotEmpty)
        .join('\n');
    return Contact(
      id: person['id'] as String,
      name: person['name'] as String? ?? '',
      title: org?['role'] as String? ?? '',
      company: org?['name'] as String? ?? '',
      email: method('email'),
      phone: method('phone'),
      linkedin: contacts
          .where((item) => (item['label'] as String? ?? '').toLowerCase().contains('linkedin'))
          .map((item) => item['value'] as String? ?? '')
          .firstWhere((value) => value.isNotEmpty, orElse: () => ''),
      location: person['where_met'] as String? ?? '',
      metAt: person['how_met'] as String? ?? person['where_met'] as String? ?? '',
      strength: _strengthFrom(person['alpha_score']),
      tags: [
        for (final item in person['interests'] as List? ?? const []) item.toString(),
      ],
      notes: noteText,
      connectedIds: connectedIds,
      readOnly: readOnly,
      createdAt: DateTime.tryParse(person['created_at'] as String? ?? ''),
    );
  }

  static int _strengthFrom(Object? value) {
    num? parsed;
    if (value is num) {
      parsed = value;
    } else if (value is String) {
      parsed = num.tryParse(value);
    }
    return (parsed?.round() ?? 5).clamp(1, 10);
  }

  Object? _decode(http.Response response) {
    if (response.body.isEmpty) return {};
    return jsonDecode(response.body);
  }

  String _error(Object? body, int status) {
    if (body is Map && body['detail'] is String) return body['detail'] as String;
    return 'Request failed with status $status.';
  }

  void dispose() => _client.close();
}
