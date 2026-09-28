


abstract class Cons {
  static const routeRepoCreate = '/repo/create';
  static const routeRepoEdit = '/repo/edit';
  static const routeRepoImport = '/repo/import';
  static const routeRepoOpen = '/repo/open';
  static const routeEditorOpen = '/editor/open';
  static const routeFileHistory = 'file/history';
  static const routeViewObject = '/view/object';
  static const routeConflictList = '/conflict/list';
  static const routeUserLogin = '/user/login';
  static const routeUserRegister = '/user/register';
  static const routeUserForgotPassword = '/user/forgotPassword';
  static const routeUserChangePassword = '/user/changePassword';
  static const routeUserChangeEmail = '/user/changeEmail';
  static const routeAbout = '/about';
  static const routeTlsCertManage = '/tls/certManage';
  static const routeSyncHistory = '/syncHistory';
  static const routeRedeem = '/redeem';
  static const routeRepoStatus = '/repo/status';
  static const routeMarkdownPreview = '/markdownPreview';


  static const homePageCodeHome = 1;
  static const homePageCodeRepo = 2;
  static const homePageCodeFiles = 3;
  static const homePageCodeEditor = 4;
  // static const homePageCodeLogout = 5;  // 登出无需保存为上次打开页面，所以设了变量也用不到
  static const homePageCodeSettings = 6;
  static const homePageCodeMsg = 7;
  static const homePageCodeDeleted = 8;
  static const homePageCodeAbout = 9;
  static const homePageCodeConflict = 10;
  // 显示的时候可以简化一些，显示个Recent就行
  static const homePageCodeRecentFiles = 11;

  static final zeroDateTime = DateTime.fromMillisecondsSinceEpoch(0, isUtc: true);



}
