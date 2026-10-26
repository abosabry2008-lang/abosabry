import 'package:flutter/material.dart';

import '../core/theme.dart';

/// Unified header used by list screens: a page title, an optional action and a
/// consistent stack of search / filter controls.
///
/// The filter controls sit in a tinted toolbar band, the way SAP list reports
/// separate the header from the filter area.
class PageHeader extends StatelessWidget {
  const PageHeader({
    super.key,
    required this.title,
    this.subtitle,
    this.trailing,
    this.filters = const <Widget>[],
  });

  final String title;
  final String? subtitle;
  final Widget? trailing;
  final List<Widget> filters;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isLight = AppTheme.isLight(context);
    final border = theme.colorScheme.outlineVariant;
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 8),
      child: Container(
        clipBehavior: Clip.antiAlias,
        decoration: BoxDecoration(
          color: theme.colorScheme.surface,
          borderRadius: BorderRadius.circular(6),
          border: Border.all(color: border),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 10, 8, 10),
              child: Row(
                children: <Widget>[
                  Container(
                    width: 3,
                    height: 18,
                    margin: const EdgeInsetsDirectional.only(end: 9),
                    decoration: BoxDecoration(
                      color: theme.colorScheme.primary,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        Text(
                          title,
                          style: theme.textTheme.titleMedium?.copyWith(
                            fontSize: 16,
                            fontWeight: FontWeight.w600,
                            color: isLight
                                ? AppTheme.textPrimary
                                : theme.colorScheme.onSurface,
                          ),
                        ),
                        if (subtitle != null && subtitle!.isNotEmpty)
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
            if (filters.isNotEmpty)
              Container(
                padding: const EdgeInsets.fromLTRB(12, 9, 12, 10),
                decoration: BoxDecoration(
                  color: AppTheme.sectionHeaderColor(context),
                  border: Border(top: BorderSide(color: border)),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: <Widget>[
                    for (var index = 0; index < filters.length; index++) ...<Widget>[
                      if (index > 0) const SizedBox(height: 7),
                      filters[index],
                    ],
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }
}
