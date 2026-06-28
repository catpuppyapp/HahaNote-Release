import 'package:cloud_disk_note_app/bean/bean.dart' show LabelValue;
import 'package:cloud_disk_note_app/cloud_disk_note/app.dart';
import 'package:cloud_disk_note_app/cloud_disk_note/remotes/base/remote.dart';
import 'package:cloud_disk_note_app/cloud_disk_note/storage/files/file_info.dart';
import 'package:cloud_disk_note_app/cloud_disk_note/storage/repo/repo.dart';
import 'package:cloud_disk_note_app/cloud_disk_note/storage/versioning/version.dart';
import 'package:cloud_disk_note_app/constants/cons.dart' show Cons;
import 'package:cloud_disk_note_app/db/db.dart';
import 'package:cloud_disk_note_app/db/entity/repo_entity.dart';
import 'package:cloud_disk_note_app/i18n/strings.g.dart';
import 'package:cloud_disk_note_app/page/base/searchable_page_state.dart';
import 'package:cloud_disk_note_app/util/fs.dart' show Fs;
import 'package:cloud_disk_note_app/util/util.dart' show formatDateTimeHumanFriendly;
import 'package:cloud_disk_note_app/widget/list.dart';
import 'package:flutter/material.dart';

const _TAG = "file_history.dart";


class FileHistoryPage extends StatefulWidget {
  // 文件在仓库下的相对路径
  final String path;

  const FileHistoryPage({super.key, required this.path});

  @override
  State<FileHistoryPage> createState() => _FileHistoryPageState();

}

class _FileHistoryPageState extends SearchablePageState<FileHistoryPage> {
  RepoEntity? openedRepo;
  late final String path;
  String currentClientId = "";

  Future<void> _view(VersionOid oid) async {
    if(!mounted) return;

    Navigator.pushNamed(
      context,
      Cons.routeViewObject,
      // 解密过的obj的2进制文件
      arguments: {"path": path, "oid": oid.value}
    );
  }

  @override
  Future<void> doLoadItems() async {
    if(path.isEmpty) {
      App.logger.debug(_TAG, "path is empty, will return empty list");
      items = [];
      return;
    }

    final repoFromDb = await Db.getOpenedRepo();
    openedRepo = repoFromDb;
    if (repoFromDb == null) {
      setState(() {
        err = "Opened repo is null";
      });
      return;
    }

    final repo = await Repo.open(repoFromDb.path);
    currentClientId = repo.client.id;

    final tempDir = await repo.createTempDir('file_history');
    try {
      final contentKeyData = await repo.getContentKey();
      final FileInfo? fileInfo = await repo.getTypedLocalData(
        RemoteDataType.files,
        await FileInfo.pathToOid(path, contentKeyData),
        repo.getRemoteDataDirPath(),
        tempDir,
      );

      // 如果文件未同步过（untracked），所以，有可能无历史
      final history = <VersionNode>[];
      if (fileInfo != null) {
        history.addAll(fileInfo.history);

        // 不删除删除节点了，显示吧，知道什么时候删过
        // for(final i in fileInfo.history) {
        //   // 把删除节点去掉，没必要显示
        //   if(!ObjRef.isInvalidOid(i.oid.value)) {
        //     history.add(i);
        //   }
        // }
      }

      //时间降序排列（其实直接reverse再toList()就行，实际上只执行一次循环，因为中间生成的iterable相当于是个胖指针，并不会实际执行迭代）
      // history.sort((a, b) => b.createTime.utcMs.compareTo(a.createTime.utcMs));

      items = history.reversed.toList();
    } finally {
      await tempDir.clean();
    }
  }

  @override
  List<Widget> getActions() {
    return [
      IconButton(
        icon: Icon(Icons.refresh),
        tooltip: t.refresh,
        onPressed: () {
          loadItems();
        },
      )
    ];
  }

  @override
  void initBase() {
    super.title = t.history;
    path = widget.path;

    WidgetsBinding.instance.addPostFrameCallback((_) {
      requireLogin();
    });
  }

  @override
  Widget itemBuilder<T>(BuildContext context, int index, T item) {
    item as VersionNode;

    return LabelValueTile(
      items: [
        LabelValue(label: t.oid, value: item.oid.shortValue(), icon: Icons.commit),
        LabelValue(label: t.createTime, value: formatDateTimeHumanFriendly(item.createTime.toDateTime()), icon: Icons.access_time_outlined),
        LabelValue(label: t.tag, value: item.tag.toString(), icon: Icons.label_outline),
        LabelValue(label: t.size, value: Fs.humanFriendlySize(item.fileSizeInBytes), icon: Icons.sd_storage_outlined),
        LabelValue(label: t.client, value: item.client.name, icon: Icons.devices, valueFontWeight: item.client.id == currentClientId ? FontWeight.bold : null),
        // 如果是冲突覆盖，这里会显示谁覆盖了谁，以及冲突msg id
        if(item.note.isNotEmpty) LabelValue(label: t.note, value: item.note, icon: Icons.notes),
      ], 
      onTap: () {
        _view(item.oid);
      },
      menuItems: [],
    );
  }

  @override
  Future<bool> searchMatcher(String keyword, dynamic item) async {
    item as VersionNode;

    return item.oid.shortValue().toLowerCase().contains(keyword) ||
        item.oid.value == keyword ||  // 可精确匹配完整oid
        formatDateTimeHumanFriendly(item.createTime.toDateTime()).toLowerCase().contains(keyword) ||
        item.tag.toString().toLowerCase().contains(keyword) ||
        Fs.readableSize(item.fileSizeInBytes).toLowerCase().contains(keyword) ||
        item.note.toLowerCase().contains(keyword);
  }

  @override
  List<Widget> underSearchBarAboveListChildren() {
    return defaultUnderSearchBarAboveListChildren(path);
  }

}

