import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../theme/app_theme.dart';

/// Renders the assistant's markdown: bold, links, lists, and tables.
class ChatMarkdown extends StatelessWidget {
  const ChatMarkdown({super.key, required this.text, required this.style});

  final String text;
  final TextStyle style;

  @override
  Widget build(BuildContext context) {
    final blocks = _parse(text);
    if (blocks.isEmpty) return const SizedBox.shrink();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (var i = 0; i < blocks.length; i++) ...[
          if (i > 0) const SizedBox(height: 10),
          _block(context, blocks[i]),
        ],
      ],
    );
  }

  Widget _block(BuildContext context, _Block block) {
    return switch (block) {
      _Paragraph(:final text) => Text.rich(_span(context, text, style)),
      _Heading(:final text) => Text.rich(
          _span(context, text, style.copyWith(fontWeight: FontWeight.w700, height: 1.3)),
        ),
      _BulletList(:final items) => Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            for (final item in items)
              Padding(
                padding: const EdgeInsets.only(bottom: 4),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('•  ', style: style.copyWith(color: AppColors.ai, fontWeight: FontWeight.w700)),
                    Expanded(child: Text.rich(_span(context, item, style))),
                  ],
                ),
              ),
          ],
        ),
      _Table(:final header, :final rows) => _MarkdownTable(header: header, rows: rows, style: style),
    };
  }
}

class _MarkdownTable extends StatelessWidget {
  const _MarkdownTable({required this.header, required this.rows, required this.style});

  final List<String> header;
  final List<List<String>> rows;
  final TextStyle style;

  @override
  Widget build(BuildContext context) {
    final border = context.oc.border;
    final headerStyle = style.copyWith(fontWeight: FontWeight.w700, fontSize: (style.fontSize ?? 14) - 1);
    final cellStyle = style.copyWith(fontSize: (style.fontSize ?? 14) - 1, height: 1.35);
    return ClipRRect(
      borderRadius: BorderRadius.circular(12),
      child: DecoratedBox(
        decoration: BoxDecoration(
          border: Border.all(color: border),
          borderRadius: BorderRadius.circular(12),
        ),
        child: SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Table(
            defaultColumnWidth: const IntrinsicColumnWidth(),
            border: TableBorder(horizontalInside: BorderSide(color: border), verticalInside: BorderSide(color: border.withValues(alpha: 0.7))),
            children: [
              TableRow(
                decoration: BoxDecoration(color: context.oc.surface.withValues(alpha: context.isDark ? 0.55 : 0.7)),
                children: [for (final cell in header) _cell(context, cell, headerStyle)],
              ),
              for (final row in rows)
                TableRow(
                  children: [
                    for (var i = 0; i < header.length; i++)
                      _cell(context, i < row.length ? row[i] : '', cellStyle),
                  ],
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _cell(BuildContext context, String text, TextStyle style) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      child: Text.rich(_span(context, text, style)),
    );
  }
}

TextSpan _span(BuildContext context, String source, TextStyle style) {
  final linkColor = context.isDark ? AppColors.freshLeaf : AppColors.deepSpruce;
  return TextSpan(style: style, children: [for (final piece in _inline(source)) _piece(piece, style, linkColor)]);
}

InlineSpan _piece(_Piece piece, TextStyle style, Color linkColor) {
  return switch (piece) {
    _Text(:final text) => TextSpan(text: text),
    _Bold(:final text) => TextSpan(
        style: const TextStyle(fontWeight: FontWeight.w700),
        children: [
          for (final inner in _inline(text))
            if (inner is! _Bold) _piece(inner, style.copyWith(fontWeight: FontWeight.w700), linkColor),
        ],
      ),
    _Link(:final label, :final url, :final bold) => WidgetSpan(
        alignment: PlaceholderAlignment.baseline,
        baseline: TextBaseline.alphabetic,
        child: GestureDetector(
          onTap: () => _open(url),
          child: Text(
            label,
            style: style.copyWith(
              color: linkColor,
              fontWeight: bold ? FontWeight.w700 : FontWeight.w600,
              decoration: TextDecoration.underline,
              decorationColor: linkColor,
            ),
          ),
        ),
      ),
  };
}

Future<void> _open(String url) async {
  final uri = Uri.tryParse(url);
  if (uri == null) return;
  await launchUrl(uri, mode: LaunchMode.externalApplication).catchError((_) => false);
}

sealed class _Block {}

class _Paragraph extends _Block {
  _Paragraph(this.text);
  final String text;
}

class _Heading extends _Block {
  _Heading(this.text);
  final String text;
}

class _BulletList extends _Block {
  _BulletList(this.items);
  final List<String> items;
}

class _Table extends _Block {
  _Table(this.header, this.rows);
  final List<String> header;
  final List<List<String>> rows;
}

sealed class _Piece {}

class _Text extends _Piece {
  _Text(this.text);
  final String text;
}

class _Bold extends _Piece {
  _Bold(this.text);
  final String text;
}

class _Link extends _Piece {
  _Link(this.label, this.url, {this.bold = false});
  final String label;
  final String url;
  final bool bold;
}

final _token = RegExp(
  r'\*\*\[([^\]]+)\]\((https?:[^)\s]+)\)\*\*'
  r'|\[([^\]]+)\]\((https?:[^)\s]+)\)'
  r'|\*\*([^*]+)\*\*',
);
final _bullet = RegExp(r'^\s*(?:[-*]|\d+\.)\s+');
final _heading = RegExp(r'^#{1,3}\s+(.*)$');

List<_Block> _parse(String source) {
  final lines = source.replaceAll('\r\n', '\n').split('\n');
  final blocks = <_Block>[];
  var i = 0;
  while (i < lines.length) {
    if (lines[i].trim().isEmpty) {
      i++;
      continue;
    }
    if (_isTable(lines, i)) {
      final header = _splitRow(lines[i]);
      i += 2;
      final rows = <List<String>>[];
      while (i < lines.length && lines[i].trim().startsWith('|')) {
        rows.add(_splitRow(lines[i]));
        i++;
      }
      blocks.add(_Table(header, rows));
      continue;
    }
    if (_bullet.hasMatch(lines[i])) {
      final items = <String>[];
      while (i < lines.length && _bullet.hasMatch(lines[i])) {
        items.add(lines[i].replaceFirst(_bullet, ''));
        i++;
      }
      blocks.add(_BulletList(items));
      continue;
    }
    final heading = _heading.firstMatch(lines[i].trim());
    if (heading != null) {
      blocks.add(_Heading(heading.group(1)!));
      i++;
      continue;
    }
    final paragraph = <String>[];
    while (i < lines.length && lines[i].trim().isNotEmpty && !_isStructure(lines, i)) {
      paragraph.add(lines[i].trim());
      i++;
    }
    if (paragraph.isNotEmpty) blocks.add(_Paragraph(paragraph.join('\n')));
  }
  return blocks;
}

bool _isStructure(List<String> lines, int i) {
  if (_bullet.hasMatch(lines[i]) || _heading.hasMatch(lines[i].trim())) return true;
  return _isTable(lines, i);
}

bool _isTable(List<String> lines, int i) {
  if (i + 1 >= lines.length || !lines[i].contains('|')) return false;
  final cells = _splitRow(lines[i + 1]);
  if (cells.isEmpty) return false;
  return cells.every((cell) => RegExp(r'^:?-+:?$').hasMatch(cell.replaceAll(' ', '')));
}

List<String> _splitRow(String line) {
  var row = line.trim();
  if (row.startsWith('|')) row = row.substring(1);
  if (row.endsWith('|')) row = row.substring(0, row.length - 1);
  return [for (final cell in row.split('|')) cell.trim()];
}

List<_Piece> _inline(String source) {
  final pieces = <_Piece>[];
  var index = 0;
  for (final match in _token.allMatches(source)) {
    if (match.start > index) pieces.add(_Text(source.substring(index, match.start)));
    if (match.group(1) != null) {
      pieces.add(_Link(match.group(1)!, match.group(2)!, bold: true));
    } else if (match.group(3) != null) {
      pieces.add(_Link(match.group(3)!, match.group(4)!));
    } else if (match.group(5) != null) {
      pieces.add(_Bold(match.group(5)!));
    }
    index = match.end;
  }
  if (index < source.length) pieces.add(_Text(source.substring(index)));
  return pieces;
}
