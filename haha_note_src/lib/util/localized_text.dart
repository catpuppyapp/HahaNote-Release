import '../cloud_disk_note/storage/repo/repo.dart';
import '../cloud_disk_note/storage/repo/sync.dart';
import '../i18n/strings.g.dart';

// 关联函数 MergeMode.toText，要改连关联函数一起改
String mergeModeToLocalizedText(int mergeMode) {
  if (mergeMode == MergeMode.mergeRemoteAndWorkdir) {
    return t.mergeRemoteAndWorkdir;
  }

  if (mergeMode == MergeMode.remoteOverwriteWorkdir) {
    return t.remoteOverwriteWorkdir;
  }

  return t.unknown;
}

  // 状态的文本描述
String repoStatusDesc(RepoStatus? repoStatus) {
  if(repoStatus == null) {
    return "";
  }

  if(repoStatus.value == RepoStatusVal.clean) {
    return t.noChanges;
  }

  if(repoStatus.value == RepoStatusVal.dirty) {
    return t.haveChangesNeedToSync;
  }

  if(repoStatus.value == RepoStatusVal.none) {
    return t.checking;
  }

  if(repoStatus.value == RepoStatusVal.err) {
    return repoStatus.msg;
  }

  return "";
}
