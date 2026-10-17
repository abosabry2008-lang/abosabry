import 'package:flutter/material.dart';

import '../core/formatters.dart';
import '../core/l10n.dart';

/// An outlined button that opens a date-range picker.
///
/// Shows `s.dateRange` while no range is chosen, or the formatted
/// `from – to` range once dates have been picked.
class DateRangeButton extends StatelessWidget {
  const DateRangeButton({
    super.key,
    required this.from,
    required this.to,
    required this.onChanged,
  });

  final DateTime? from;
  final DateTime? to;
  final void Function(DateTime? from, DateTime? to) onChanged;

  @override
  Widget build(BuildContext context) {
    final s = context.s;
    final hasRange = from != null || to != null;
    return OutlinedButton.icon(
      onPressed: () async {
        final now = DateTime.now();
        final picked = await showDateRangePicker(
          context: context,
          firstDate: DateTime(now.year - 5),
          lastDate: DateTime(now.year + 5),
          initialDateRange: (from != null && to != null)
              ? DateTimeRange(start: from!, end: to!)
              : null,
        );
        if (picked != null) onChanged(picked.start, picked.end);
      },
      icon: const Icon(Icons.event_outlined),
      label: Text(
        hasRange
            ? '${Formatters.date(from)} – ${Formatters.date(to)}'
            : s.dateRange,
        overflow: TextOverflow.ellipsis,
      ),
    );
  }
}
