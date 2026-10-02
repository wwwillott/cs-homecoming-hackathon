import 'package:flutter_test/flutter_test.dart';
import 'package:orbit/services/recap_service.dart';

void main() {
  test('recap draft preserves the streaming session and suggested fields', () {
    final draft = RecapDraft.fromJson({
      'sessionId': 'session-123',
      'transcript': 'We discussed robotics.',
      'aiFields': ['name', 'company'],
      'contact': {
        'id': 'draft-session-123',
        'name': 'Maya',
        'company': 'Robotics Club',
      },
    });

    expect(draft.sessionId, 'session-123');
    expect(draft.transcript, 'We discussed robotics.');
    expect(draft.contact.name, 'Maya');
    expect(draft.contact.company, 'Robotics Club');
    expect(draft.aiFields, containsAll(['name', 'company']));
  });
}
