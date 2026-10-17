import 'package:flutter/material.dart';

import '../core/l10n.dart';
import '../state/paged_list_controller.dart';
import 'empty_state.dart';
import 'error_view.dart';

/// Generic list view for a [PagedListController].
///
/// Handles the loading / empty / error states, pull-to-refresh and automatic
/// "load more" pagination when the user reaches the bottom.
class AsyncListView<T> extends StatefulWidget {
  const AsyncListView({
    super.key,
    required this.controller,
    required this.itemBuilder,
    this.header,
    this.emptyTitle,
    this.emptyMessage,
    this.emptyIcon = Icons.inbox_outlined,
    this.emptyAction,
    this.padding = const EdgeInsets.fromLTRB(12, 8, 12, 96),
    this.separator = true,
  });

  final PagedListController<T> controller;
  final Widget Function(BuildContext context, T item, int index) itemBuilder;
  final Widget? header;
  final String? emptyTitle;
  final String? emptyMessage;
  final IconData emptyIcon;
  final Widget? emptyAction;
  final EdgeInsets padding;
  final bool separator;

  @override
  State<AsyncListView<T>> createState() => _AsyncListViewState<T>();
}

class _AsyncListViewState<T> extends State<AsyncListView<T>> {
  final ScrollController _scrollController = ScrollController();

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_onScroll);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) widget.controller.ensureLoaded();
    });
  }

  @override
  void didUpdateWidget(covariant AsyncListView<T> oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller != widget.controller) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) widget.controller.ensureLoaded();
      });
    }
  }

  @override
  void dispose() {
    _scrollController.removeListener(_onScroll);
    _scrollController.dispose();
    super.dispose();
  }

  void _onScroll() {
    if (!_scrollController.hasClients) return;
    final position = _scrollController.position;
    if (position.pixels >= position.maxScrollExtent - 400) {
      widget.controller.loadMore();
    }
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: widget.controller,
      builder: (context, _) {
        final controller = widget.controller;

        if (controller.loading && controller.items.isEmpty) {
          return const Center(child: CircularProgressIndicator());
        }

        if (controller.error != null && controller.items.isEmpty) {
          return ErrorView(
            message: controller.error!,
            onRetry: controller.refresh,
          );
        }

        if (controller.items.isEmpty) {
          return RefreshIndicator(
            onRefresh: controller.refresh,
            child: ListView(
              physics: const AlwaysScrollableScrollPhysics(),
              children: <Widget>[
                SizedBox(height: MediaQuery.sizeOf(context).height * 0.12),
                EmptyState(
                  icon: widget.emptyIcon,
                  title: widget.emptyTitle ?? context.s.nothingHereYet,
                  message: widget.emptyMessage,
                  action: widget.emptyAction,
                ),
              ],
            ),
          );
        }

        final items = controller.items;
        final headerCount = widget.header == null ? 0 : 1;
        final footerCount = controller.hasMore || controller.loadingMore ? 1 : 0;

        return RefreshIndicator(
          onRefresh: controller.refresh,
          child: ListView.builder(
            controller: _scrollController,
            physics: const AlwaysScrollableScrollPhysics(),
            padding: widget.padding,
            itemCount: headerCount + items.length + footerCount,
            itemBuilder: (context, index) {
              if (widget.header != null && index == 0) {
                return widget.header!;
              }
              final itemIndex = index - headerCount;
              if (itemIndex < items.length) {
                final card = widget.itemBuilder(context, items[itemIndex], itemIndex);
                if (!widget.separator) return card;
                return Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: card,
                );
              }
              return const Padding(
                padding: EdgeInsets.symmetric(vertical: 20),
                child: Center(child: CircularProgressIndicator()),
              );
            },
          ),
        );
      },
    );
  }
}
