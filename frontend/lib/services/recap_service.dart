import 'dart:typed_data';

import '../models/contact.dart';

enum RecapKind {
  recap('My recap', 'Talk through the meeting after it happens'),
  conversation('Conversation', 'Record the conversation itself (with permission)');

  const RecapKind(this.label, this.description);
  final String label;
  final String description;
}

/// What the backend returns after summarizing a recording. The user always
/// reviews [contact] before it is added.
class RecapDraft {
  const RecapDraft({
    required this.contact,
    required this.aiFields,
    required this.transcript,
  });

  final Contact contact;

  /// Names of [Contact] JSON fields that were filled in by the summarizer.
  final Set<String> aiFields;
  final String transcript;

  factory RecapDraft.fromJson(Map<String, dynamic> json) {
    final contactJson = Map<String, dynamic>.from(json['contact'] as Map);
    contactJson['id'] ??= 'draft-${DateTime.now().microsecondsSinceEpoch}';
    bool filled(Object? v) => v != null && v != '' && v != false && !(v is List && v.isEmpty);
    final explicit = (json['aiFields'] as List?)?.map((e) => e.toString()).toSet();
    return RecapDraft(
      contact: Contact.fromJson(contactJson),
      aiFields: explicit ??
          {
            for (final e in contactJson.entries)
              if (e.key != 'id' && filled(e.value)) e.key,
          },
      transcript: json['transcript'] as String? ?? '',
    );
  }
}

/// Boundary for the voice recap backend.
abstract class RecapService {
  Future<RecapDraft> summarize({
    required Uint8List audio,
    required String mimeType,
    required RecapKind kind,
  });
}

/// Stand-in used until the backend endpoint is wired up.
class MockRecapService implements RecapService {
  static const demoTranscript =
      'Just walked out of the Silicon Slopes AI mixer. Met Jasmine Ortiz, she\'s a staff '
      'machine learning engineer at Recursion in Salt Lake. Super sharp. She works on their '
      'speech and lab-notes models and said they\'re hiring two new-grad ML engineers in '
      'January. She went to BYU too, grad of 2019, and offered to refer me if I send over my '
      'resume. We talked a lot about running models on-device. She\'s into trail running and '
      'just did the Wasatch 100 as a pacer. Her email is jasmine.ortiz@recursion.example. '
      'Priya introduced us. I should send her my resume and the hackathon demo by Friday. '
      'Honestly one of the best conversations of the night, I\'d say an eight.';

  @override
  Future<RecapDraft> summarize({
    required Uint8List audio,
    required String mimeType,
    required RecapKind kind,
  }) async {
    await Future<void>.delayed(const Duration(milliseconds: 2600));
    final now = DateTime.now();
    return RecapDraft(
      transcript: demoTranscript,
      aiFields: const {
        'name', 'title', 'company', 'email', 'location', 'metAt', 'metOn', 'introducedById',
        'strength', 'category', 'tags', 'notes', 'conversationHooks', 'howTheyCanHelp',
        'aiSummary', 'school', 'canRefer',
      },
      contact: Contact(
        id: 'draft-${now.microsecondsSinceEpoch}',
        name: 'Jasmine Ortiz',
        title: 'Staff Machine Learning Engineer',
        company: 'Recursion',
        email: 'jasmine.ortiz@recursion.example',
        location: 'Salt Lake City, UT',
        metAt: 'Silicon Slopes AI Mixer',
        metOn: now,
        introducedById: 'c03',
        strength: 8,
        category: ContactCategory.engineer,
        tags: const ['AI', 'BYU alum', 'Referral'],
        notes: 'Works on speech and lab-notes models. Deep interest in on-device inference.',
        conversationHooks: 'Trail runner. Recently paced at the Wasatch 100.',
        howTheyCanHelp: 'Offered a referral for new-grad ML engineer roles opening in January.',
        aiSummary:
            'Jasmine is a Staff ML Engineer at Recursion working on speech and lab-notes models. '
            'Recursion is hiring two new-grad ML engineers in January and she offered to refer you. '
            'You connected over on-device inference, trail running, and BYU.',
        school: 'BYU · 2019',
        canRefer: true,
        lastContacted: now,
        interactions: [
          Interaction(date: now, type: InteractionType.voiceRecap, note: 'Created from a voice recap.'),
        ],
        createdAt: now,
      ),
    );
  }
}
