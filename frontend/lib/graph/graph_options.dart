import 'package:flutter/material.dart';

enum ColorBy {
  strength('Strength', Icons.local_fire_department_outlined),
  category('Relationship', Icons.category_outlined),
  company('Company', Icons.apartment_outlined),
  metAt('Where you met', Icons.place_outlined),
  recency('Last contact', Icons.schedule_outlined);

  const ColorBy(this.label, this.icon);
  final String label;
  final IconData icon;
}

enum SizeBy {
  strength('Strength', Icons.bar_chart_rounded),
  connections('Connections', Icons.hub_outlined),
  recency('Recency', Icons.bolt_outlined),
  uniform('Uniform', Icons.circle_outlined);

  const SizeBy(this.label, this.icon);
  final String label;
  final IconData icon;
}
