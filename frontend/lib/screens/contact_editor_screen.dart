import 'package:flutter/material.dart';

import '../models/contact.dart';
import '../navigation.dart';
import '../services/recap_service.dart';
import '../state/app_state.dart';
import '../theme/app_theme.dart';
import '../utils/format.dart';
import '../widgets/common.dart';

class ContactEditorScreen extends StatefulWidget {
  const ContactEditorScreen({super.key, this.initial, this.draft});

  final Contact? initial;
  final RecapDraft? draft;

  @override
  State<ContactEditorScreen> createState() => _ContactEditorScreenState();
}

class _ContactEditorScreenState extends State<ContactEditorScreen> {
  late final Contact _base;
  late final Set<String> _ai;
  final Map<String, TextEditingController> _c = {};
  final _tagInput = TextEditingController();

  late int _strength;
  late ContactCategory _category;
  DateTime? _metOn;
  String? _introducedById;
  late List<String> _tags;
  late bool _canRefer;
  bool _showTranscript = false;
  String? _nameError;

  static const _textFields = [
    'name', 'title', 'company', 'email', 'phone', 'linkedin', 'location', 'metAt', 'notes',
    'conversationHooks', 'howTheyCanHelp', 'howICanHelp', 'aiSummary', 'school', 'skills',
  ];

  bool get _isDraft => widget.draft != null;
  bool get _isNew => widget.initial == null;

  @override
  void initState() {
    super.initState();
    _base = widget.initial ??
        widget.draft?.contact ??
        Contact(id: 'draft-${DateTime.now().microsecondsSinceEpoch}', name: '', metOn: DateTime.now());
    _ai = {...?widget.draft?.aiFields};
    final json = _base.toJson();
    for (final f in _textFields) {
      final value = f == 'skills' ? _base.skills.join(', ') : (json[f] as String? ?? '');
      final controller = TextEditingController(text: value);
      controller.addListener(() {
        if (_ai.contains(f) && controller.text != value) setState(() => _ai.remove(f));
      });
      _c[f] = controller;
    }
    _strength = _base.strength;
    _category = _base.category;
    _metOn = _base.metOn;
    _introducedById = _base.introducedById;
    _tags = [..._base.tags];
    _canRefer = _base.canRefer;
  }

  @override
  void dispose() {
    for (final c in _c.values) {
      c.dispose();
    }
    _tagInput.dispose();
    super.dispose();
  }

  void _touch(String field) {
    if (_ai.remove(field)) setState(() {});
  }

  String _t(String f) => _c[f]!.text.trim();

  void _save() {
    if (_t('name').isEmpty) {
      setState(() => _nameError = 'Add a name to save');
      return;
    }
    final app = AppScope.read(context);
    final messenger = ScaffoldMessenger.of(context);
    var contact = _base.copyWith(
      name: _t('name'),
      title: _t('title'),
      company: _t('company'),
      email: _t('email'),
      phone: _t('phone'),
      linkedin: _t('linkedin'),
      location: _t('location'),
      metAt: _t('metAt'),
      metOn: _metOn,
      introducedById: _introducedById,
      clearIntroducedBy: _introducedById == null,
      strength: _strength,
      category: _category,
      tags: _tags,
      notes: _t('notes'),
      conversationHooks: _t('conversationHooks'),
      howTheyCanHelp: _t('howTheyCanHelp'),
      howICanHelp: _t('howICanHelp'),
      aiSummary: _t('aiSummary'),
      school: _t('school'),
      skills: _t('skills').split(',').map((s) => s.trim()).where((s) => s.isNotEmpty).toList(),
      canRefer: _canRefer,
      lastContacted: _base.lastContacted ?? _metOn ?? DateTime.now(),
    );
    if (_isNew && _introducedById != null) {
      final intro = app.byId(_introducedById);
      if (intro != null && !contact.connectedIds.contains(intro.id)) {
        contact = contact.copyWith(connectedIds: [...contact.connectedIds, intro.id]);
      }
    }
    final saved = app.upsert(contact);
    Navigator.of(context).pop(saved);
    if (_isNew) {
      messenger
        ..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(
          content: Text('${saved.firstName} added to your network'),
          action: SnackBarAction(
            label: 'View',
            onPressed: () {
              final ctx = app.navigatorKey.currentContext;
              if (ctx != null) openContact(ctx, saved.id);
            },
          ),
        ));
    }
  }

  Future<bool> _confirmDiscard() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Discard this draft?'),
        content: const Text('The summary from your recording won\'t be saved.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Keep editing')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Discard')),
        ],
      ),
    );
    return ok ?? false;
  }

  Future<void> _pickMetDate() async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: _metOn ?? now,
      firstDate: DateTime(now.year - 10),
      lastDate: now,
    );
    if (picked == null) return;
    setState(() {
      _metOn = picked;
      _ai.remove('metOn');
    });
  }

  void _addTag(String raw) {
    final tag = raw.trim().replaceAll('#', '');
    if (tag.isEmpty || _tags.contains(tag)) {
      _tagInput.clear();
      return;
    }
    setState(() {
      _tags.add(tag);
      _ai.remove('tags');
    });
    _tagInput.clear();
  }

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    final title = _isDraft ? 'Review draft' : (_isNew ? 'New connection' : 'Edit ${_base.firstName}');

    return PopScope(
      canPop: !_isDraft,
      onPopInvokedWithResult: (didPop, _) async {
        if (didPop) return;
        final navigator = Navigator.of(context);
        if (await _confirmDiscard()) navigator.pop();
      },
      child: Scaffold(
        appBar: AppBar(
          leading: IconButton(
            tooltip: 'Close',
            icon: const Icon(Icons.close_rounded),
            onPressed: () => Navigator.of(context).maybePop(),
          ),
          title: Text(title),
          actions: [
            Padding(
              padding: const EdgeInsets.only(right: 12),
              child: FilledButton(
                onPressed: _save,
                child: Text(_isDraft ? 'Add to network' : 'Save'),
              ),
            ),
          ],
        ),
        body: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(18, 8, 18, 48),
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 760),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (_isDraft) ...[
                    _aiBanner(context),
                    const SizedBox(height: 16),
                  ],
                  _section('Basics', Icons.person_outline_rounded, [
                    _field('name', 'Full name', icon: Icons.badge_outlined, error: _nameError,
                        onChanged: (_) => setState(() => _nameError = null)),
                    _row([
                      _field('title', 'Title', icon: Icons.work_outline),
                      _field('company', 'Company', icon: Icons.apartment_outlined),
                    ]),
                    _label('Relationship', ai: _ai.contains('category')),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        for (final cat in ContactCategory.values)
                          ChoiceChip(
                            avatar: Icon(cat.icon, size: 16),
                            label: Text(cat.label),
                            selected: _category == cat,
                            onSelected: (_) => setState(() {
                              _category = cat;
                              _ai.remove('category');
                            }),
                          ),
                      ],
                    ),
                  ]),
                  _section(app.mode.strengthLabel, Icons.local_fire_department_outlined, [
                    _strengthPicker(context),
                  ]),
                  _section('How you met', Icons.place_outlined, [
                    _field('metAt', 'Event or place', icon: Icons.event_outlined),
                    if (app.allEvents.isNotEmpty)
                      Wrap(
                        spacing: 6,
                        runSpacing: 6,
                        children: [
                          for (final e in app.allEvents.take(8))
                            ActionChip(
                              label: Text(e, style: const TextStyle(fontSize: 12)),
                              visualDensity: VisualDensity.compact,
                              onPressed: () => _c['metAt']!.text = e,
                            ),
                        ],
                      ),
                    _row([
                      _dateButton(
                        label: 'Date met',
                        value: _metOn,
                        ai: _ai.contains('metOn'),
                        onTap: _pickMetDate,
                      ),
                      _introPicker(context),
                    ]),
                  ]),
                  _section('Contact info', Icons.contact_mail_outlined, [
                    _row([
                      _field('email', 'Email', icon: Icons.mail_outline_rounded, keyboard: TextInputType.emailAddress),
                      _field('phone', 'Phone', icon: Icons.call_outlined, keyboard: TextInputType.phone),
                    ]),
                    _row([
                      _field('linkedin', 'LinkedIn', icon: Icons.link_rounded, keyboard: TextInputType.url),
                      _field('location', 'Location', icon: Icons.location_on_outlined),
                    ]),
                  ]),
                  _section('What you know', Icons.lightbulb_outline_rounded, [
                    if (_isDraft || _t('aiSummary').isNotEmpty)
                      _field('aiSummary', 'Recap summary', icon: Icons.auto_awesome, maxLines: 5),
                    _field('notes', 'Notes', icon: Icons.notes_rounded, maxLines: 4),
                    _field('conversationHooks', 'Conversation hooks (hobbies, family, hometown)',
                        icon: Icons.forum_outlined, maxLines: 3),
                    _row([
                      _field('howTheyCanHelp', 'How they can help me', icon: Icons.volunteer_activism_outlined, maxLines: 3),
                      _field('howICanHelp', 'How I can help them', icon: Icons.redeem_outlined, maxLines: 3),
                    ]),
                  ]),
                  _section('Background & tags', Icons.sell_outlined, [
                    _row([
                      _field('school', 'School / grad year', icon: Icons.school_outlined),
                      _field('skills', 'Skills (comma separated)', icon: Icons.bolt_rounded),
                    ]),
                    _tagEditor(context, app.allTags),
                    _switch('Can refer me', 'They offered to refer you or make an intro', _canRefer, 'canRefer',
                        (v) => setState(() => _canRefer = v)),
                  ]),
                  const SizedBox(height: 8),
                  FilledButton.icon(
                    onPressed: _save,
                    icon: Icon(_isDraft ? Icons.person_add_alt_1_rounded : Icons.check_rounded),
                    label: Text(_isDraft ? 'Add ${_t('name').isEmpty ? 'to network' : _t('name').split(' ').first}' : 'Save'),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _aiBanner(BuildContext context) {
    final transcript = widget.draft?.transcript ?? '';
    return Container(
      padding: const EdgeInsets.all(1.4),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(19),
        gradient: const LinearGradient(colors: AppColors.brandWide),
      ),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(color: context.oc.surface, borderRadius: BorderRadius.circular(18)),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 36,
                  height: 36,
                  decoration: BoxDecoration(
                    color: AppColors.ai.withValues(alpha: 0.14),
                    borderRadius: BorderRadius.circular(11),
                  ),
                  child: const Icon(Icons.auto_awesome, color: AppColors.ai, size: 19),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Drafted from your recording', style: context.tt.titleSmall),
                      const SizedBox(height: 2),
                      Text(
                        '${_ai.length} fields filled in. Review them, then add when it looks right.',
                        style: context.tt.bodySmall,
                      ),
                    ],
                  ),
                ),
              ],
            ),
            if (transcript.isNotEmpty) ...[
              const SizedBox(height: 10),
              TextButton.icon(
                style: TextButton.styleFrom(padding: const EdgeInsets.symmetric(horizontal: 8)),
                onPressed: () => setState(() => _showTranscript = !_showTranscript),
                icon: AnimatedRotation(
                  turns: _showTranscript ? 0.5 : 0,
                  duration: const Duration(milliseconds: 200),
                  child: const Icon(Icons.expand_more_rounded, size: 18),
                ),
                label: Text(_showTranscript ? 'Hide transcript' : 'Show transcript'),
              ),
              AnimatedCrossFade(
                duration: const Duration(milliseconds: 250),
                sizeCurve: Curves.easeOutCubic,
                crossFadeState: _showTranscript ? CrossFadeState.showSecond : CrossFadeState.showFirst,
                firstChild: const SizedBox(width: double.infinity),
                secondChild: Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: context.oc.surfaceHigh,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    '"$transcript"',
                    style: context.tt.bodySmall?.copyWith(fontStyle: FontStyle.italic, color: context.oc.muted),
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _section(String title, IconData icon, List<Widget> children) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: SectionCard(
        title: title,
        icon: icon,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            for (var i = 0; i < children.length; i++) ...[
              if (i > 0) const SizedBox(height: 12),
              children[i],
            ],
          ],
        ),
      ),
    );
  }

  Widget _row(List<Widget> children) {
    return LayoutBuilder(builder: (context, constraints) {
      if (constraints.maxWidth < 520) {
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            for (var i = 0; i < children.length; i++) ...[
              if (i > 0) const SizedBox(height: 12),
              children[i],
            ],
          ],
        );
      }
      return Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (var i = 0; i < children.length; i++) ...[
            if (i > 0) const SizedBox(width: 12),
            Expanded(child: children[i]),
          ],
        ],
      );
    });
  }

  Widget _label(String text, {bool ai = false}) {
    return Row(
      children: [
        Text(text, style: context.tt.labelMedium),
        if (ai) ...[const SizedBox(width: 6), const _Sparkle()],
      ],
    );
  }

  Widget _field(
    String key,
    String label, {
    IconData? icon,
    int maxLines = 1,
    TextInputType? keyboard,
    String? error,
    ValueChanged<String>? onChanged,
  }) {
    final ai = _ai.contains(key);
    final aiBorder = OutlineInputBorder(
      borderRadius: BorderRadius.circular(14),
      borderSide: BorderSide(color: AppColors.ai.withValues(alpha: 0.45)),
    );
    return AnimatedContainer(
      duration: const Duration(milliseconds: 250),
      child: TextField(
        controller: _c[key],
        minLines: 1,
        maxLines: maxLines,
        keyboardType: maxLines > 1 ? TextInputType.multiline : keyboard,
        textCapitalization: keyboard == null ? TextCapitalization.sentences : TextCapitalization.none,
        onChanged: onChanged,
        decoration: InputDecoration(
          labelText: label,
          errorText: error,
          prefixIcon: icon == null ? null : Icon(icon, size: 20),
          suffixIcon: ai
              ? const Tooltip(
                  message: 'Filled in from your recording',
                  child: Padding(padding: EdgeInsets.all(12), child: _Sparkle()),
                )
              : null,
          fillColor: ai ? AppColors.ai.withValues(alpha: context.isDark ? 0.08 : 0.04) : null,
          enabledBorder: ai ? aiBorder : null,
        ),
      ),
    );
  }

  Widget _strengthPicker(BuildContext context) {
    final app = AppScope.of(context);
    final color = AppColors.strength(_strength);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Text(app.mode.strengthHint, style: context.tt.bodySmall),
            if (_ai.contains('strength')) ...[const SizedBox(width: 6), const _Sparkle()],
            const Spacer(),
            AnimatedDefaultTextStyle(
              duration: const Duration(milliseconds: 200),
              style: context.tt.headlineSmall!.copyWith(color: color),
              child: Text('$_strength'),
            ),
            const SizedBox(width: 8),
            SizedBox(
              width: 86,
              child: Text(
                AppColors.strengthWord(_strength),
                style: TextStyle(fontWeight: FontWeight.w600, color: color),
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),
        SliderTheme(
          data: SliderTheme.of(context).copyWith(
            activeTrackColor: color,
            thumbColor: color,
            trackHeight: 8,
            thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 11),
            activeTickMarkColor: Colors.white.withValues(alpha: 0.6),
            inactiveTickMarkColor: context.oc.border,
          ),
          child: Slider(
            value: _strength.toDouble(),
            min: 1,
            max: 10,
            divisions: 9,
            label: '$_strength',
            onChanged: (v) => setState(() {
              _strength = v.round();
              _ai.remove('strength');
            }),
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('Barely know them', style: context.tt.labelSmall),
              Text('Would vouch for me', style: context.tt.labelSmall),
            ],
          ),
        ),
      ],
    );
  }

  Widget _dateButton({
    required String label,
    required DateTime? value,
    required bool ai,
    required VoidCallback onTap,
  }) {
    return InkWell(
      borderRadius: BorderRadius.circular(14),
      onTap: onTap,
      child: InputDecorator(
        decoration: InputDecoration(
          labelText: label,
          prefixIcon: const Icon(Icons.calendar_today_outlined, size: 19),
          suffixIcon: ai ? const Padding(padding: EdgeInsets.all(12), child: _Sparkle()) : null,
        ),
        child: Text(
          value == null ? 'Not set' : '${shortDate(value)} · ${relativePast(value)}',
          style: context.tt.bodyMedium?.copyWith(color: value == null ? context.oc.subtle : null),
        ),
      ),
    );
  }

  Widget _introPicker(BuildContext context) {
    final app = AppScope.of(context);
    final options = app.contacts.where((c) => c.id != _base.id).toList()
      ..sort((a, b) => a.name.compareTo(b.name));
    return LayoutBuilder(builder: (context, constraints) {
      return DropdownMenu<String?>(
        width: constraints.maxWidth,
        initialSelection: _introducedById,
        enableFilter: true,
        requestFocusOnTap: true,
        menuHeight: 320,
        label: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('Introduced by'),
            if (_ai.contains('introducedById')) ...[const SizedBox(width: 6), const _Sparkle()],
          ],
        ),
        leadingIcon: const Icon(Icons.connect_without_contact_outlined, size: 20),
        onSelected: (id) => setState(() {
          _introducedById = id;
          _ai.remove('introducedById');
        }),
        dropdownMenuEntries: [
          const DropdownMenuEntry<String?>(value: null, label: 'No one'),
          for (final c in options) DropdownMenuEntry<String?>(value: c.id, label: c.name),
        ],
      );
    });
  }

  Widget _tagEditor(BuildContext context, List<String> suggestions) {
    final remaining = suggestions.where((t) => !_tags.contains(t)).take(8).toList();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _label('Tags', ai: _ai.contains('tags')),
        const SizedBox(height: 8),
        if (_tags.isNotEmpty) ...[
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              for (final t in _tags)
                InputChip(
                  label: Text('#$t'),
                  onDeleted: () => setState(() {
                    _tags.remove(t);
                    _ai.remove('tags');
                  }),
                ),
            ],
          ),
          const SizedBox(height: 10),
        ],
        TextField(
          controller: _tagInput,
          onSubmitted: _addTag,
          decoration: InputDecoration(
            hintText: 'Add a tag and press enter',
            prefixIcon: const Icon(Icons.tag_rounded, size: 20),
            suffixIcon: IconButton(icon: const Icon(Icons.add_rounded), onPressed: () => _addTag(_tagInput.text)),
          ),
        ),
        if (remaining.isNotEmpty) ...[
          const SizedBox(height: 8),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              for (final t in remaining)
                ActionChip(
                  label: Text('+ $t', style: const TextStyle(fontSize: 12)),
                  visualDensity: VisualDensity.compact,
                  onPressed: () => _addTag(t),
                ),
            ],
          ),
        ],
      ],
    );
  }

  Widget _switch(String title, String subtitle, bool value, String key, ValueChanged<bool> onChanged) {
    return SwitchListTile.adaptive(
      contentPadding: EdgeInsets.zero,
      value: value,
      onChanged: (v) {
        _touch(key);
        onChanged(v);
      },
      title: Row(
        children: [
          Text(title, style: context.tt.titleSmall),
          if (_ai.contains(key)) ...[const SizedBox(width: 6), const _Sparkle()],
        ],
      ),
      subtitle: Text(subtitle, style: context.tt.bodySmall),
    );
  }
}

class _Sparkle extends StatelessWidget {
  const _Sparkle();

  @override
  Widget build(BuildContext context) {
    return const Icon(Icons.auto_awesome, size: 15, color: AppColors.ai);
  }
}
