import 'dart:convert';

import 'package:http/http.dart' as http;

import '../models/contact.dart';
import '../models/user_mode.dart';

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
}

class ApiAssistantService implements AssistantService {
  ApiAssistantService({
    required this.fallback,
    String apiUrl = const String.fromEnvironment(
      'ORBIT_API_URL',
      defaultValue: 'http://127.0.0.1:8000',
    ),
    http.Client? client,
  })  : _apiUri = Uri.parse(apiUrl),
        _client = client ?? http.Client();

  final AssistantService fallback;
  final Uri _apiUri;
  final http.Client _client;

  @override
  Future<List<String>> suggestedPrompts() => fallback.suggestedPrompts();

  @override
  Stream<String> reply(List<ChatMessage> history) async* {
    final question = history.lastWhere((message) => message.role == ChatRole.user).text;
    try {
      final response = await _client.post(
        _apiUri.replace(path: '/api/network/ask', query: null, fragment: null),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'question': question}),
      );
      if (response.statusCode >= 200 && response.statusCode < 300) {
        final body = Map<String, dynamic>.from(jsonDecode(response.body) as Map);
        final citations = body['citations'] as List? ?? const [];
        if (citations.isNotEmpty) {
          yield body['answer'] as String? ?? '';
          return;
        }
      }
    } catch (_) {
      // Keep the local assistant available while the backend is offline.
    }
    yield* fallback.reply(history);
  }
}

/// Stand-in used until the backend endpoint is wired up. Answers from the
/// local contact list so the chat feels real in demos.
class MockAssistantService implements AssistantService {
  MockAssistantService({required this.contacts, required this.mode, required this.userName});

  final List<Contact> Function() contacts;
  final UserMode Function() mode;
  final String Function() userName;

  @override
  Future<List<String>> suggestedPrompts() async {
    await Future<void>.delayed(const Duration(milliseconds: 700));
    final list = contacts();
    if (list.isEmpty) {
      return const [
        'Where can I meet people in my field this month?',
        'What should I say when I introduce myself at an event?',
        'How do I follow someone up on LinkedIn without being awkward?',
      ];
    }
    final hub = _hub(list);
    final company = _top(list.where((c) => c.canRefer).map((c) => c.company));
    final event = _top(list.map((c) => c.metAt));
    final recent = [...list.where((c) => c.metOn != null)]..sort((a, b) => b.metOn!.compareTo(a.metOn!));
    if (mode() == UserMode.recruiter) {
      return [
        'Who are my top candidates right now?',
        if (event != null) 'Who stood out at $event?',
        if (hub != null) 'Who could ${hub.firstName} introduce me to?',
        'Where should I go to meet more strong candidates?',
      ];
    }
    return [
      if (hub != null) 'Who could ${hub.firstName} introduce me to?',
      if (company != null) 'How do I get a referral at $company?',
      if (recent.isNotEmpty) 'Help me write a message to ${recent.first.firstName}',
      'Which events should I go to next?',
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
    if (list.isEmpty) {
      return 'Your network is empty right now, so start with places where conversations happen naturally. '
          'Look for a meetup or hackathon on Luma, Meetup, or Devpost this week, and record a quick recap after each conversation. '
          'Once a few people are in Orbit, I can suggest who to ask for intros.';
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
    if (q.contains('message') || q.contains('write') || q.contains('email')) {
      final where = c.metAt.isEmpty ? 'recently' : 'at ${c.metAt}';
      final hook = c.conversationHooks.isEmpty ? '' : ' ${c.conversationHooks.split('.').first.trim()}.';
      return 'Here\'s a short message you could send ${c.firstName}:\n\n'
          '"Hi ${c.firstName}, it was great meeting you $where. I really enjoyed hearing about your work'
          '${c.company.isEmpty ? '' : ' at ${c.company}'}. I\'d love to keep in touch and grab a quick coffee sometime if you\'re open to it."\n\n'
          'Something personal you noted that could make it warmer:$hook'
          '${hook.isEmpty ? ' nothing yet, so keep it simple.' : ''}';
    }
    final friends = _neighbors(list, c)..sort((a, b) => b.strength.compareTo(a.strength));
    if (friends.isEmpty) {
      return '${c.name} isn\'t connected to anyone else in your network yet. '
          'Ask who else they\'d recommend you meet, then add those people so I can map the links.';
    }
    final names = friends.take(5).map((f) => '• ${f.name}${f.roleLine.isEmpty ? '' : ', ${f.roleLine}'}').join('\n');
    return '${c.firstName} knows ${friends.length} ${friends.length == 1 ? 'person' : 'people'} in your network:\n\n$names\n\n'
        '${c.canRefer ? '${c.firstName} has offered to help, so a direct ask is fair. ' : ''}'
        'Ask for one specific intro rather than "anyone you know". It\'s much easier to say yes to.';
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

  String _overview(List<Contact> list) {
    final strongest = [...list]..sort((a, b) => b.strength.compareTo(a.strength));
    final hub = _hub(list);
    final name = userName().isEmpty ? '' : ', ${userName()}';
    return 'Here\'s a quick read on your network$name. You have ${list.length} people. '
        'Your strongest ties are ${strongest.take(3).map((c) => c.firstName).join(', ')}.'
        '${hub == null ? '' : ' ${hub.firstName} is your biggest connector and knows ${_neighbors(list, hub).length} people you know.'}\n\n'
        'Ask me about a person, a company, or an event and I\'ll pull up what you know.';
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
