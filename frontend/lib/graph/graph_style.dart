import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../models/contact.dart';
import '../theme/app_theme.dart';
import 'graph_options.dart';

const _otherColor = Color(0xFF97A096);

const _groupPalette = AppColors.naturePalette;

class LegendEntry {
  const LegendEntry(this.label, this.color, [this.count = 0]);
  final String label;
  final Color color;
  final int count;
}

/// Maps contacts to node colors/sizes for the current graph settings.
class GraphStyler {
  GraphStyler({required this.contacts, required this.colorBy, required this.sizeBy})
      : edges = buildEdges(contacts) {
    for (final (a, b) in edges) {
      degree[a] = (degree[a] ?? 0) + 1;
      degree[b] = (degree[b] ?? 0) + 1;
    }
    if (colorBy == ColorBy.company || colorBy == ColorBy.metAt) {
      final counts = <String, int>{};
      for (final c in contacts) {
        final k = _groupKey(c);
        if (k.isNotEmpty) counts[k] = (counts[k] ?? 0) + 1;
      }
      final ranked = counts.keys.toList()
        ..sort((a, b) {
          final diff = counts[b]!.compareTo(counts[a]!);
          return diff != 0 ? diff : a.compareTo(b);
        });
      for (var i = 0; i < ranked.length; i++) {
        final multi = counts[ranked[i]]! > 1;
        if (i < _groupPalette.length && (multi || i < 5)) {
          _groupColors[ranked[i]] = _groupPalette[i];
        }
        _groupCounts[ranked[i]] = counts[ranked[i]]!;
      }
    }
  }

  final List<Contact> contacts;
  final ColorBy colorBy;
  final SizeBy sizeBy;
  final List<(String, String)> edges;
  final Map<String, int> degree = {};
  final Map<String, Color> _groupColors = {};
  final Map<String, int> _groupCounts = {};

  static List<(String, String)> buildEdges(List<Contact> contacts) {
    final ids = {for (final c in contacts) c.id};
    final seen = <String>{};
    final out = <(String, String)>[];
    void add(String a, String b) {
      if (a == b || !ids.contains(a) || !ids.contains(b)) return;
      final key = a.compareTo(b) < 0 ? '$a|$b' : '$b|$a';
      if (seen.add(key)) out.add((a, b));
    }

    for (final c in contacts) {
      for (final o in c.connectedIds) {
        add(c.id, o);
      }
      if (c.introducedById != null) add(c.id, c.introducedById!);
    }
    return out;
  }

  String _groupKey(Contact c) => colorBy == ColorBy.company ? c.company : c.metAt;

  Color colorFor(Contact c) {
    switch (colorBy) {
      case ColorBy.strength:
        return AppColors.strength(c.strength);
      case ColorBy.category:
        return AppColors.category[c.category]!;
      case ColorBy.company:
      case ColorBy.metAt:
        return _groupColors[_groupKey(c)] ?? _otherColor;
      case ColorBy.recency:
        return AppColors.recency(c.daysSinceContact);
    }
  }

  double radiusFor(Contact c) {
    switch (sizeBy) {
      case SizeBy.strength:
        return 8 + c.strength * 1.6;
      case SizeBy.connections:
        return 10 + math.sqrt((degree[c.id] ?? 0).toDouble()) * 6.5;
      case SizeBy.recency:
        return 24 - (c.daysSinceContact / 120).clamp(0.0, 1.0) * 13;
      case SizeBy.uniform:
        return 15;
    }
  }

  List<LegendEntry> legend() {
    switch (colorBy) {
      case ColorBy.strength:
      case ColorBy.recency:
        return const [];
      case ColorBy.category:
        final counts = <ContactCategory, int>{};
        for (final c in contacts) {
          counts[c.category] = (counts[c.category] ?? 0) + 1;
        }
        final cats = counts.keys.toList()..sort((a, b) => counts[b]!.compareTo(counts[a]!));
        return [for (final c in cats) LegendEntry(c.label, AppColors.category[c]!, counts[c]!)];
      case ColorBy.company:
      case ColorBy.metAt:
        final entries = [
          for (final e in _groupColors.entries) LegendEntry(e.key, e.value, _groupCounts[e.key] ?? 0),
        ];
        final other = contacts.where((c) => !_groupColors.containsKey(_groupKey(c))).length;
        if (other > 0) entries.add(LegendEntry('Other', _otherColor, other));
        return entries;
    }
  }

  String get sizeCaption => switch (sizeBy) {
        SizeBy.strength => 'Size = strength',
        SizeBy.connections => 'Size = how many people they know',
        SizeBy.recency => 'Size = how recently you talked',
        SizeBy.uniform => 'All nodes equal size',
      };
}
