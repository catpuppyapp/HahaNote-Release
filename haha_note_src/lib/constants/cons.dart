


abstract class Cons {
  static final routeRepoCreate = '/repo/create';
  static final routeRepoEdit = '/repo/edit';
  static final routeRepoImport = '/repo/import';
  static final routeRepoOpen = '/repo/open';
  static final routeEditorOpen = '/editor/open';
  static final routeFileHistory = 'file/history';
  static final routeViewObject = '/view/object';
  static final routeConflictList = '/conflict/list';
  static final routeUserLogin = '/user/login';
  static final routeUserRegister = '/user/register';
  static final routeUserForgotPassword = '/user/forgotPassword';
  static final routeUserChangePassword = '/user/changePassword';
  static final routeUserChangeEmail = '/user/changeEmail';
  static final routeAbout = '/about';
  static final routeTlsCertManage = '/tls/certManage';
  static final routeSyncHistory = '/syncHistory';
  static final routeRedeem = '/redeem';
  static final routeRepoStatus = '/repo/status';
  static final routeMarkdownPreview = '/markdownPreview';


  static final homePageCodeHome = 1;
  static final homePageCodeRepo = 2;
  static final homePageCodeFiles = 3;
  static final homePageCodeEditor = 4;
  // static final homePageCodeLogout = 5;  // 登出无需保存为上次打开页面，所以设了变量也用不到
  static final homePageCodeSettings = 6;
  static final homePageCodeMsg = 7;
  static final homePageCodeDeleted = 8;
  static final homePageCodeAbout = 9;
  static final homePageCodeConflict = 10;
  // 显示的时候可以简化一些，显示个Recent就行
  static final homePageCodeRecentFiles = 11;

  static final zeroDateTime = DateTime.fromMillisecondsSinceEpoch(0, isUtc: true);



}
