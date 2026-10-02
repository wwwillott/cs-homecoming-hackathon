import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../data/contact_repository.dart';
import '../data/demo_data.dart';
import '../graph/graph_options.dart';
import '../models/contact.dart';
import '../models/user_mode.dart';
import '../services/assistant_service.dart';
import '../services/recap_service.dart';

enum AppTab { home, people, network, grow }

enum SortBy {
  recent('Recently added'),
  strength('Strongest first'),
  name('Name'),
  company('Company');

  const SortBy(this.label);
  final String label;
}

class AppState extends ChangeNotifier {
  AppState({ContactRepository? repository, RecapService? recapService, AssistantService? assistant})
      : repository = repository ?? LocalContactRepository(),
        recapService = recapService ?? MockRecapService(),
        _customAssistant = assistant;

  final ContactRepository repository;
  final RecapService recapService;
  final AssistantService? _customAssistant;
  late final AssistantService assistant = _customAssistant ??
      MockAssistantService(contacts: () => _contacts, mode: () => mode, userName: () => userName);
  final navigatorKey = GlobalKey<NavigatorState>();

  static const _kOnboarded = 'orbit.onboarded';
  static const _kMode = 'orbit.mode';
  static const _kTheme = 'orbit.theme';
  static const _kName = 'orbit.userName';

  bool loaded = false;
  bool onboarded = false;
  UserMode mode = UserMode.seeker;
  ThemeMode themeMode = ThemeMode.system;
  String userName = '';

  List<Contact> _contacts = [];
  Map<String, Contact> _byId = {};

  List<Contact> get contacts => _contacts;
  Contact? byId(String? id) => id == null ? null : _byId[id];

  AppTab tab = AppTab.home;
  String? selectedContactId;

  ColorBy colorBy = ColorBy.strength;
  SizeBy sizeBy = SizeBy.strength;
  bool showPeerLinks = true;
  String? graphFocusId;
  bool assistantOpen = false;

  Future<void> init() async {
    final prefs = await SharedPreferences.getInstance();
    onboarded = prefs.getBool(_kOnboarded) ?? false;
    mode = UserMode.fromName(prefs.getString(_kMode));
    themeMode = ThemeMode.values.firstWhere(
      (m) => m.name == prefs.getString(_kTheme),
      orElse: () => ThemeMode.system,
    );
    userName = prefs.getString(_kName) ?? '';
    _setContacts(await repository.loadAll());
    loaded = true;
    notifyListeners();
  }

  void _setContacts(List<Contact> list) {
    _contacts = list;
    _byId = {for (final c in list) c.id: c};
  }

  Future<void> _persist() => repository.saveAll(_contacts);

  Future<void> completeOnboarding({
    required UserMode mode,
    required bool withDemoData,
    String name = '',
  }) async {
    this.mode = mode;
    userName = name.trim();
    onboarded = true;
    if (withDemoData) {
      _setContacts(buildDemoContacts());
    } else if (_contacts.isEmpty) {
      _setContacts([]);
    }
    tab = AppTab.home;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_kOnboarded, true);
    await prefs.setString(_kMode, mode.name);
    await prefs.setString(_kName, userName);
    await _persist();
  }

  Future<void> resetApp() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.clear();
    onboarded = false;
    selectedContactId = null;
    graphFocusId = null;
    _setContacts([]);
    tab = AppTab.home;
    notifyListeners();
  }

  void loadDemoData() {
    _setContacts(buildDemoContacts());
    selectedContactId = null;
    graphFocusId = null;
    notifyListeners();
    _persist();
  }

  void setMode(UserMode value) {
    if (mode == value) return;
    mode = value;
    notifyListeners();
    SharedPreferences.getInstance().then((p) => p.setString(_kMode, value.name));
  }

  void setThemeMode(ThemeMode value) {
    themeMode = value;
    notifyListeners();
    SharedPreferences.getInstance().then((p) => p.setString(_kTheme, value.name));
  }

  void setTab(AppTab value) {
    if (tab == value) return;
    tab = value;
    assistantOpen = false;
    notifyListeners();
  }

  void setAssistantOpen(bool value) {
    if (assistantOpen == value) return;
    assistantOpen = value;
    notifyListeners();
  }

  void selectContact(String? id) {
    selectedContactId = id;
    notifyListeners();
  }

  void setColorBy(ColorBy value) {
    colorBy = value;
    notifyListeners();
  }

  void setSizeBy(SizeBy value) {
    sizeBy = value;
    notifyListeners();
  }

  void setShowPeerLinks(bool value) {
    showPeerLinks = value;
    notifyListeners();
  }

  void setGraphFocus(String? id) {
    if (graphFocusId == id) return;
    graphFocusId = id;
    notifyListeners();
  }

  Contact upsert(Contact contact) {
    final index = _contacts.indexWhere((c) => c.id == contact.id);
    var saved = contact;
    if (index == -1) {
      if (saved.id.startsWith('draft-') || saved.id.isEmpty) {
        saved = saved.copyWith(id: 'c${DateTime.now().microsecondsSinceEpoch}');
      }
      saved = saved.copyWith(createdAt: saved.createdAt ?? DateTime.now());
      _setContacts([saved, ..._contacts]);
    } else {
      final next = [..._contacts]..[index] = saved;
      _setContacts(next);
    }
    notifyListeners();
    _persist();
    return saved;
  }

  void delete(String id) {
    _setContacts(_contacts
        .where((c) => c.id != id)
        .map((c) => c.connectedIds.contains(id) || c.introducedById == id
            ? c.copyWith(
                connectedIds: c.connectedIds.where((x) => x != id).toList(),
                clearIntroducedBy: c.introducedById == id,
              )
            : c)
        .toList());
    if (selectedContactId == id) selectedContactId = null;
    if (graphFocusId == id) graphFocusId = null;
    notifyListeners();
    _persist();
  }

  void toggleFavorite(String id) {
    final c = byId(id);
    if (c != null) upsert(c.copyWith(favorite: !c.favorite));
  }

  void logInteraction(String id, Interaction interaction) {
    final c = byId(id);
    if (c == null) return;
    upsert(c.copyWith(
      interactions: [interaction, ...c.interactions],
      lastContacted: interaction.date,
    ));
  }

  /// Contacts linked to [id] in either direction.
  Set<String> neighborsOf(String id) {
    final c = byId(id);
    final out = <String>{};
    if (c == null) return out;
    out.addAll(c.connectedIds.where(_byId.containsKey));
    if (c.introducedById != null && _byId.containsKey(c.introducedById)) out.add(c.introducedById!);
    for (final other in _contacts) {
      if (other.connectedIds.contains(id) || other.introducedById == id) out.add(other.id);
    }
    out.remove(id);
    return out;
  }

  List<Contact> sorted(Iterable<Contact> list, SortBy sort) {
    final out = list.toList();
    switch (sort) {
      case SortBy.recent:
        out.sort((a, b) => (b.createdAt ?? DateTime(0)).compareTo(a.createdAt ?? DateTime(0)));
      case SortBy.strength:
        out.sort((a, b) => b.strength.compareTo(a.strength));
      case SortBy.name:
        out.sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
      case SortBy.company:
        out.sort((a, b) => a.company.toLowerCase().compareTo(b.company.toLowerCase()));
    }
    return out;
  }

  List<String> get allTags {
    final counts = <String, int>{};
    for (final c in _contacts) {
      for (final t in c.tags) {
        counts[t] = (counts[t] ?? 0) + 1;
      }
    }
    return (counts.keys.toList()..sort((a, b) => counts[b]!.compareTo(counts[a]!)));
  }

  List<String> get allEvents {
    final set = <String>{for (final c in _contacts) if (c.metAt.isNotEmpty) c.metAt};
    return set.toList()..sort();
  }

  List<String> get allCompanies {
    final set = <String>{for (final c in _contacts) if (c.company.isNotEmpty) c.company};
    return set.toList()..sort();
  }
}

class AppScope extends InheritedNotifier<AppState> {
  const AppScope({super.key, required AppState state, required super.child})
      : super(notifier: state);

  static AppState of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<AppScope>()!.notifier!;

  static AppState read(BuildContext context) =>
      context.getInheritedWidgetOfExactType<AppScope>()!.notifier!;
}
