import 'package:cloud_disk_note_app/i18n/strings.g.dart';
import 'package:cloud_disk_note_app/ui/ui.dart';
import 'package:cloud_disk_note_app/widget/base_layout.dart';
import 'package:flutter/material.dart';

class PullToRefreshList extends StatefulWidget {
  final bool loading;
  final String err;
  final bool listIsEmpty;
  // 若有专门更新进度的字段，就传字段过来，若只想在loading时显示个正在加载则别传，
  // 因为当 loading 为true时本组件会自动显示 正在加载
  final String progressText;
  final Future<void> Function() onRefresh;
  final Widget child;
  final String? listEmptyText;

  const PullToRefreshList({
    super.key,
    required this.loading,
    required this.err,
    required this.listIsEmpty,
    this.progressText = "",
    required this.onRefresh,
    required this.child,
    this.listEmptyText,
  });

  @override
  State<StatefulWidget> createState() => _PullToRefreshListState();

}

class _PullToRefreshListState extends State<PullToRefreshList> {
  final GlobalKey<RefreshIndicatorState> refreshIndicatorKey = GlobalKey();

  @override
  Widget build(BuildContext context) {
    return RefreshIndicator(
      key: refreshIndicatorKey,
      onRefresh: () async {
        if(widget.loading) {
          // 正在loading则禁止刷新
          return;
        }

        // 显示加载指示器，就是转圈那个东西
        refreshIndicatorKey.currentState?.show();
        await widget.onRefresh();
        // 函数返回自动解除加载，无需手动hide加载指示器（也没有手动hide的函数）
      },
      child: widget.loading || widget.listIsEmpty || widget.err.isNotEmpty ?
      BaseLayout.defaultScreenPaddingContainer(
        child: SingleChildScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          child: SizedBox(
            height: MediaQuery.of(context).size.height / 2, // 使其可滚动占满高度
            child: Center(
              child: SelectableText(
                widget.progressText.isNotEmpty
                  ? widget.progressText
                  : widget.loading
                  ? t.loading
                  : widget.err.isNotEmpty
                  ? widget.err
                  : widget.listIsEmpty
                  ? widget.listEmptyText ?? t.nothing
                  : ""  // should never reach here, due to if list is not empty ,will show list view
                , style: TextStyle(color: widget.err.isNotEmpty ? UI.getColorErr() : null),),
            )
          ),
        )
      ) : widget.child
    );
  }

}