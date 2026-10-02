import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';

import '../data/growth_resources.dart';
import '../models/user_mode.dart';
import '../navigation.dart';
import '../services/assistant_service.dart';
import '../state/app_state.dart';
import '../theme/app_theme.dart';
import '../widgets/chat_markdown.dart';
import '../widgets/common.dart';
import 'settings_sheet.dart';

const _aiGradient = LinearGradient(
  begin: Alignment.topLeft,
  end: Alignment.bottomRight,
  colors: AppColors.brand,
);

class GrowScreen extends StatefulWidget {
  const GrowScreen({super.key});

  @override
  State<GrowScreen> createState() => _GrowScreenState();
}

class _GrowScreenState extends State<GrowScreen> {
  ResourceKind _kind = ResourceKind.events;
  final _dock = GlobalKey<_AssistantDockState>();

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    final recruiter = app.mode == UserMode.recruiter;
    final showSettings = MediaQuery.sizeOf(context).width < Breakpoints.rail;
    final resources = growthResources.where((r) => r.kind == _kind).toList();

    return LayoutBuilder(builder: (context, constraints) {
      final hPad = constraints.maxWidth >= 600 ? 32.0 : 18.0;
      final open = app.assistantOpen;
      return Stack(
        children: [
          SafeArea(
            bottom: false,
            child: CustomScrollView(
              slivers: [
                SliverPadding(
                  padding: EdgeInsets.fromLTRB(hPad, 20, hPad, 0),
                  sliver: SliverToBoxAdapter(
                    child: Center(
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 1100),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        'Nourish your Network',
                                        style: context.tt.headlineSmall,
                                        maxLines: 2,
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                      const SizedBox(height: 4),
                                      Text(
                                        recruiter
                                            ? 'Places to find great people, and an assistant that knows who you\'ve met.'
                                            : 'Places to meet new people, and an assistant that knows your network.',
                                        style: context.tt.bodyMedium?.copyWith(color: context.oc.muted),
                                      ),
                                    ],
                                  ),
                                ),
                                if (showSettings)
                                  IconButton(
                                    tooltip: 'Settings',
                                    onPressed: () => showSettingsSheet(context),
                                    icon: const Icon(Icons.settings_outlined),
                                  ),
                              ],
                            ),
                            const SizedBox(height: 20),
                            SizedBox(
                              height: 38,
                              child: ListView(
                                scrollDirection: Axis.horizontal,
                                clipBehavior: Clip.none,
                                children: [
                                  for (final k in ResourceKind.values) ...[
                                    ChoiceChip(
                                      avatar: Icon(k.icon, size: 16),
                                      label: Text(k.label),
                                      selected: _kind == k,
                                      onSelected: (_) => setState(() => _kind = k),
                                    ),
                                    const SizedBox(width: 8),
                                  ],
                                  ActionChip(
                                    avatar: const Icon(Icons.auto_awesome, size: 16, color: AppColors.ai),
                                    label: const Text('Ask Spruce'),
                                    labelStyle: const TextStyle(
                                      color: AppColors.ai,
                                      fontWeight: FontWeight.w600,
                                      fontSize: 13,
                                    ),
                                    backgroundColor: AppColors.ai.withValues(alpha: context.isDark ? 0.18 : 0.1),
                                    side: BorderSide(color: AppColors.ai.withValues(alpha: 0.45)),
                                    onPressed: () => _dock.currentState?.suggestApps(),
                                  ),
                                ],
                              ),
                            ),
                            if (app.isSharedMode) ...[
                              const SizedBox(height: 8),
                              _CrossTreeIntros(
                                app: app,
                                onAsk: () => _dock.currentState?.ask(
                                  'Who should I introduce across our trees?',
                                ),
                              ),
                              const SizedBox(height: 20),
                            ] else
                              const SizedBox(height: 16),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
                SliverPadding(
                  padding: EdgeInsets.fromLTRB(
                    math.max(hPad, (constraints.maxWidth - 1100) / 2),
                    0,
                    math.max(hPad, (constraints.maxWidth - 1100) / 2),
                    120,
                  ),
                  sliver: SliverGrid(
                    gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                      maxCrossAxisExtent: 380,
                      mainAxisExtent: 128,
                      crossAxisSpacing: 14,
                      mainAxisSpacing: 14,
                    ),
                    delegate: SliverChildBuilderDelegate(
                      (context, i) => FadeSlideIn(
                        key: ValueKey('${_kind.name}-${resources[i].name}'),
                        index: i,
                        child: _ResourceCard(resource: resources[i]),
                      ),
                      childCount: resources.length,
                    ),
                  ),
                ),
              ],
            ),
          ),
          Positioned.fill(
            child: IgnorePointer(
              ignoring: !open,
              child: AnimatedOpacity(
                opacity: open ? 1 : 0,
                duration: const Duration(milliseconds: 250),
                child: GestureDetector(
                  onTap: () => app.setAssistantOpen(false),
                  child: ColoredBox(color: Colors.black.withValues(alpha: context.isDark ? 0.45 : 0.25)),
                ),
              ),
            ),
          ),
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            child: SafeArea(
              top: false,
              child: Padding(
                padding: EdgeInsets.fromLTRB(hPad > 20 ? 24 : 12, 0, hPad > 20 ? 24 : 12, hPad > 20 ? 20 : 12),
                child: AssistantDock(
                  key: _dock,
                  maxWidth: constraints.maxWidth,
                  panelHeight: math.min(640.0, constraints.maxHeight - (hPad > 20 ? 60 : 40)),
                ),
              ),
            ),
          ),
        ],
      );
    });
  }
}

class _CrossTreeIntros extends StatelessWidget {
  const _CrossTreeIntros({required this.app, required this.onAsk});
  final AppState app;
  final VoidCallback onAsk;

  @override
  Widget build(BuildContext context) {
    final oc = context.oc;
    final label = app.activeSharedTree?.shortLabel ?? 'their';
    final suggestions = app.introductionSuggestions;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.ai.withValues(alpha: context.isDark ? 0.14 : 0.08),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: AppColors.ai.withValues(alpha: 0.35)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.auto_awesome, size: 18, color: AppColors.ai),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Intro ideas across your tree and $label\'s',
                  style: context.tt.titleSmall,
                ),
              ),
              TextButton(
                onPressed: onAsk,
                child: const Text('Ask Spruce'),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            'Spruce can search both networks while shared mode is on.',
            style: context.tt.bodySmall?.copyWith(color: oc.muted),
          ),
          if (suggestions.isEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 12),
              child: Text(
                'No cross-tree matches yet — ask Spruce or add a few more people.',
                style: context.tt.bodyMedium,
              ),
            )
          else
            ...suggestions.take(3).map((item) {
              final a = item['person_a_name'] as String? ?? 'Someone';
              final b = item['person_b_name'] as String? ?? 'Someone';
              final reason = item['reason'] as String? ?? '';
              return Padding(
                padding: const EdgeInsets.only(top: 12),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(Icons.handshake_outlined, size: 18, color: oc.muted),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('$a ↔ $b', style: context.tt.titleSmall),
                          if (reason.isNotEmpty)
                            Text(reason, style: context.tt.bodySmall?.copyWith(color: oc.muted)),
                        ],
                      ),
                    ),
                  ],
                ),
              );
            }),
        ],
      ),
    );
  }
}

class _ResourceCard extends StatelessWidget {
  const _ResourceCard({required this.resource});
  final GrowthResource resource;

  Future<void> _open(BuildContext context) async {
    final ok = await launchUrl(Uri.parse(resource.url), webOnlyWindowName: '_blank').catchError((_) => false);
    if (!ok && context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Couldn\'t open ${resource.host}')));
    }
  }

  @override
  Widget build(BuildContext context) {
    final r = resource;
    final oc = context.oc;
    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => _open(context),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  _Mark(resource: r),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(r.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: context.tt.titleSmall),
                        const SizedBox(height: 2),
                        Text(
                          r.host,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: context.tt.labelSmall?.copyWith(color: oc.subtle, letterSpacing: 0),
                        ),
                      ],
                    ),
                  ),
                  Icon(Icons.open_in_new_rounded, size: 17, color: oc.subtle),
                ],
              ),
              const SizedBox(height: 12),
              Text(r.tagline, maxLines: 2, overflow: TextOverflow.ellipsis, style: context.tt.bodyMedium),
            ],
          ),
        ),
      ),
    );
  }
}

class _Mark extends StatelessWidget {
  const _Mark({required this.resource});
  final GrowthResource resource;

  @override
  Widget build(BuildContext context) {
    final text = resource.mark ?? resource.name[0];
    return Container(
      width: 42,
      height: 42,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(12),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color.lerp(resource.color, Colors.white, 0.12)!, resource.color],
        ),
      ),
      child: Text(
        text,
        style: TextStyle(
          color: Colors.white,
          fontWeight: FontWeight.w800,
          fontSize: text.length > 2 ? 12.5 : 18,
          letterSpacing: text.length > 1 ? -0.3 : 0,
        ),
      ),
    );
  }
}

/// Collapsed chat bar that expands into a full assistant panel.
class AssistantDock extends StatefulWidget {
  const AssistantDock({
    super.key,
    required this.maxWidth,
    required this.panelHeight,
    this.collapsedStyle = AssistantCollapsedStyle.bar,
  });

  final double maxWidth;
  final double panelHeight;
  final AssistantCollapsedStyle collapsedStyle;

  @override
  State<AssistantDock> createState() => _AssistantDockState();
}

enum AssistantCollapsedStyle { bar, fab }

class _AssistantDockState extends State<AssistantDock> {
  final _input = TextEditingController();
  late final FocusNode _focus = FocusNode(onKeyEvent: _onKey);
  final List<ChatMessage> _messages = [];
  List<String>? _suggestions;
  bool _loadingSuggestions = false;
  bool _sending = false;
  String _streaming = '';
  StreamSubscription<String>? _sub;
  int _generation = 0;
  int _seenEpoch = -1;

  @override
  void dispose() {
    _sub?.cancel();
    _input.dispose();
    _focus.dispose();
    super.dispose();
  }

  KeyEventResult _onKey(FocusNode node, KeyEvent e) {
    if (e is! KeyDownEvent) return KeyEventResult.ignored;
    if (e.logicalKey == LogicalKeyboardKey.enter && !HardwareKeyboard.instance.isShiftPressed) {
      _send();
      return KeyEventResult.handled;
    }
    if (e.logicalKey == LogicalKeyboardKey.escape) {
      AppScope.read(context).setAssistantOpen(false);
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  Future<void> _loadSuggestions() async {
    if (_loadingSuggestions) return;
    _loadingSuggestions = true;
    final app = AppScope.read(context);
    try {
      final list = await app.assistant.suggestedPrompts();
      if (mounted) setState(() => _suggestions = list);
    } catch (_) {
      if (mounted) setState(() => _suggestions = const []);
    } finally {
      _loadingSuggestions = false;
    }
  }

  void _expand() {
    AppScope.read(context).setAssistantOpen(true);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _focus.requestFocus();
    });
  }

  /// Opens the panel and puts [prompt] in the box so the user can finish it.
  void _fillDraft(String prompt) {
    AppScope.read(context).setAssistantOpen(true);
    _input.value = TextEditingValue(
      text: prompt,
      selection: TextSelection.collapsed(offset: prompt.length),
    );
    _focus.requestFocus();
  }

  void _useSuggestion(String text) {
    if (text.toLowerCase().startsWith('find alumni')) {
      final school = AppScope.read(context).university.trim();
      final from = school.isEmpty ? 'my university' : school;
      _fillDraft('Find alumni from $from who work at local companies in ');
      return;
    }
    _send(text);
  }

  /// Opens the panel and sends [prompt] as if the user had typed it.
  void ask(String prompt) {
    AppScope.read(context).setAssistantOpen(true);
    _send(prompt);
  }

  /// Local app picks from the size of the user's own tree. Does not call the API.
  void suggestApps() {
    if (_sending) return;
    final app = AppScope.read(context);
    final answer = spruceAppSuggestion(
      people: app.contacts.length,
      recruiter: app.mode == UserMode.recruiter,
    );
    app.setAssistantOpen(true);
    setState(() {
      _messages.add(ChatMessage(
        role: ChatRole.user,
        text: 'Which apps should I use?',
        sentAt: DateTime.now(),
      ));
      _sending = true;
      _streaming = '';
    });
    final generation = _generation;
    final words = answer.split(' ');
    _sub = _typed(words).listen(
      (chunk) {
        if (!mounted || generation != _generation) return;
        setState(() => _streaming += chunk);
      },
      onDone: () {
        if (!mounted || generation != _generation) return;
        _finish(_streaming);
      },
      onError: (_) {
        if (!mounted || generation != _generation) return;
        _finish(answer);
      },
    );
  }

  Stream<String> _typed(List<String> words) async* {
    for (var i = 0; i < words.length; i++) {
      yield i == 0 ? words[i] : ' ${words[i]}';
      await Future<void>.delayed(const Duration(milliseconds: 16));
    }
  }

  void _newChat() {
    _generation++;
    _sub?.cancel();
    AppScope.read(context).assistant.reset();
    setState(() {
      _messages.clear();
      _sending = false;
      _streaming = '';
      _suggestions = null;
    });
    _loadSuggestions();
  }

  void _send([String? preset]) {
    final text = (preset ?? _input.text).trim();
    if (text.isEmpty || _sending) return;
    _input.clear();
    setState(() {
      _messages.add(ChatMessage(role: ChatRole.user, text: text, sentAt: DateTime.now()));
      _sending = true;
      _streaming = '';
    });
    final app = AppScope.read(context);
    final generation = _generation;
    _sub = app.assistant.reply(List.of(_messages)).listen(
      (chunk) {
        if (!mounted || generation != _generation) return;
        setState(() => _streaming += chunk);
      },
      onDone: () {
        if (!mounted || generation != _generation) return;
        _finish(_streaming);
      },
      onError: (_) {
        if (!mounted || generation != _generation) return;
        _finish('Sorry, I couldn\'t reach the assistant. Try again in a moment.');
      },
      cancelOnError: true,
    );
  }

  void _finish(String text) {
    if (!mounted) return;
    setState(() {
      _messages.add(ChatMessage(role: ChatRole.assistant, text: text, sentAt: DateTime.now()));
      _sending = false;
      _streaming = '';
    });
  }

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    final open = app.assistantOpen;
    if (_seenEpoch < 0) {
      _seenEpoch = app.assistantEpoch;
    } else if (_seenEpoch != app.assistantEpoch) {
      final epoch = app.assistantEpoch;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted || _seenEpoch == epoch) return;
        _generation++;
        _seenEpoch = epoch;
        _sub?.cancel();
        setState(() {
          _messages.clear();
          _sending = false;
          _streaming = '';
          _suggestions = null;
        });
        _loadSuggestions();
      });
    }
    if (open && _suggestions == null && !_loadingSuggestions) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _loadSuggestions());
    }
    final oc = context.oc;
    const collapsedHeight = 58.0;
    const fabSize = 56.0;
    final fab = widget.collapsedStyle == AssistantCollapsedStyle.fab;
    final width = open
        ? math.min(widget.maxWidth - 24, 760.0)
        : (fab ? fabSize : math.min(widget.maxWidth - 24, 600.0));
    final height = open ? widget.panelHeight : (fab ? fabSize : collapsedHeight);

    return Center(
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 380),
        curve: Curves.easeOutCubic,
        width: width,
        height: height,
        clipBehavior: Clip.antiAlias,
        decoration: BoxDecoration(
          color: fab && !open ? null : oc.surface,
          gradient: fab && !open
              ? const LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: AppColors.brand,
                )
              : null,
          borderRadius: BorderRadius.circular(open ? 24 : (fab ? fabSize / 2 : collapsedHeight / 2)),
          border: fab && !open
              ? null
              : Border.all(color: open ? oc.border : AppColors.ai.withValues(alpha: 0.35), width: 1.2),
          boxShadow: [
            BoxShadow(
              color: (open ? Colors.black : AppColors.ai).withValues(alpha: context.isDark ? 0.4 : 0.16),
              blurRadius: open ? 40 : 24,
              offset: const Offset(0, 10),
            ),
          ],
        ),
        child: AnimatedSwitcher(
          duration: const Duration(milliseconds: 220),
          layoutBuilder: (current, previous) => Stack(
            alignment: Alignment.bottomCenter,
            children: [...previous, ?current],
          ),
          child: open
              ? OverflowBox(
                  key: const ValueKey('open'),
                  alignment: Alignment.bottomCenter,
                  minHeight: widget.panelHeight,
                  maxHeight: widget.panelHeight,
                  child: _panel(context),
                )
              : fab
                  ? _CollapsedFab(key: const ValueKey('fab'), onTap: _expand)
                  : _CollapsedBar(key: const ValueKey('closed'), onTap: _expand),
        ),
      ),
    );
  }

  Widget _panel(BuildContext context) {
    final app = AppScope.of(context);
    final oc = context.oc;
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 8, 10),
          child: Row(
            children: [
              const _AiAvatar(size: 34),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Spruce', style: context.tt.titleSmall),
                    Text(
                      app.demoMode ? 'Demo mode · sample answers' : 'Live AI · knows your network',
                      style: context.tt.bodySmall?.copyWith(color: oc.subtle),
                    ),
                  ],
                ),
              ),
              if (_messages.isNotEmpty)
                IconButton(
                  tooltip: 'New chat',
                  onPressed: _newChat,
                  icon: Icon(Icons.edit_square, size: 20, color: oc.muted),
                ),
              IconButton(
                tooltip: 'Minimize',
                onPressed: () => app.setAssistantOpen(false),
                icon: Icon(Icons.keyboard_arrow_down_rounded, color: oc.muted),
              ),
            ],
          ),
        ),
        Divider(height: 1, color: oc.border),
        Expanded(
          child: AnimatedSwitcher(
            duration: const Duration(milliseconds: 250),
            child: _messages.isEmpty ? _welcome(context) : _conversation(context),
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 6, 12, 4),
          child: Container(
            padding: const EdgeInsets.fromLTRB(16, 4, 6, 4),
            decoration: BoxDecoration(
              color: oc.surfaceHigh.withValues(alpha: context.isDark ? 0.7 : 1),
              borderRadius: BorderRadius.circular(22),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Expanded(
                  child: TextField(
                    controller: _input,
                    focusNode: _focus,
                    minLines: 1,
                    maxLines: 5,
                    textCapitalization: TextCapitalization.sentences,
                    style: context.tt.bodyMedium,
                    decoration: const InputDecoration(
                      hintText: 'Ask about people, companies, or events…',
                      border: InputBorder.none,
                      enabledBorder: InputBorder.none,
                      focusedBorder: InputBorder.none,
                      filled: false,
                      isDense: true,
                      contentPadding: EdgeInsets.symmetric(vertical: 12),
                    ),
                  ),
                ),
                const SizedBox(width: 6),
                ListenableBuilder(
                  listenable: _input,
                  builder: (context, _) {
                    final ready = _input.text.trim().isNotEmpty && !_sending;
                    return AnimatedOpacity(
                      duration: const Duration(milliseconds: 150),
                      opacity: ready ? 1 : 0.45,
                      child: Material(
                        shape: const CircleBorder(),
                        clipBehavior: Clip.antiAlias,
                        child: Ink(
                          width: 38,
                          height: 38,
                          decoration: const BoxDecoration(gradient: _aiGradient),
                          child: InkWell(
                            onTap: ready ? _send : null,
                            child: const Icon(Icons.arrow_upward_rounded, color: AppColors.mistCream, size: 20),
                          ),
                        ),
                      ),
                    );
                  },
                ),
              ],
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: Text(
            'AI can make mistakes. Double-check anything important.',
            style: context.tt.labelSmall?.copyWith(color: oc.subtle, letterSpacing: 0),
          ),
        ),
      ],
    );
  }

  Widget _welcome(BuildContext context) {
    final app = AppScope.of(context);
    final oc = context.oc;
    final name = app.userName.isEmpty ? '' : ', ${app.userName}';
    final suggestions = _suggestions;
    return ListView(
      key: const ValueKey('welcome'),
      padding: const EdgeInsets.fromLTRB(20, 22, 20, 12),
      children: [
        Text('Hi$name. What do you want to work on?', style: context.tt.titleMedium),
        const SizedBox(height: 4),
        Text('A few ideas based on your network:', style: context.tt.bodySmall?.copyWith(color: oc.muted)),
        const SizedBox(height: 16),
        if (suggestions == null)
          for (var i = 0; i < 3; i++) const _SuggestionSkeleton()
        else
          for (var i = 0; i < suggestions.length; i++)
            FadeSlideIn(
              index: i,
              child: _SuggestionTile(
                text: suggestions[i],
                fillsIn: suggestions[i].toLowerCase().startsWith('find alumni'),
                onTap: () => _useSuggestion(suggestions[i]),
              ),
            ),
      ],
    );
  }

  Widget _conversation(BuildContext context) {
    final items = [
      if (_sending) ChatMessage(role: ChatRole.assistant, text: _streaming, sentAt: DateTime.now()),
      ..._messages.reversed,
    ];
    return ListView.builder(
      key: const ValueKey('chat'),
      reverse: true,
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
      itemCount: items.length,
      itemBuilder: (context, i) {
        final m = items[i];
        final pending = _sending && i == 0;
        return Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: _Bubble(message: m, thinking: pending),
        );
      },
    );
  }
}

class _CollapsedFab extends StatelessWidget {
  const _CollapsedFab({super.key, required this.onTap});
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      type: MaterialType.transparency,
      child: Tooltip(
        message: 'Ask Spruce',
        child: InkWell(
          onTap: onTap,
          customBorder: const CircleBorder(),
          child: const SizedBox.expand(
            child: Icon(Icons.auto_awesome, color: AppColors.mistCream, size: 24),
          ),
        ),
      ),
    );
  }
}

class _CollapsedBar extends StatelessWidget {
  const _CollapsedBar({super.key, required this.onTap});
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final oc = context.oc;
    return Material(
      type: MaterialType.transparency,
      child: InkWell(
        onTap: onTap,
        child: SizedBox(
          height: 58,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: Row(
              children: [
                const _AiAvatar(size: 34),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    'Ask Spruce about your network…',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: context.tt.bodyMedium?.copyWith(color: oc.muted),
                  ),
                ),
                Container(
                  width: 34,
                  height: 34,
                  decoration: BoxDecoration(color: oc.surfaceHigh, shape: BoxShape.circle),
                  child: Icon(Icons.keyboard_arrow_up_rounded, color: oc.muted, size: 22),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _AiAvatar extends StatelessWidget {
  const _AiAvatar({required this.size});
  final double size;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: const BoxDecoration(shape: BoxShape.circle, gradient: _aiGradient),
      child: Icon(Icons.auto_awesome, color: AppColors.mistCream, size: size * 0.5),
    );
  }
}

class _SuggestionTile extends StatelessWidget {
  const _SuggestionTile({required this.text, required this.onTap, this.fillsIn = false});
  final String text;
  final VoidCallback onTap;
  final bool fillsIn;

  @override
  Widget build(BuildContext context) {
    final oc = context.oc;
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Material(
        color: Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(14),
          side: BorderSide(color: oc.border),
        ),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            child: Row(
              children: [
                const Icon(Icons.auto_awesome_outlined, size: 17, color: AppColors.ai),
                const SizedBox(width: 10),
                Expanded(child: Text(text, style: context.tt.bodyMedium)),
                Icon(fillsIn ? Icons.edit_outlined : Icons.arrow_forward_rounded, size: 17, color: oc.subtle),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _SuggestionSkeleton extends StatefulWidget {
  const _SuggestionSkeleton();

  @override
  State<_SuggestionSkeleton> createState() => _SuggestionSkeletonState();
}

class _SuggestionSkeletonState extends State<_SuggestionSkeleton> with SingleTickerProviderStateMixin {
  late final AnimationController _c =
      AnimationController(vsync: this, duration: const Duration(milliseconds: 900))..repeat(reverse: true);

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: FadeTransition(
        opacity: Tween(begin: 0.45, end: 1.0).animate(_c),
        child: Container(
          height: 46,
          decoration: BoxDecoration(color: context.oc.surfaceHigh, borderRadius: BorderRadius.circular(14)),
        ),
      ),
    );
  }
}

class _Bubble extends StatelessWidget {
  const _Bubble({required this.message, this.thinking = false});
  final ChatMessage message;
  final bool thinking;

  @override
  Widget build(BuildContext context) {
    final oc = context.oc;
    final mine = message.role == ChatRole.user;
    final textStyle = context.tt.bodyMedium?.copyWith(color: mine ? context.cs.onPrimary : oc.ink, height: 1.45);
    final body = message.text.isEmpty
        ? const _TypingDots()
        : Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (mine)
                SelectableText(message.text, style: textStyle)
              else
                ChatMarkdown(text: message.text, style: textStyle!),
              if (thinking) ...[
                const SizedBox(height: 8),
                const _TypingDots(),
              ],
            ],
          );
    final bubble = Container(
      constraints: const BoxConstraints(maxWidth: 520),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: mine ? context.cs.primary : oc.surfaceHigh.withValues(alpha: context.isDark ? 0.8 : 1),
        borderRadius: BorderRadius.only(
          topLeft: const Radius.circular(18),
          topRight: const Radius.circular(18),
          bottomLeft: Radius.circular(mine ? 18 : 6),
          bottomRight: Radius.circular(mine ? 6 : 18),
        ),
      ),
      child: body,
    );
    if (mine) {
      return Align(alignment: Alignment.centerRight, child: bubble);
    }
    return Row(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        const _AiAvatar(size: 26),
        const SizedBox(width: 8),
        Flexible(child: bubble),
      ],
    );
  }
}

class _TypingDots extends StatefulWidget {
  const _TypingDots();

  @override
  State<_TypingDots> createState() => _TypingDotsState();
}

class _TypingDotsState extends State<_TypingDots> with SingleTickerProviderStateMixin {
  late final AnimationController _c =
      AnimationController(vsync: this, duration: const Duration(milliseconds: 1100))..repeat();

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final color = context.oc.muted;
    return SizedBox(
      height: 20,
      width: 36,
      child: AnimatedBuilder(
        animation: _c,
        builder: (context, _) => Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            for (var i = 0; i < 3; i++)
              Transform.translate(
                offset: Offset(0, -3 * math.sin(((_c.value - i * 0.18) % 1) * math.pi).clamp(0, 1)),
                child: Container(
                  width: 7,
                  height: 7,
                  decoration: BoxDecoration(color: color, shape: BoxShape.circle),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
