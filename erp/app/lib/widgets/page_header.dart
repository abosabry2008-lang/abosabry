import 'package:flutter/material.dart';

import '../core/theme.dart';

/// Unified header used by list screens: a classic SAP GUI title bar, an
/// optional action and a dense stack of search / filter controls.
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
    final border = theme.colorScheme.outlineVariant;
    return Padding(
      padding: const EdgeInsets.fromLTRB(10, 10, 10, 7),
      child: Container(
        clipBehavior: Clip.antiAlias,
        decoration: BoxDecoration(
          color: theme.colorScheme.surface,
          borderRadius: BorderRadius.circular(3),
          border: Border.all(color: border),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            Container(
              padding: const EdgeInsets.fromLTRB(12, 8, 8, 8),
              decoration: const BoxDecoration(
                gradient: LinearGradient(
                  begin: AlignmentDirectional.centerStart,
                  end: AlignmentDirectional.centerEnd,
                  colors: <Color>[
                    AppTheme.titleBarStart,
                    AppTheme.titleBarEnd,
                  ],
                ),
              ),
              child: Row(
                children: <Widget>[
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        Text(
                          title,
                          style: theme.textTheme.titleMedium?.copyWith(
                            fontSize: 15,
                            fontWeight: FontWeight.w700,
                            color: Colors.white,
                          ),
                        ),
                        if (subtitle != null && subtitle!.isNotEmpty)
                          Padding(
                            padding: const EdgeInsets.only(top: 1),
                            child: Text(
                              subtitle!,
                              style: theme.textTheme.bodySmall?.copyWith(
                                fontSize: 10.5,
                                color: Colors.white70,
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
                padding: const EdgeInsets.fromLTRB(10, 7, 10, 8),
                decoration: BoxDecoration(
                  color: AppTheme.isLight(context)
                      ? const Color(0xFFEDF1F5)
                      : theme.colorScheme.surfaceContainerHigh,
                  border: Border(top: BorderSide(color: border)),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: <Widget>[
                    for (var index = 0; index < filters.length; index++) ...<Widget>[
                      if (index > 0) const SizedBox(height: 6),
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
