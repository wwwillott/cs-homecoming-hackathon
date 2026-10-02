import 'package:flutter/material.dart';

enum ResourceKind {
  events('Attend events', Icons.event_outlined),
  community('Join communities', Icons.groups_outlined);

  const ResourceKind(this.label, this.icon);
  final String label;
  final IconData icon;
}

@immutable
class GrowthResource {
  const GrowthResource({
    required this.name,
    required this.url,
    required this.kind,
    required this.tagline,
    required this.color,
    this.mark,
  });

  final String name;
  final String url;
  final ResourceKind kind;
  final String tagline;
  final Color color;

  /// Short text shown in the logo tile. Defaults to the first letter.
  final String? mark;

  String get host => Uri.parse(url).host.replaceFirst('www.', '');
}

const growthResources = [
  GrowthResource(
    name: 'Luma',
    url: 'https://lu.ma',
    kind: ResourceKind.events,
    color: Color(0xFFEA580C),
    tagline: 'Tech and startup meetups, demo days, founder dinners, and AI events.',
  ),
  GrowthResource(
    name: 'Meetup',
    url: 'https://www.meetup.com',
    kind: ResourceKind.events,
    color: Color(0xFFF64060),
    tagline: 'Local groups that meet regularly around a shared interest.',
  ),
  GrowthResource(
    name: 'Eventbrite',
    url: 'https://www.eventbrite.com',
    kind: ResourceKind.events,
    color: Color(0xFFF05537),
    tagline: 'Conferences, workshops, and career events near you.',
  ),
  GrowthResource(
    name: 'Handshake',
    url: 'https://joinhandshake.com',
    kind: ResourceKind.events,
    color: Color(0xFF1E1E1E),
    tagline: 'Career fairs, employer info sessions, and jobs for students and new grads.',
  ),
  GrowthResource(
    name: 'Devpost',
    url: 'https://devpost.com',
    kind: ResourceKind.events,
    color: Color(0xFF0B4F6C),
    tagline: 'Online and in-person hackathons with sponsors, judges, and builders.',
  ),
  GrowthResource(
    name: 'Major League Hacking',
    url: 'https://mlh.io',
    kind: ResourceKind.events,
    color: Color(0xFFE73427),
    mark: 'MLH',
    tagline: 'The student hackathon season, global hack weeks, and the MLH Fellowship.',
  ),
  GrowthResource(
    name: 'Partiful',
    url: 'https://partiful.com',
    kind: ResourceKind.events,
    color: Color(0xFF9333EA),
    tagline: 'Casual invites, where a lot of community and after-hours events live.',
  ),
  GrowthResource(
    name: 'Built In',
    url: 'https://builtin.com',
    kind: ResourceKind.events,
    color: Color(0xFF2E5BFF),
    tagline: 'Tech companies, jobs, and local events by city.',
  ),
  GrowthResource(
    name: 'LinkedIn',
    url: 'https://www.linkedin.com',
    kind: ResourceKind.community,
    color: Color(0xFF0A66C2),
    mark: 'in',
    tagline: 'Stay connected with everyone you meet and see who they know.',
  ),
  GrowthResource(
    name: 'Discord',
    url: 'https://discord.com',
    kind: ResourceKind.community,
    color: Color(0xFF5865F2),
    tagline: 'Developer, open-source, and campus servers where people actually chat.',
  ),
  GrowthResource(
    name: 'GitHub',
    url: 'https://github.com',
    kind: ResourceKind.community,
    color: Color(0xFF24292F),
    tagline: 'Contribute to open source and get to know maintainers through your work.',
  ),
  GrowthResource(
    name: 'Reddit',
    url: 'https://www.reddit.com',
    kind: ResourceKind.community,
    color: Color(0xFFFF4500),
    tagline: 'Career and city communities, from r/cscareerquestions to local meetups.',
  ),
  GrowthResource(
    name: 'ADPList',
    url: 'https://adplist.org',
    kind: ResourceKind.community,
    color: Color(0xFF2563EB),
    tagline: 'Free one-on-one mentorship with people in tech, design, and product.',
  ),
  GrowthResource(
    name: 'Fishbowl',
    url: 'https://www.fishbowlapp.com',
    kind: ResourceKind.community,
    color: Color(0xFF0D9488),
    tagline: 'Industry groups for candid questions about companies, roles, and pay.',
  ),
  GrowthResource(
    name: 'Wellfound',
    url: 'https://wellfound.com',
    kind: ResourceKind.community,
    color: Color(0xFF111827),
    tagline: 'Startup network where you can message founders and hiring teams directly.',
  ),
  GrowthResource(
    name: 'Peerlist',
    url: 'https://peerlist.io',
    kind: ResourceKind.community,
    color: Color(0xFF00AA45),
    tagline: 'A profile for builders to show their work and meet other makers.',
  ),
  GrowthResource(
    name: 'YC Co-Founder Matching',
    url: 'https://www.ycombinator.com/cofounder-matching',
    kind: ResourceKind.community,
    color: Color(0xFFF26522),
    mark: 'Y',
    tagline: 'Meet potential co-founders if you\'re starting something.',
  ),
  GrowthResource(
    name: 'Toastmasters',
    url: 'https://www.toastmasters.org',
    kind: ResourceKind.community,
    color: Color(0xFF772432),
    tagline: 'Weekly local clubs that build speaking confidence and a steady network.',
  ),
];
