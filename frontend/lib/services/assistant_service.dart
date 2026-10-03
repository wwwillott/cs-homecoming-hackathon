import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import '../models/contact.dart';
import '../models/user_mode.dart';
import 'api_config.dart';

enum ChatRole { user, assistant }

class ChatMessage {
  const ChatMessage({required this.role, required this.text, required this.sentAt});

  final ChatRole role;
  final String text;
  final DateTime sentAt;

  Map<String, dynamic> toJson() => {'role': role.name, 'text': text, 'sentAt': sentAt.toIso8601String()};
}

/// Boundary for the networking assistant backend.
abstract class AssistantService {
  /// Prompts tailored to what the backend knows about the user.
  Future<List<String>> suggestedPrompts();

  /// Streams the assistant's reply to the last user message in [history].
  Stream<String> reply(List<ChatMessage> history);

  /// Drops the current conversation so the next message starts a new session.
  void reset();
}

/// Uses the on-device assistant while demo mode is on, and the Agents API otherwise.
class ModeAssistantService implements AssistantService {
  ModeAssistantService({required this.demoMode, required this.live, required this.demo});

  final bool Function() demoMode;
  final AssistantService live;
  final AssistantService demo;

  AssistantService get _active => demoMode() ? demo : live;

  @override
  Future<List<String>> suggestedPrompts() => _active.suggestedPrompts();

  @override
  Stream<String> reply(List<ChatMessage> history) => _active.reply(history);

  @override
  void reset() {
    live.reset();
    demo.reset();
  }
}

class ApiAssistantService implements AssistantService {
  ApiAssistantService({
    required this.networkContext,
    required this.place,
    String apiUrl = apiBaseUrl,
    String? Function()? sharedLabel,
    http.Client? client,
  })  : _apiUri = Uri.parse(apiUrl),
        _sharedLabel = sharedLabel,
        _client = client ?? http.Client();

  final String Function() networkContext;
  final Map<String, String> Function() place;
  final Uri _apiUri;
  final String? Function()? _sharedLabel;
  final http.Client _client;
  String? _sessionId;

  Uri _uri(String path) => _apiUri.replace(path: path, query: null, fragment: null);

  @override
  Future<List<String>> suggestedPrompts() async {
    final label = _sharedLabel?.call();
    if (label != null && label.isNotEmpty) {
      return _withAlumni([
        'Who in $label\'s tree works in robotics?',
        'Who should I introduce across our trees?',
        'What overlap do I have with $label\'s network?',
      ]);
    }
    try {
      final response = await _client.get(_uri('/api/assistant/prompts'));
      if (response.statusCode >= 200 && response.statusCode < 300) {
        final body = Map<String, dynamic>.from(jsonDecode(response.body) as Map);
        final prompts = [
          for (final item in body['prompts'] as List? ?? const [])
            if (item is String && item.trim().isNotEmpty) item,
        ];
        return _withAlumni([
          eventsPromptChip,
          ...prompts.where((prompt) => !prompt.toLowerCase().startsWith('find events')),
        ]);
      }
    } catch (_) {
      // The chip still shows so a failed backend is visible when they send it.
    }
    return _withAlumni(const [eventsPromptChip]);
  }

  @override
  Stream<String> reply(List<ChatMessage> history) async* {
    final request = http.Request('POST', _uri('/api/assistant/chat'));
    request.headers['Content-Type'] = 'application/json';
    request.headers['Accept'] = 'text/event-stream';
    request.body = jsonEncode({
      'session_id': _sessionId,
      'context': networkContext(),
      'place': place(),
      'messages': [
        for (final message in history) {'role': message.role.name, 'text': message.text},
      ],
    });
    final response = await _client.send(request);
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw StateError('Assistant request failed (${response.statusCode})');
    }

    var buffer = '';
    var received = false;
    await for (final chunk in response.stream.transform(utf8.decoder)) {
      buffer = (buffer + chunk).replaceAll('\r\n', '\n');
      while (buffer.contains('\n\n')) {
        final split = buffer.indexOf('\n\n');
        final raw = buffer.substring(0, split);
        buffer = buffer.substring(split + 2);
        for (final line in raw.split('\n')) {
          if (!line.startsWith('data:')) continue;
          final payload = line.substring(5).trim();
          if (payload.isEmpty) continue;
          final data = jsonDecode(payload);
          if (data is! Map) continue;
          final sessionId = data['session_id'];
          if (sessionId is String && sessionId.isNotEmpty) _sessionId = sessionId;
          final error = data['error'];
          if (error != null) throw StateError(error.toString());
          if (data['done'] == true) {
            if (!received) throw StateError('The assistant returned an empty reply.');
            return;
          }
          final delta = data['delta'];
          if (delta is String && delta.isNotEmpty) {
            received = true;
            yield delta;
          }
        }
      }
    }
    if (!received) throw StateError('The assistant returned an empty reply.');
  }

  @override
  void reset() {
    final sessionId = _sessionId;
    _sessionId = null;
    if (sessionId == null || sessionId.isEmpty) return;
    unawaited(_client.delete(_uri('/api/assistant/sessions/$sessionId')).then((_) {}, onError: (_) {}));
  }
}

const eventsPromptChip = 'Find events near Provo, Utah';
const alumniPromptChip = 'Find alumni from my university in a company or field';

List<String> _withAlumni(List<String> prompts) {
  if (prompts.any((prompt) => prompt.toLowerCase().startsWith('find alumni'))) return prompts;
  return [...prompts, alumniPromptChip];
}

/// A short snapshot of the local network, sent with each live Ask Spruce turn.
///
/// When [sharedContacts] is non-empty, own and shared people are listed in
/// separate sections so the model can answer about the attached tree.
String networkBrief({
  required List<Contact> contacts,
  required String userName,
  List<Contact> sharedContacts = const [],
  String? sharedLabel,
}) {
  final who = userName.trim().isEmpty ? 'The user' : userName.trim();
  if (contacts.isEmpty && sharedContacts.isEmpty) {
    return '$who has not saved any contacts yet.';
  }

  final ownBudget = sharedContacts.isEmpty ? 24 : 14;
  final sharedBudget = 14;
  final buffer = StringBuffer();

  if (contacts.isEmpty) {
    buffer.writeln('$who has no people in their own tree yet.');
  } else {
    buffer.writeln('$who\'s network (${contacts.length} people):');
    buffer.write(_contactBriefLines(contacts.take(ownBudget)));
    if (contacts.length > ownBudget) {
      buffer.writeln('- …and ${contacts.length - ownBudget} more in their own tree.');
    }
  }

  if (sharedContacts.isNotEmpty) {
    final label = (sharedLabel == null || sharedLabel.trim().isEmpty)
        ? 'the shared tree'
        : sharedLabel.trim();
    buffer.writeln();
    buffer.writeln(
      'Shared mode is on. A read-only copy of $label\'s network is attached '
      '(${sharedContacts.length} people). Answer questions about these people too, '
      'and say which tree someone belongs to when it matters:',
    );
    buffer.write(_contactBriefLines(sharedContacts.take(sharedBudget), shared: true));
    if (sharedContacts.length > sharedBudget) {
      buffer.writeln(
        '- …and ${sharedContacts.length - sharedBudget} more in $label\'s tree.',
      );
    }
  }

  return buffer.toString().trimRight();
}

String _contactBriefLines(Iterable<Contact> contacts, {bool shared = false}) {
  final lines = <String>[];
  for (final contact in contacts) {
    final role = switch ((contact.title.isNotEmpty, contact.company.isNotEmpty)) {
      (true, true) => '${contact.title} at ${contact.company}',
      (true, false) => contact.title,
      (false, true) => contact.company,
      _ => '',
    };
    final tags = [
      if (contact.tags.isNotEmpty) contact.tags.take(3).join(', '),
      if (contact.skills.isNotEmpty) contact.skills.take(2).join(', '),
    ].where((item) => item.isNotEmpty).join('; ');
    final met = contact.metAt.isEmpty ? '' : ' Met at ${contact.metAt}.';
    final notes = contact.notes.trim().isEmpty
        ? ''
        : ' Notes: ${contact.notes.trim().split('\n').first}';
    final hooks = contact.conversationHooks.trim().isEmpty
        ? ''
        : ' Hooks: ${contact.conversationHooks.trim().split('\n').first}';
    final marker = shared ? ' [shared tree]' : '';
    final detail = [
      if (role.isNotEmpty) role,
      if (tags.isNotEmpty) tags,
    ].join('. ');
    lines.add(
      '- ${contact.name}$marker'
      '${detail.isEmpty ? '' : ', $detail.'}'
      '$met$notes$hooks',
    );
  }
  return '${lines.join('\n')}\n';
}

/// A few apps for the Ask Spruce chip. A smaller tree gets places to meet
/// people. Past 30 people, the picks shift toward helping the network you have.
/// The list is shuffled so each tap is a different handful.
String spruceAppSuggestion({required int people, required bool recruiter}) {
  const meet = [
    (name: 'Luma', why: 'Follow a local calendar and show up where the same people return.'),
    (name: 'Meetup', why: 'Pick one group and go more than once. Regulars become real connections.'),
    (name: 'Devpost', why: 'A hackathon lets you work beside people instead of only swapping names.'),
    (name: 'Handshake', why: 'Career fairs and info sessions put you in the room with peers and employers.'),
    (name: 'Partiful', why: 'Smaller invites are where a lot of campus and community gatherings happen.'),
    (name: 'Discord', why: 'Join one community you care about and actually talk there this week.'),
  ];
  const meetCandidates = [
    (name: 'Handshake', why: 'Host or attend an info session and meet students who fit the roles.'),
    (name: 'Devpost', why: 'Judge or sponsor a hackathon and see how people build.'),
    (name: 'Major League Hacking', why: 'The student hackathon season is a direct way to meet builders.'),
    (name: 'Luma', why: 'A small technical meetup brings the right candidates to you.'),
    (name: 'Meetup', why: 'A recurring local group is an easy place to meet people more than once.'),
  ];
  const help = [
    (name: 'ADPList', why: 'Offer a short mentoring chat to someone a step behind you.'),
    (name: 'LinkedIn', why: 'Introduce two people who should know each other, and say why.'),
    (name: 'Toastmasters', why: 'A weekly club makes the intros and talks you give more useful.'),
    (name: 'GitHub', why: 'Help on a project someone you know cares about.'),
    (name: 'Fishbowl', why: 'Answer a question in your field from what you have already learned.'),
    (name: 'Peerlist', why: 'Share what you are building so people in your tree can collaborate.'),
  ];
  const helpCandidates = [
    (name: 'LinkedIn', why: 'Make a specific intro between a candidate and someone who can help them.'),
    (name: 'ADPList', why: 'Offer office hours so people you have met can ask for advice.'),
    (name: 'Fishbowl', why: 'Answer candid questions about roles and teams you actually know.'),
    (name: 'Discord', why: 'Stay in a community you recruit from and help people there, not only pitch them.'),
  ];

  final established = people > 30;
  final pool = switch ((established, recruiter)) {
    (false, false) => meet,
    (false, true) => meetCandidates,
    (true, false) => help,
    (true, true) => helpCandidates,
  };
  final picked = [...pool]..shuffle();
  final lines = picked.take(3).map((app) => '• ${app.name}: ${app.why}').join('\n');
  final count = '$people ${people == 1 ? 'person' : 'people'}';
  final intro = established
      ? 'Your tree has $count, so you can start helping the people you already know.'
      : 'Your tree has $count, so the useful next step is still meeting new people.';
  return '$intro\n\n$lines\n\nPick one and use it this week.';
}

/// Stand-in used until the backend endpoint is wired up. Answers from the
/// local contact list so the chat feels real in demos.
class MockAssistantService implements AssistantService {
  MockAssistantService({required this.contacts, required this.mode, required this.userName});

  final List<Contact> Function() contacts;
  final UserMode Function() mode;
  final String Function() userName;

  @override
  void reset() {}

  @override
  Future<List<String>> suggestedPrompts() async {
    await Future<void>.delayed(const Duration(milliseconds: 700));
    final list = contacts();
    if (list.isEmpty) {
      return _prompts(const [
        'Where can I meet people in my field this month?',
        'What should I say when I introduce myself at an event?',
        'How do I follow someone up on LinkedIn without being awkward?',
      ]);
    }
    final hub = _hub(list);
    final company = _top(list.where((c) => c.canRefer).map((c) => c.company));
    final event = _top(list.map((c) => c.metAt));
    final recent = [...list.where((c) => c.metOn != null)]..sort((a, b) => b.metOn!.compareTo(a.metOn!));
    if (mode() == UserMode.recruiter) {
      return _prompts([
        'Who are my top candidates right now?',
        if (event != null) 'Who stood out at $event?',
        if (hub != null) 'Who could ${hub.firstName} introduce me to?',
        'Where should I go to meet more strong candidates?',
      ]);
    }
    return _prompts([
      if (hub != null) 'Who could ${hub.firstName} introduce me to?',
      if (company != null) 'How do I get a referral at $company?',
      if (recent.isNotEmpty) 'Help me write a message to ${recent.first.firstName}',
      'Which events should I go to next?',
    ]);
  }

  List<String> _prompts(List<String> prompts) {
    return [
      eventsPromptChip,
      alumniPromptChip,
      ...prompts.where((prompt) => prompt != eventsPromptChip && prompt != alumniPromptChip),
    ];
  }

  @override
  Stream<String> reply(List<ChatMessage> history) async* {
    final question = history.lastWhere((m) => m.role == ChatRole.user).text;
    final answer = _answer(question);
    await Future<void>.delayed(const Duration(milliseconds: 650));
    final words = answer.split(' ');
    for (var i = 0; i < words.length; i++) {
      yield i == 0 ? words[i] : ' ${words[i]}';
      await Future<void>.delayed(const Duration(milliseconds: 22));
    }
  }

  String _answer(String question) {
    final q = question.toLowerCase();
    final list = contacts();
    if (RegExp(r'\bapps?\b').hasMatch(q)) return _apps(list);
    if (list.isEmpty) {
      return 'Your network is empty right now, so start with places where conversations happen naturally. '
          'Look for a meetup or hackathon on Luma, Meetup, or Devpost this week, and record a quick recap after each conversation. '
          'Once a few people are in Spruce, I can suggest who to ask for intros.';
    }

    final named = _mentioned(list, q);
    if (named != null) return _aboutPerson(list, named, q);

    for (final company in list.map((c) => c.company).where((c) => c.isNotEmpty).toSet()) {
      if (q.contains(company.toLowerCase())) {
        return _aboutCompany(list, company);
      }
    }
    for (final event in list.map((c) => c.metAt).where((e) => e.isNotEmpty).toSet()) {
      if (q.contains(event.toLowerCase())) return _aboutEvent(list, event);
    }
    if (q.contains('candidate')) return _candidates(list);
    if (q.contains('event') || q.contains('meet') || q.contains('where') || q.contains('go to')) {
      return _events(list);
    }
    return _overview(list);
  }

  String _aboutPerson(List<Contact> list, Contact c, String q) {
    final treeNote = c.readOnly
        ? ' ${c.firstName} is from the shared tree currently attached to your view.'
        : '';
    if (q.contains('message') || q.contains('write') || q.contains('email')) {
      final where = c.metAt.isEmpty ? 'recently' : 'at ${c.metAt}';
      final hook = c.conversationHooks.isEmpty ? '' : ' ${c.conversationHooks.split('.').first.trim()}.';
      return 'Here\'s a short message you could send ${c.firstName}:\n\n'
          '"Hi ${c.firstName}, it was great meeting you $where. I really enjoyed hearing about your work'
          '${c.company.isEmpty ? '' : ' at ${c.company}'}. I\'d love to keep in touch and grab a quick coffee sometime if you\'re open to it."\n\n'
          'Something personal you noted that could make it warmer:$hook'
          '${hook.isEmpty ? ' nothing yet, so keep it simple.' : ''}'
          '$treeNote';
    }
    final friends = _neighbors(list, c)..sort((a, b) => b.strength.compareTo(a.strength));
    if (friends.isEmpty) {
      return '${c.name} isn\'t connected to anyone else in the visible network yet.'
          '$treeNote '
          'Ask who else they\'d recommend you meet, then add those people so I can map the links.';
    }
    final names = friends.take(5).map((f) => '• ${f.name}${f.roleLine.isEmpty ? '' : ', ${f.roleLine}'}').join('\n');
    return '${c.firstName} knows ${friends.length} ${friends.length == 1 ? 'person' : 'people'} nearby:\n\n$names\n\n'
        '${c.canRefer ? '${c.firstName} has offered to help, so a direct ask is fair. ' : ''}'
        'Ask for one specific intro rather than "anyone you know". It\'s much easier to say yes to.'
        '$treeNote';
  }

  String _aboutCompany(List<Contact> list, String company) {
    final people = list.where((c) => c.company == company).toList()..sort((a, b) => b.strength.compareTo(a.strength));
    final referrers = people.where((c) => c.canRefer).toList();
    final lines = people.take(5).map((p) => '• ${p.name}, ${p.title} (strength ${p.strength})').join('\n');
    final best = referrers.isNotEmpty ? referrers.first : people.first;
    return 'You know ${people.length} ${people.length == 1 ? 'person' : 'people'} at $company:\n\n$lines\n\n'
        '${best.firstName} is your best first ask${referrers.contains(best) ? ' since they already offered to refer you' : ''}. '
        'Send the job link, a two-line note on why you fit, and your resume so it takes them a minute to submit.';
  }

  String _aboutEvent(List<Contact> list, String event) {
    final people = list.where((c) => c.metAt == event).toList()..sort((a, b) => b.strength.compareTo(a.strength));
    final lines = people.take(5).map((p) => '• ${p.name}, ${p.roleLine} (${p.strength}/10)').join('\n');
    return 'You met ${people.length} ${people.length == 1 ? 'person' : 'people'} at $event. The ones who stood out most:\n\n$lines';
  }

  String _candidates(List<Contact> list) {
    final people = list.where((c) => c.category == ContactCategory.candidate).toList()
      ..sort((a, b) => b.strength.compareTo(a.strength));
    if (people.isEmpty) {
      return 'No one is marked as a Candidate yet. Set their relationship to Candidate and they\'ll show up here.';
    }
    final lines = people.take(5).map((p) => '• ${p.name}, ${p.roleLine} (${p.strength}/10)').join('\n');
    return 'Your strongest candidates right now:\n\n$lines';
  }

  String _events(List<Contact> list) {
    final counts = <String, int>{};
    for (final c in list) {
      if (c.metAt.isNotEmpty) counts[c.metAt] = (counts[c.metAt] ?? 0) + 1;
    }
    final top = (counts.entries.toList()..sort((a, b) => b.value.compareTo(a.value))).take(3);
    final lines = top.map((e) => '• ${e.key}: ${e.value} ${e.value == 1 ? 'person' : 'people'}').join('\n');
    return 'Your best places to meet people so far:\n\n$lines\n\n'
        'Look for more events like these on Luma and Meetup, and check Devpost for hackathons. '
        'They\'re where most of your strongest ties came from.';
  }

  String _apps(List<Contact> list) =>
      spruceAppSuggestion(people: list.length, recruiter: mode() == UserMode.recruiter);

  String _overview(List<Contact> list) {
    final strongest = [...list]..sort((a, b) => b.strength.compareTo(a.strength));
    final hub = _hub(list);
    final shared = list.where((c) => c.readOnly).toList();
    final name = userName().isEmpty ? '' : ', ${userName()}';
    final sharedLine = shared.isEmpty
        ? ''
        : ' ${shared.length} ${shared.length == 1 ? 'person is' : 'people are'} from the attached shared tree'
            '${shared.isEmpty ? '' : ' (for example ${shared.first.name})'}.';
    return 'Here\'s a quick read on your network$name. You can see ${list.length} people right now.'
        '$sharedLine '
        'Your strongest ties are ${strongest.take(3).map((c) => c.firstName).join(', ')}.'
        '${hub == null ? '' : ' ${hub.firstName} is your biggest connector and knows ${_neighbors(list, hub).length} people you know.'}\n\n'
        'Ask me about a person, company, or who to introduce across the trees.';
  }

  Contact? _mentioned(List<Contact> list, String q) {
    for (final c in list) {
      if (q.contains(c.name.toLowerCase())) return c;
    }
    final words = RegExp(r"[a-z']+").allMatches(q).map((m) => m.group(0)!.replaceAll("'s", '')).toSet();
    for (final c in list) {
      if (words.contains(c.firstName.toLowerCase())) return c;
    }
    return null;
  }

  List<Contact> _neighbors(List<Contact> list, Contact c) {
    final ids = <String>{...c.connectedIds, ?c.introducedById};
    for (final o in list) {
      if (o.connectedIds.contains(c.id) || o.introducedById == c.id) {
        ids.add(o.id);
      }
    }
    ids.remove(c.id);
    return list.where((o) => ids.contains(o.id)).toList();
  }

  Contact? _hub(List<Contact> list) {
    Contact? best;
    var bestCount = 0;
    for (final c in list) {
      final n = _neighbors(list, c).length;
      if (n > bestCount) {
        best = c;
        bestCount = n;
      }
    }
    return bestCount >= 2 ? best : null;
  }

  String? _top(Iterable<String> values) {
    final counts = <String, int>{};
    for (final v in values) {
      if (v.isNotEmpty) counts[v] = (counts[v] ?? 0) + 1;
    }
    if (counts.isEmpty) return null;
    final best = counts.entries.reduce((a, b) => a.value >= b.value ? a : b);
    return best.value >= 2 ? best.key : null;
  }
}
