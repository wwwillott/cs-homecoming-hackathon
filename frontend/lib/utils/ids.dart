import 'dart:convert';

final _uuidPattern = RegExp(
  r'^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$',
);

bool isUuid(String? value) =>
    value != null && value.isNotEmpty && _uuidPattern.hasMatch(value);

/// Stable UUID-shaped id for offline auth fallbacks.
String localUserIdFor(String username) {
  final input = utf8.encode('spruce.local.user:${username.trim().toLowerCase()}');
  final out = List<int>.filled(16, 0);
  for (var i = 0; i < input.length; i++) {
    out[i % 16] ^= input[i];
    out[(i * 5) % 16] ^= (input[i] + i) & 0xff;
  }
  out[6] = (out[6] & 0x0f) | 0x40;
  out[8] = (out[8] & 0x3f) | 0x80;
  String hex(int byte) => byte.toRadixString(16).padLeft(2, '0');
  final h = out.map(hex).join();
  return '${h.substring(0, 8)}-${h.substring(8, 12)}-${h.substring(12, 16)}-'
      '${h.substring(16, 20)}-${h.substring(20)}';
}
