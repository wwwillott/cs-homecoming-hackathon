class NetworkTree {
  const NetworkTree({
    required this.id,
    required this.label,
    required this.isPrimary,
    required this.isReadOnly,
    this.attributedUserId,
    this.attributedUsername,
  });

  final String id;
  final String label;
  final bool isPrimary;
  final bool isReadOnly;
  final String? attributedUserId;
  final String? attributedUsername;

  factory NetworkTree.fromJson(Map<String, dynamic> json) => NetworkTree(
        id: json['id'] as String,
        label: json['label'] as String? ?? 'Network',
        isPrimary: json['is_primary'] as bool? ?? false,
        isReadOnly: json['is_read_only'] as bool? ?? false,
        attributedUserId: json['attributed_user_id'] as String?,
        attributedUsername: json['attributed_username'] as String?,
      );

  String get shortLabel {
    final username = attributedUsername?.trim();
    if (username != null && username.isNotEmpty) return username;
    final trimmed = label.trim();
    if (trimmed.endsWith("'s network") && trimmed.length > 10) {
      return trimmed.substring(0, trimmed.length - 10).trim();
    }
    return trimmed;
  }
}

class NetworkShareCode {
  const NetworkShareCode({required this.token, this.expiresAt});

  final String token;
  final DateTime? expiresAt;
}
