import 'package:flutter/material.dart';

import '../core/l10n.dart';
import 'form_fields.dart';

/// Mandatory day picker plus a search button, shown above list screens.
class DaySearchRow extends StatelessWidget {
  const DaySearchRow({
    super.key,
    required this.day,
    required this.onDayChanged,
    required this.onSearch,
  });

  final DateTime day;
  final ValueChanged<DateTime> onDayChanged;
  final VoidCallback onSearch;

  @override
  Widget build(BuildContext context) {
    final s = context.s;
    return Row(
      children: <Widget>[
        Expanded(
          child: AppDateField(
            label: s.date,
            value: day,
            clearable: false,
            onChanged: (value) {
              if (value != null) onDayChanged(value);
            },
          ),
        ),
        const SizedBox(width: 8),
        FilledButton.tonalIcon(
          onPressed: onSearch,
          icon: const Icon(Icons.search),
          label: Text(s.search),
        ),
      ],
    );
  }
}
