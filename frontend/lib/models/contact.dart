import 'package:flutter/material.dart';

enum ContactCategory {
  recruiter('Recruiter', Icons.badge_outlined),
  mentor('Mentor', Icons.school_outlined),
  engineer('Engineer', Icons.code),
  founder('Founder', Icons.rocket_launch_outlined),
  peer('Peer', Icons.people_outline),
  alumni('Alumni', Icons.account_balance_outlined),
  candidate('Candidate', Icons.person_search_outlined),
  other('Other', Icons.circle_outlined);

  const ContactCategory(this.label, this.icon);
  final String label;
  final IconData icon;

  static ContactCategory fromName(String? name) => ContactCategory.values
      .firstWhere((c) => c.name == name, orElse: () => ContactCategory.other);
}

enum InteractionType {
  met('Met in person', Icons.handshake_outlined),
  call('Call', Icons.call_outlined),
  coffee('Coffee chat', Icons.local_cafe_outlined),
  email('Email', Icons.mail_outline),
  message('Message', Icons.chat_bubble_outline),
  interview('Interview', Icons.event_available_outlined),
  voiceRecap('Voice recap', Icons.graphic_eq);

  const InteractionType(this.label, this.icon);
  final String label;
  final IconData icon;

  static InteractionType fromName(String? name) => InteractionType.values
      .firstWhere((c) => c.name == name, orElse: () => InteractionType.met);
}

@immutable
class Interaction {
  const Interaction({required this.date, required this.type, this.note = ''});

  final DateTime date;
  final InteractionType type;
  final String note;

  Map<String, dynamic> toJson() => {
        'date': date.toIso8601String(),
        'type': type.name,
        'note': note,
      };

  factory Interaction.fromJson(Map<String, dynamic> json) => Interaction(
        date: DateTime.tryParse(json['date'] as String? ?? '') ?? DateTime.now(),
        type: InteractionType.fromName(json['type'] as String?),
        note: json['note'] as String? ?? '',
      );
}

/// A person in the user's network. JSON shape is the contract with the backend.
@immutable
class Contact {
  const Contact({
    required this.id,
    required this.name,
    this.title = '',
    this.company = '',
    this.email = '',
    this.phone = '',
    this.linkedin = '',
    this.location = '',
    this.metAt = '',
    this.metOn,
    this.introducedById,
    this.strength = 5,
    this.category = ContactCategory.other,
    this.tags = const [],
    this.notes = '',
    this.conversationHooks = '',
    this.howTheyCanHelp = '',
    this.howICanHelp = '',
    this.aiSummary = '',
    this.school = '',
    this.skills = const [],
    this.canRefer = false,
    this.lastContacted,
    this.interactions = const [],
    this.connectedIds = const [],
    this.favorite = false,
    this.createdAt,
    this.readOnly = false,
  });

  final String id;
  final String name;
  final String title;
  final String company;
  final String email;
  final String phone;
  final String linkedin;
  final String location;

  /// Event or place where you met, e.g. "BYU Career Fair".
  final String metAt;
  final DateTime? metOn;
  final String? introducedById;

  /// 1-10. Connection strength for job seekers, impression for recruiters.
  final int strength;
  final ContactCategory category;
  final List<String> tags;
  final String notes;

  /// Personal details worth remembering (kids, hobbies, hometown).
  final String conversationHooks;
  final String howTheyCanHelp;
  final String howICanHelp;

  /// Summary produced by the voice recap backend.
  final String aiSummary;

  final String school;
  final List<String> skills;
  final bool canRefer;
  final DateTime? lastContacted;
  final List<Interaction> interactions;

  /// Other contacts this person knows (drawn as edges in the graph).
  final List<String> connectedIds;
  final bool favorite;
  final DateTime? createdAt;
  final bool readOnly;

  String get initials {
    final parts = name.trim().split(RegExp(r'\s+')).where((p) => p.isNotEmpty);
    if (parts.isEmpty) return '?';
    if (parts.length == 1) return parts.first[0].toUpperCase();
    return (parts.first[0] + parts.last[0]).toUpperCase();
  }

  String get firstName => name.trim().split(RegExp(r'\s+')).first;

  String get roleLine {
    if (title.isNotEmpty && company.isNotEmpty) return '$title · $company';
    return title.isNotEmpty ? title : company;
  }

  int get daysSinceContact {
    final last = lastContacted ?? metOn ?? createdAt;
    if (last == null) return 0;
    return DateTime.now().difference(last).inDays;
  }

  Contact copyWith({
    String? id,
    String? name,
    String? title,
    String? company,
    String? email,
    String? phone,
    String? linkedin,
    String? location,
    String? metAt,
    DateTime? metOn,
    String? introducedById,
    bool clearIntroducedBy = false,
    int? strength,
    ContactCategory? category,
    List<String>? tags,
    String? notes,
    String? conversationHooks,
    String? howTheyCanHelp,
    String? howICanHelp,
    String? aiSummary,
    String? school,
    List<String>? skills,
    bool? canRefer,
    DateTime? lastContacted,
    List<Interaction>? interactions,
    List<String>? connectedIds,
    bool? favorite,
    DateTime? createdAt,
    bool? readOnly,
  }) {
    return Contact(
      id: id ?? this.id,
      name: name ?? this.name,
      title: title ?? this.title,
      company: company ?? this.company,
      email: email ?? this.email,
      phone: phone ?? this.phone,
      linkedin: linkedin ?? this.linkedin,
      location: location ?? this.location,
      metAt: metAt ?? this.metAt,
      metOn: metOn ?? this.metOn,
      introducedById: clearIntroducedBy ? null : (introducedById ?? this.introducedById),
      strength: strength ?? this.strength,
      category: category ?? this.category,
      tags: tags ?? this.tags,
      notes: notes ?? this.notes,
      conversationHooks: conversationHooks ?? this.conversationHooks,
      howTheyCanHelp: howTheyCanHelp ?? this.howTheyCanHelp,
      howICanHelp: howICanHelp ?? this.howICanHelp,
      aiSummary: aiSummary ?? this.aiSummary,
      school: school ?? this.school,
      skills: skills ?? this.skills,
      canRefer: canRefer ?? this.canRefer,
      lastContacted: lastContacted ?? this.lastContacted,
      interactions: interactions ?? this.interactions,
      connectedIds: connectedIds ?? this.connectedIds,
      favorite: favorite ?? this.favorite,
      createdAt: createdAt ?? this.createdAt,
      readOnly: readOnly ?? this.readOnly,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'title': title,
        'company': company,
        'email': email,
        'phone': phone,
        'linkedin': linkedin,
        'location': location,
        'metAt': metAt,
        'metOn': metOn?.toIso8601String(),
        'introducedById': introducedById,
        'strength': strength,
        'category': category.name,
        'tags': tags,
        'notes': notes,
        'conversationHooks': conversationHooks,
        'howTheyCanHelp': howTheyCanHelp,
        'howICanHelp': howICanHelp,
        'aiSummary': aiSummary,
        'school': school,
        'skills': skills,
        'canRefer': canRefer,
        'lastContacted': lastContacted?.toIso8601String(),
        'interactions': interactions.map((i) => i.toJson()).toList(),
        'connectedIds': connectedIds,
        'favorite': favorite,
        'createdAt': createdAt?.toIso8601String(),
      };

  factory Contact.fromJson(Map<String, dynamic> json) {
    DateTime? date(String key) => DateTime.tryParse(json[key] as String? ?? '');
    List<String> strings(String key) =>
        (json[key] as List?)?.map((e) => e.toString()).toList() ?? const [];
    return Contact(
      id: json['id'] as String,
      name: json['name'] as String? ?? '',
      title: json['title'] as String? ?? '',
      company: json['company'] as String? ?? '',
      email: json['email'] as String? ?? '',
      phone: json['phone'] as String? ?? '',
      linkedin: json['linkedin'] as String? ?? '',
      location: json['location'] as String? ?? '',
      metAt: json['metAt'] as String? ?? '',
      metOn: date('metOn'),
      introducedById: json['introducedById'] as String?,
      strength: _readStrength(json['strength']),
      category: ContactCategory.fromName(json['category'] as String?),
      tags: strings('tags'),
      notes: json['notes'] as String? ?? '',
      conversationHooks: json['conversationHooks'] as String? ?? '',
      howTheyCanHelp: json['howTheyCanHelp'] as String? ?? '',
      howICanHelp: json['howICanHelp'] as String? ?? '',
      aiSummary: json['aiSummary'] as String? ?? '',
      school: json['school'] as String? ?? '',
      skills: strings('skills'),
      canRefer: json['canRefer'] as bool? ?? false,
      lastContacted: date('lastContacted'),
      interactions: (json['interactions'] as List?)
              ?.map((e) => Interaction.fromJson(Map<String, dynamic>.from(e as Map)))
              .toList() ??
          const [],
      connectedIds: strings('connectedIds'),
      favorite: json['favorite'] as bool? ?? false,
      createdAt: date('createdAt'),
      readOnly: json['readOnly'] as bool? ?? false,
    );
  }

  static int _readStrength(Object? value) {
    num? parsed;
    if (value is num) {
      parsed = value;
    } else if (value is String) {
      parsed = num.tryParse(value);
    }
    return (parsed?.round() ?? 5).clamp(1, 10);
  }
}
