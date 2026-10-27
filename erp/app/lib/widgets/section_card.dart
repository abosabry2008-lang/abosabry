import 'package:flutter/material.dart';

import '../core/theme.dart';

/// A card with an optional title/subtitle header used to group form fields and
/// detail sections.
///
/// Styled like an SAP Fiori card / GUI group box: a tinted header band with a
/// thin border and a dense body. Behaviour is unchanged.
class SectionCard extends StatelessWidget {
  const SectionCard({
    super.key,
    this.title,
    this.subtitle,
    this.trailing,
    required this.child,
    this.padding = const EdgeInsets.all(10),
    this.headerColor,
    this.noBorder = false,
  });

  final String? title;
  final String? subtitle;
  final Widget? trailing;
  final Widget child;
  final EdgeInsetsGeometry padding;
  final Color? headerColor;

  /// Removes the outer border (used when the card sits inside another panel).
  final bool noBorder;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final hasHeader = title != null || trailing != null;
    final border = theme.colorScheme.outlineVariant;
    return Card(
      margin: EdgeInsets.zero,
      elevation: 0,
      color: theme.colorScheme.surface,
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(3),
        side: noBorder ? BorderSide.none : BorderSide(color: border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          if (hasHeader)
            Container(
              padding: const EdgeInsets.fromLTRB(10, 6, 6, 6),
              decoration: BoxDecoration(
                color: headerColor ?? AppTheme.sectionHeaderColor(context),
                border: Border(bottom: BorderSide(color: border)),
              ),
              child: Row(
                children: <Widget>[
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        if (title != null)
                          Text(
                            title!,
                            style: theme.textTheme.titleSmall?.copyWith(
                              fontWeight: FontWeight.w700,
                              color: AppTheme.groupTitleColor(context),
                            ),
                          ),
                        if (subtitle != null)
                          Padding(
                            padding: const EdgeInsets.only(top: 1),
                            child: Text(
                              subtitle!,
                              style: theme.textTheme.bodySmall?.copyWith(
                                color: theme.colorScheme.onSurfaceVariant,
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                  if (trailing != null) trailing!,
                ],
              ),
            ),
          Padding(
            padding: padding,
            child: child,
          ),
        ],
      ),
    );
  }
}
