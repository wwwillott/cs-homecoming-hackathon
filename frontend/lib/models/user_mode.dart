enum UserMode {
  seeker(
    label: 'Job seeker',
    description: 'Find, grow, and lean on the people you know.',
    strengthLabel: 'Connection strength',
    strengthHint: 'How well do you know them?',
  ),
  recruiter(
    label: 'Recruiter',
    description: 'Remember the standout people you meet.',
    strengthLabel: 'Impression',
    strengthHint: 'How impressed were you?',
  );

  const UserMode({
    required this.label,
    required this.description,
    required this.strengthLabel,
    required this.strengthHint,
  });

  final String label;
  final String description;
  final String strengthLabel;
  final String strengthHint;

  static UserMode fromName(String? name) =>
      UserMode.values.firstWhere((m) => m.name == name, orElse: () => UserMode.seeker);
}
