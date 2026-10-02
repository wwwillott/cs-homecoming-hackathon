import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../data/contact_repository.dart';
import '../data/demo_data.dart';
import '../graph/graph_options.dart';
import '../models/contact.dart';
import '../models/network_tree.dart';
import '../models/user_mode.dart';
import '../services/assistant_service.dart';
import '../services/auth_service.dart';
import '../services/network_tree_service.dart';
import '../services/recap_service.dart';
import '../services/streaming_recap_service.dart';

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
  AppState({
    ContactRepository? repository,
    RecapService? recapService,
    AssistantService? assistant,
    AuthService? authService,
    NetworkTreeService? networkTreeService,
  })  : authService = authService ?? AuthService(),
        _customRepository = repository,
        _injectedRecap = recapService,
        _customAssistant = assistant,
        _customNetworkTrees = networkTreeService;

  final AuthService authService;
  final ContactRepository? _customRepository;
  final RecapService? _injectedRecap;
  final AssistantService? _customAssistant;
  final NetworkTreeService? _customNetworkTrees;

  late final ContactRepository repository =
      _customRepository ?? LocalContactRepository(userId: () => userId);
  late final NetworkTreeService networkTrees =
      _customNetworkTrees ?? NetworkTreeService(userId: () => userId);
  late final RecapService _liveRecap = ApiRecapService(userId: () => userId);
  late final RecapService _demoRecap = MockRecapService();
  late final ApiAssistantService _liveAssistant = ApiAssistantService(
    networkContext: () {
      final shared = activeSharedTree;
      final brief = networkBrief(contacts: visibleContacts, userName: userName);
      if (shared == null) return brief;
      return '$brief\n\nShared mode is on with ${shared.label}. '
          'People from that attached tree are included above and marked read-only.';
    },
    place: () => {'city': city, 'state': homeState, 'university': university},
    sharedLabel: () => activeSharedTree?.shortLabel,
  );
  late final MockAssistantService _mockAssistant = MockAssistantService(
    contacts: () => visibleContacts,
    mode: () => mode,
    userName: () => userName,
  );
  late final AssistantService assistant = _customAssistant ??
      ModeAssistantService(
        demoMode: () => demoMode,
        live: _liveAssistant,
        demo: _mockAssistant,
      );

  RecapService get recapService => _injectedRecap ?? (demoMode ? _demoRecap : _liveRecap);
  final navigatorKey = GlobalKey<NavigatorState>();

  static const _kSessionUserId = 'orbit.session.userId';
  static const _kSessionUsername = 'orbit.session.username';
  static const _kTheme = 'orbit.theme';
  static const _kDemo = 'orbit.demoMode';
  static const _firstTreeGoals = [5, 10, 15, 25, 30];

  /// Network-size goals that grow the tree: 5, 10, 15, 25, 30, then every 10.
  static int treeGoal(int index) => index < _firstTreeGoals.length
      ? _firstTreeGoals[index]
      : _firstTreeGoals.last + 10 * (index - _firstTreeGoals.length + 1);

  bool loaded = false;
  bool onboarded = false;
  bool demoMode = false;
  int assistantEpoch = 0;
  String? userId;
  String? username;
  UserMode mode = UserMode.seeker;
  ThemeMode themeMode = ThemeMode.system;
  String userName = '';
  String city = '';
  String homeState = '';
  String university = '';

  bool get isSignedIn => userId != null && userId!.isNotEmpty;

  List<Contact> _contacts = [];
  Map<String, Contact> _byId = {};
  List<NetworkTree> trees = [];
  NetworkTree? activeSharedTree;
  List<Contact> _attachedContacts = [];
  List<Map<String, dynamic>> introductionSuggestions = [];

  List<Contact> get contacts => _contacts;
  List<Contact> get attachedContacts => isSharedMode ? _attachedContacts : const [];
  List<Contact> get visibleContacts => [..._contacts, ...attachedContacts];
  bool get isSharedMode => activeSharedTree != null;
  Contact? byId(String? id) {
    if (id == null) return null;
    return _byId[id] ?? _attachedById[id];
  }

  Map<String, Contact> get _attachedById => {for (final c in attachedContacts) c.id: c};

  List<String> askTreeIds() => [
        if (primaryTree != null) primaryTree!.id,
        if (activeSharedTree != null) activeSharedTree!.id,
      ];

  NetworkTree? get primaryTree {
    for (final tree in trees) {
      if (tree.isPrimary) return tree;
    }
    return null;
  }

  int _treeLevelSeen = 0;

  /// Number of network-size goals reached.
  int get treeLevel {
    var level = 0;
    while (_contacts.length >= treeGoal(level)) {
      level++;
    }
    return level;
  }

  /// Level currently drawn; lags [treeLevel] until the user watches it grow.
  int get shownTreeLevel => math.min(_treeLevelSeen, treeLevel);

  bool get treeGrowthPending => treeLevel > _treeLevelSeen;

  int get nextTreeGoal => treeGoal(treeLevel);
  int get previousTreeGoal => treeLevel == 0 ? 0 : treeGoal(treeLevel - 1);
  int get connectionsToNextGrowth => nextTreeGoal - _contacts.length;
  double get treeGoalProgress =>
      (_contacts.length - previousTreeGoal) / (nextTreeGoal - previousTreeGoal);

  void markTreeGrown() {
    if (!treeGrowthPending) return;
    _setTreeLevelSeen(treeLevel);
  }

  void _setTreeLevelSeen(int level) {
    _treeLevelSeen = math.max(level, 0);
    notifyListeners();
    if (isSignedIn) {
      SharedPreferences.getInstance().then((p) => p.setInt(_pref('treeGoalsSeen'), _treeLevelSeen));
    }
  }

  AppTab tab = AppTab.home;
  String? selectedContactId;

  ColorBy colorBy = ColorBy.strength;
  SizeBy sizeBy = SizeBy.strength;
  bool showPeerLinks = true;
  String? graphFocusId;
  bool assistantOpen = false;

  String _pref(String key) => 'orbit.$userId.$key';

  Future<void> init() async {
    final prefs = await SharedPreferences.getInstance();
    themeMode = ThemeMode.values.firstWhere(
      (m) => m.name == prefs.getString(_kTheme),
      orElse: () => ThemeMode.system,
    );
    demoMode = prefs.getBool(_kDemo) ?? false;
    userId = prefs.getString(_kSessionUserId);
    username = prefs.getString(_kSessionUsername);
    if (isSignedIn) {
      await _loadUserData(prefs);
      await refreshTrees();
    }
    loaded = true;
    notifyListeners();
  }

  Future<void> _loadUserData(SharedPreferences prefs) async {
    onboarded = prefs.getBool(_pref('onboarded')) ?? false;
    mode = UserMode.fromName(prefs.getString(_pref('mode')));
    userName = prefs.getString(_pref('userName')) ?? '';
    city = prefs.getString(_pref('city')) ?? '';
    homeState = prefs.getString(_pref('state')) ?? '';
    university = prefs.getString(_pref('university')) ?? '';
    _setContacts(await repository.loadAll());
    _treeLevelSeen = prefs.getInt(_pref('treeGoalsSeen')) ?? treeLevel;
  }

  void _setContacts(List<Contact> list) {
    _contacts = list;
    _byId = {for (final c in list) c.id: c};
  }

  Future<void> _persist() => repository.saveAll(_contacts);

  Future<void> signIn(AuthSession session) async {
    userId = session.userId;
    username = session.username;
    selectedContactId = null;
    graphFocusId = null;
    tab = AppTab.home;
    assistantOpen = false;

    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_kSessionUserId, session.userId);
    await prefs.setString(_kSessionUsername, session.username);
    await _loadUserData(prefs);
    await refreshTrees();
    notifyListeners();
  }

  Future<void> signOut() async {
    userId = null;
    username = null;
    onboarded = false;
    userName = '';
    mode = UserMode.seeker;
    selectedContactId = null;
    graphFocusId = null;
    assistantOpen = false;
    leaveSharedMode();
    trees = [];
    _attachedContacts = [];
    introductionSuggestions = [];
    _setContacts([]);
    _treeLevelSeen = 0;
    assistantEpoch++;
    assistant.reset();
    tab = AppTab.home;

    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_kSessionUserId);
    await prefs.remove(_kSessionUsername);
    notifyListeners();
  }

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
    _setTreeLevelSeen(withDemoData ? treeLevel - 1 : treeLevel);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_pref('onboarded'), true);
    await prefs.setString(_pref('mode'), mode.name);
    await prefs.setString(_pref('userName'), userName);
    await _persist();
  }

  Future<void> resetApp() async {
    final prefs = await SharedPreferences.getInstance();
    if (isSignedIn) {
      await prefs.remove(_pref('onboarded'));
      await prefs.remove(_pref('mode'));
      await prefs.remove(_pref('userName'));
      await prefs.remove(_pref('city'));
      await prefs.remove(_pref('state'));
      await prefs.remove(_pref('university'));
      await prefs.remove(_pref('treeGoalsSeen'));
      await prefs.remove('orbit.contacts.$userId');
    }
    await prefs.remove(_kDemo);
    demoMode = false;
    await signOut();
  }

  /// The sample network leaves its last growth unwatched so the reveal can be demoed.
  void loadDemoData() {
    _setContacts(buildDemoContacts());
    selectedContactId = null;
    graphFocusId = null;
    _setTreeLevelSeen(treeLevel - 1);
    _persist();
  }

  void setMode(UserMode value) {
    if (mode == value) return;
    mode = value;
    notifyListeners();
    if (isSignedIn) {
      SharedPreferences.getInstance().then((p) => p.setString(_pref('mode'), value.name));
    }
  }

  void setDemoMode(bool value) {
    if (demoMode == value) return;
    demoMode = value;
    assistantEpoch++;
    assistant.reset();
    notifyListeners();
    SharedPreferences.getInstance().then((prefs) => prefs.setBool(_kDemo, value));
  }

  void setPlace({required String city, required String state, required String university}) {
    final nextCity = city.trim();
    final nextState = state.trim();
    final nextSchool = university.trim();
    if (nextCity == this.city && nextState == homeState && nextSchool == this.university) return;
    this.city = nextCity;
    homeState = nextState;
    this.university = nextSchool;
    assistantEpoch++;
    assistant.reset();
    notifyListeners();
    if (!isSignedIn) return;
    SharedPreferences.getInstance().then((prefs) async {
      await prefs.setString(_pref('city'), this.city);
      await prefs.setString(_pref('state'), homeState);
      await prefs.setString(_pref('university'), this.university);
    });
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
    if (contact.readOnly) {
      final index = _attachedContacts.indexWhere((c) => c.id == contact.id);
      if (index != -1) {
        _attachedContacts = [..._attachedContacts]..[index] = contact;
        notifyListeners();
      }
      return contact;
    }
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
    if (_attachedById.containsKey(id)) return;
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
    out.addAll(c.connectedIds.where((other) => byId(other) != null));
    if (c.introducedById != null && byId(c.introducedById) != null) {
      out.add(c.introducedById!);
    }
    for (final other in visibleContacts) {
      if (other.connectedIds.contains(id) || other.introducedById == id) {
        out.add(other.id);
      }
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

  List<String> get allCompanies {
    final set = <String>{for (final c in _contacts) if (c.company.isNotEmpty) c.company};
    return set.toList()..sort();
  }

  Future<void> refreshTrees() async {
    if (!isSignedIn) return;
    try {
      trees = await networkTrees.listTrees();
      if (activeSharedTree != null) {
        final match = trees.where((tree) => tree.id == activeSharedTree!.id);
        if (match.isEmpty) {
          leaveSharedMode();
        } else {
          activeSharedTree = match.first;
          _attachedContacts = await networkTrees.loadTreeContacts(activeSharedTree!.id);
          await refreshIntroductionSuggestions();
        }
      }
      notifyListeners();
    } catch (_) {
      // Sharing stays local-only when the backend is offline.
    }
  }

  Future<NetworkShareCode> exportPrimaryTree() async {
    if (!isSignedIn) {
      throw StateError('Sign in to share your network.');
    }
    for (final contact in _contacts) {
      try {
        await networkTrees.syncContact(contact);
      } catch (_) {}
    }
    await refreshTrees();
    final tree = primaryTree;
    if (tree == null) {
      throw StateError('Your network is not ready to share yet.');
    }
    return networkTrees.exportTree(tree.id);
  }

  Future<void> joinSharedTree(String shareToken) async {
    final tree = await networkTrees.importTree(shareToken);
    await enterSharedMode(tree);
  }

  Future<void> enterSharedMode(NetworkTree tree) async {
    activeSharedTree = tree;
    _attachedContacts = await networkTrees.loadTreeContacts(tree.id);
    await refreshTrees();
    await refreshIntroductionSuggestions();
    notifyListeners();
  }

  void leaveSharedMode() {
    if (activeSharedTree == null && _attachedContacts.isEmpty) return;
    activeSharedTree = null;
    _attachedContacts = [];
    introductionSuggestions = [];
    if (graphFocusId != null && !_byId.containsKey(graphFocusId)) {
      graphFocusId = null;
    }
    notifyListeners();
  }

  /// Test helper for dual-tree UI without the backend.
  void attachSharedTreeForTest({
    required NetworkTree tree,
    required List<Contact> contacts,
  }) {
    trees = [
      if (primaryTree == null)
        const NetworkTree(
          id: 'primary',
          label: 'My network',
          isPrimary: true,
          isReadOnly: false,
        ),
      ...trees.where((item) => item.id != tree.id),
      tree,
    ];
    activeSharedTree = tree;
    _attachedContacts = contacts;
    notifyListeners();
  }

  Future<void> refreshIntroductionSuggestions() async {
    if (activeSharedTree == null) {
      introductionSuggestions = [];
      return;
    }
    try {
      introductionSuggestions = await networkTrees.introductionSuggestions(
        mode: 'cross_tree',
        treeId: activeSharedTree!.id,
      );
    } catch (_) {
      introductionSuggestions = [];
    }
  }

  @override
  void dispose() {
    if (_injectedRecap != null) {
      unawaited(_injectedRecap.dispose());
    } else {
      unawaited(_liveRecap.dispose());
      unawaited(_demoRecap.dispose());
    }
    authService.dispose();
    networkTrees.dispose();
    super.dispose();
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
