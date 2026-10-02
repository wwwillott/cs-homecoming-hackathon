import 'package:flutter/material.dart';

enum ResourceKind {
  events('Events', Icons.event_outlined),
  professional('Professional', Icons.work_outline),
  students('Students & new grads', Icons.school_outlined),
  community('Communities', Icons.forum_outlined),
  mentorship('Mentorship', Icons.volunteer_activism_outlined);

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
    required this.seekerTip,
    required this.color,
    this.recruiterTip,
    this.mark,
  });

  final String name;
  final String url;
  final ResourceKind kind;
  final String tagline;
  final String seekerTip;

  /// Null when the app isn't especially useful for recruiters.
  final String? recruiterTip;
  final Color color;

  /// Short text shown in the logo tile. Defaults to the first letter.
  final String? mark;

  String get host => Uri.parse(url).host.replaceFirst('www.', '');
}

const growthResources = [
  GrowthResource(
    name: 'LinkedIn',
    url: 'https://www.linkedin.com',
    kind: ResourceKind.professional,
    color: Color(0xFF0A66C2),
    mark: 'in',
    tagline: 'Stay connected with everyone you meet and see who they know.',
    seekerTip: 'Connect within a day of meeting someone, with a one-line note about where you met.',
    recruiterTip: 'Search alumni and second-degree connections before reaching out cold.',
  ),
  GrowthResource(
    name: 'Handshake',
    url: 'https://joinhandshake.com',
    kind: ResourceKind.students,
    color: Color(0xFF1E1E1E),
    tagline: 'Career fairs, employer info sessions, and jobs for students and new grads.',
    seekerTip: 'RSVP to virtual info sessions. Small groups make it easy to ask real questions.',
    recruiterTip: 'Host info sessions and message students who match your roles.',
  ),
  GrowthResource(
    name: 'Luma',
    url: 'https://lu.ma',
    kind: ResourceKind.events,
    color: Color(0xFFEA580C),
    tagline: 'Tech and startup meetups, demo days, founder dinners, and AI events.',
    seekerTip: 'Follow a few local calendars. The same people show up again, which makes a second hello easy.',
    recruiterTip: 'Host a small technical meetup. It brings the right people to you.',
  ),
  GrowthResource(
    name: 'Meetup',
    url: 'https://www.meetup.com',
    kind: ResourceKind.events,
    color: Color(0xFFF64060),
    tagline: 'Local groups that meet regularly around a shared interest.',
    seekerTip: 'Pick one group and go three times. Regulars become real connections.',
    recruiterTip: 'Sponsor pizza at a local dev group in exchange for a two-minute intro.',
  ),
  GrowthResource(
    name: 'Eventbrite',
    url: 'https://www.eventbrite.com',
    kind: ResourceKind.events,
    color: Color(0xFFF05537),
    tagline: 'Conferences, workshops, and career events near you.',
    seekerTip: 'Search your city plus your field, like "Salt Lake City tech" or "Provo product".',
  ),
  GrowthResource(
    name: 'Partiful',
    url: 'https://partiful.com',
    kind: ResourceKind.events,
    color: Color(0xFF9333EA),
    tagline: 'Casual invites, where a lot of community and after-hours events live.',
    seekerTip: 'Ask the people you meet what they\'re going to next. Invites spread by word of mouth.',
  ),
  GrowthResource(
    name: 'Devpost',
    url: 'https://devpost.com',
    kind: ResourceKind.events,
    color: Color(0xFF0B4F6C),
    tagline: 'Online and in-person hackathons with sponsors, judges, and builders.',
    seekerTip: 'Hackathons are the fastest way to work alongside people and impress sponsors.',
    recruiterTip: 'Sponsor a hackathon and judge. You see how people actually build.',
  ),
  GrowthResource(
    name: 'Major League Hacking',
    url: 'https://mlh.io',
    kind: ResourceKind.students,
    color: Color(0xFFE73427),
    mark: 'MLH',
    tagline: 'The student hackathon season, global hack weeks, and the MLH Fellowship.',
    seekerTip: 'Check the season calendar for hackathons within driving distance.',
    recruiterTip: 'Partner on a hackathon to meet student builders early.',
  ),
  GrowthResource(
    name: 'ADPList',
    url: 'https://adplist.org',
    kind: ResourceKind.mentorship,
    color: Color(0xFF2563EB),
    tagline: 'Free one-on-one mentorship with people in tech, design, and product.',
    seekerTip: 'Book a 30-minute call with someone one or two steps ahead of you.',
  ),
  GrowthResource(
    name: 'Wellfound',
    url: 'https://wellfound.com',
    kind: ResourceKind.professional,
    color: Color(0xFF111827),
    tagline: 'Startup jobs where you can message founders and hiring teams directly.',
    seekerTip: 'Write a short, specific note to the founder. Early-stage teams read them.',
    recruiterTip: 'Post roles and reach candidates who want startup work.',
  ),
  GrowthResource(
    name: 'YC Co-Founder Matching',
    url: 'https://www.ycombinator.com/cofounder-matching',
    kind: ResourceKind.community,
    color: Color(0xFFF26522),
    mark: 'Y',
    tagline: 'Meet potential co-founders if you\'re starting something.',
    seekerTip: 'Even if you aren\'t ready to start, it\'s a great way to meet builders.',
  ),
  GrowthResource(
    name: 'Fishbowl',
    url: 'https://www.fishbowlapp.com',
    kind: ResourceKind.community,
    color: Color(0xFF0D9488),
    tagline: 'Industry groups for candid questions about companies, roles, and pay.',
    seekerTip: 'Ask how a team really works before you interview there.',
  ),
  GrowthResource(
    name: 'Discord',
    url: 'https://discord.com',
    kind: ResourceKind.community,
    color: Color(0xFF5865F2),
    tagline: 'Developer, open-source, and campus servers where people actually chat.',
    seekerTip: 'Answer questions in a community you care about. Helping is the best introduction.',
    recruiterTip: 'Join tech community servers and contribute before you recruit.',
  ),
  GrowthResource(
    name: 'Reddit',
    url: 'https://www.reddit.com',
    kind: ResourceKind.community,
    color: Color(0xFFFF4500),
    tagline: 'Career and city communities, from r/cscareerquestions to local meetups.',
    seekerTip: 'Your city\'s subreddit often lists meetups that aren\'t posted anywhere else.',
  ),
  GrowthResource(
    name: 'GitHub',
    url: 'https://github.com',
    kind: ResourceKind.community,
    color: Color(0xFF24292F),
    tagline: 'Contribute to open source and get to know maintainers through your work.',
    seekerTip: 'A merged pull request is a better intro than any cold message.',
    recruiterTip: 'Find engineers through the projects they contribute to.',
  ),
  GrowthResource(
    name: 'Built In',
    url: 'https://builtin.com',
    kind: ResourceKind.professional,
    color: Color(0xFF2E5BFF),
    tagline: 'Tech companies, jobs, and local events by city.',
    seekerTip: 'Use company pages to find teams to research before an event.',
    recruiterTip: 'Show off your team and culture to local tech talent.',
  ),
  GrowthResource(
    name: 'Peerlist',
    url: 'https://peerlist.io',
    kind: ResourceKind.professional,
    color: Color(0xFF00AA45),
    tagline: 'A profile for builders to show their work and meet other makers.',
    seekerTip: 'Share side projects and follow people building things you like.',
    recruiterTip: 'Browse real project work, not just resumes.',
  ),
  GrowthResource(
    name: 'Toastmasters',
    url: 'https://www.toastmasters.org',
    kind: ResourceKind.community,
    color: Color(0xFF772432),
    tagline: 'Weekly local clubs that build speaking confidence and a steady network.',
    seekerTip: 'Practicing your intro in a friendly room makes events far less stressful.',
  ),
];
