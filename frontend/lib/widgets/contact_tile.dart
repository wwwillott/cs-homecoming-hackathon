import 'package:flutter/material.dart';

import '../models/contact.dart';
import '../theme/app_theme.dart';
import '../utils/format.dart';
import 'common.dart';

class ContactTile extends StatelessWidget {
  const ContactTile({
    super.key,
    required this.contact,
    required this.onTap,
    this.selected = false,
    this.dense = false,
  });

  final Contact contact;
  final VoidCallback onTap;
  final bool selected;
  final bool dense;

  @override
  Widget build(BuildContext context) {
    final oc = context.oc;
    final c = contact;
    final subtitle = [
      if (c.metAt.isNotEmpty) c.metAt,
      if (c.metOn != null) shortDate(c.metOn!),
    ].join(' · ');

    return AnimatedContainer(
      duration: const Duration(milliseconds: 200),
      decoration: BoxDecoration(
        color: selected ? context.cs.primary.withValues(alpha: context.isDark ? 0.16 : 0.07) : oc.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: selected ? context.cs.primary.withValues(alpha: 0.5) : oc.border,
        ),
      ),
      child: Material(
        type: MaterialType.transparency,
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: onTap,
          child: Padding(
            padding: EdgeInsets.symmetric(horizontal: 14, vertical: dense ? 10 : 13),
            child: Row(
              children: [
                ContactAvatar(contact: c, size: dense ? 38 : 44),
                const SizedBox(width: 13),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Flexible(
                            child: Text(
                              c.name,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: context.tt.titleSmall?.copyWith(fontSize: 15),
                            ),
                          ),
                          if (c.favorite) ...[
                            const SizedBox(width: 5),
                            const Icon(Icons.star_rounded, size: 15, color: AppColors.amber),
                          ],
                        ],
                      ),
                      if (c.roleLine.isNotEmpty) ...[
                        const SizedBox(height: 2),
                        Text(
                          c.roleLine,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: context.tt.bodySmall?.copyWith(color: oc.muted, fontSize: 13),
                        ),
                      ],
                      if (!dense && subtitle.isNotEmpty) ...[
                        const SizedBox(height: 5),
                        Row(
                          children: [
                            Icon(Icons.place_outlined, size: 13, color: oc.subtle),
                            const SizedBox(width: 4),
                            Flexible(
                              child: Text(
                                subtitle,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: context.tt.labelSmall?.copyWith(
                                  color: oc.subtle,
                                  fontWeight: FontWeight.w500,
                                  letterSpacing: 0,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ],
                  ),
                ),
                const SizedBox(width: 10),
                StrengthBadge(value: c.strength, compact: dense),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
