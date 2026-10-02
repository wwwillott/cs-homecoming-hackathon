const _months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];

String shortDate(DateTime d) {
  final now = DateTime.now();
  final base = '${_months[d.month - 1]} ${d.day}';
  return d.year == now.year ? base : '$base, ${d.year}';
}

String relativePast(DateTime d) {
  final days = DateTime(DateTime.now().year, DateTime.now().month, DateTime.now().day)
      .difference(DateTime(d.year, d.month, d.day))
      .inDays;
  if (days <= 0) return 'Today';
  if (days == 1) return 'Yesterday';
  if (days < 7) return '${days}d ago';
  if (days < 30) return '${(days / 7).floor()}w ago';
  if (days < 365) return '${(days / 30).floor()}mo ago';
  return shortDate(d);
}

String relativeFuture(DateTime d) {
  final today = DateTime(DateTime.now().year, DateTime.now().month, DateTime.now().day);
  final days = DateTime(d.year, d.month, d.day).difference(today).inDays;
  if (days < -1) return '${-days}d overdue';
  if (days == -1) return 'Yesterday';
  if (days == 0) return 'Today';
  if (days == 1) return 'Tomorrow';
  if (days < 7) return 'In ${days}d';
  return shortDate(d);
}

String greeting() {
  final h = DateTime.now().hour;
  if (h < 12) return 'Good morning';
  if (h < 17) return 'Good afternoon';
  return 'Good evening';
}
