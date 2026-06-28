

const _keySync = "Sync";
const _keySyncHistory = "SyncHistory";
const _keyRepoStatus = "RepoStatus";
const _keySave = "Save";  // save editor content
const _keyPreview = "Preview";  // editor preiview markdown
const _keyUndo = "Undo";  // editor undo
const _keyRedo = "Redo";  // editor redo

const Map<String, String> shortCutTable = {
  // 据我观察桌面软件，快捷键字符串不应有空格，例如 "Ctrl+T" 是常见的，"Ctrl + T" 不常见
  _keySync: "Ctrl+T",
  _keySyncHistory: "Ctrl+H",
  _keyRepoStatus: "Ctrl+G",
  _keySave: "Ctrl+S",
  _keyPreview: "Ctrl+P",
  _keyUndo: "Ctrl+Z",
  _keyRedo: "Ctrl+Shift+Z",
};

abstract class ShortCuts {
  static String getKeyBindingOfSync() {
    return shortCutTable[_keySync]!;
  }

  static String getKeyBindingOfSyncHistory() {
    return shortCutTable[_keySyncHistory]!;
  }

  static String getKeyBindingOfRepoStatus() {
    return shortCutTable[_keyRepoStatus]!;
  }

  static String getKeyBindingOfSave() {
    return shortCutTable[_keySave]!;
  }

  static String getKeyBindingOfPreview() {
    return shortCutTable[_keyPreview]!;
  }

  static String getKeyBindingOfUndo() {
    return shortCutTable[_keyUndo]!;
  }

  static String getKeyBindingOfRedo() {
    return shortCutTable[_keyRedo]!;
  }

}
