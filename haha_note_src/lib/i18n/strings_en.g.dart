///
/// Generated file. Do not edit.
///
// coverage:ignore-file
// ignore_for_file: type=lint, unused_import
// dart format off

part of 'strings.g.dart';

// Path: <root>
typedef TranslationsEn = Translations; // ignore: unused_element
class Translations with BaseTranslations<AppLocale, Translations> {
	/// Returns the current translations of the given [context].
	///
	/// Usage:
	/// final t = Translations.of(context);
	static Translations of(BuildContext context) => InheritedLocaleData.of<AppLocale, Translations>(context).translations;

	/// You can call this constructor and build your own translation instance of this locale.
	/// Constructing via the enum [AppLocale.build] is preferred.
	Translations({Map<String, Node>? overrides, PluralResolver? cardinalResolver, PluralResolver? ordinalResolver, TranslationMetadata<AppLocale, Translations>? meta})
		: assert(overrides == null, 'Set "translation_overrides: true" in order to enable this feature.'),
		  $meta = meta ?? TranslationMetadata(
		    locale: AppLocale.en,
		    overrides: overrides ?? {},
		    cardinalResolver: cardinalResolver,
		    ordinalResolver: ordinalResolver,
		  ) {
		$meta.setFlatMapFunction(_flatMapFunction);
	}

	/// Metadata for the translations of <en>.
	@override final TranslationMetadata<AppLocale, Translations> $meta;

	/// Access flat map
	dynamic operator[](String key) => $meta.getTranslation(key);

	late final Translations _root = this; // ignore: unused_field

	Translations $copyWith({TranslationMetadata<AppLocale, Translations>? meta}) => Translations(meta: meta ?? this.$meta);

	// Translations

	/// en: 'HahaNote'
	String get appName => 'HahaNote';

	/// en: 'HahaNote is an e2ee note-taking and syncing app'
	String get appDesc => 'HahaNote is an e2ee note-taking and syncing app';

	/// en: 'Create'
	String get create => 'Create';

	/// en: 'Import'
	String get import => 'Import';

	/// en: 'Open'
	String get open => 'Open';

	/// en: 'Edit'
	String get edit => 'Edit';

	/// en: 'Unknown'
	String get unknown => 'Unknown';

	/// en: 'Username'
	String get username => 'Username';

	/// en: 'Password'
	String get password => 'Password';

	/// en: 'Host'
	String get host => 'Host';

	/// en: 'Authorize'
	String get authorize => 'Authorize';

	/// en: 'Remote Path'
	String get remotePath => 'Remote Path';

	/// en: 'Local Path'
	String get localPath => 'Local Path';

	/// en: 'Choose'
	String get choose => 'Choose';

	/// en: 'Submit'
	String get submit => 'Submit';

	/// en: 'Cancel'
	String get cancel => 'Cancel';

	/// en: 'Master Password'
	String get masterPassword => 'Master Password';

	/// en: 'Invalid Email'
	String get invalidEmail => 'Invalid Email';

	/// en: 'Please Input'
	String get pleaseInput => 'Please Input';

	/// en: 'Please complete the Dropbox authorization'
	String get pleaseAuthorizeDropbox => 'Please complete the Dropbox authorization';

	/// en: 'Repo already added'
	String get repoAlreadyAdded => 'Repo already added';

	/// en: 'Local repo path already exists'
	String get localRepoPathAlreadyExists => 'Local repo path already exists';

	/// en: 'Local repo path is not empty'
	String get localRepoPathIsNotEmpty => 'Local repo path is not empty';

	/// en: 'Unknown remote type'
	String get unknownRemoteType => 'Unknown remote type';

	/// en: 'Remote path already exists'
	String get remotePathAlreadyExists => 'Remote path already exists';

	/// en: 'Remote path doesn't exist'
	String get remotePathDoesntExist => 'Remote path doesn\'t exist';

	/// en: 'Unknown mode'
	String get unknownMode => 'Unknown mode';

	/// en: 'Home'
	String get home => 'Home';

	/// en: 'Repo'
	String get repo => 'Repo';

	/// en: 'Files'
	String get files => 'Files';

	/// en: 'Editor'
	String get editor => 'Editor';

	/// en: 'Logout'
	String get logout => 'Logout';

	/// en: 'Invalid path'
	String get invalidPath => 'Invalid path';

	/// en: 'Path is not absolute'
	String get pathIsNotAbsolute => 'Path is not absolute';

	/// en: 'Remote type'
	String get remoteType => 'Remote type';

	/// en: 'Sync'
	String get sync => 'Sync';

	/// en: 'Reload'
	String get reload => 'Reload';

	/// en: 'Close'
	String get close => 'Close';

	/// en: 'Conflict'
	String get conflict => 'Conflict';

	/// en: 'About'
	String get about => 'About';

	/// en: 'There are $count conflicts'
	String thereAreConflicts({required Object count}) => 'There are ${count} conflicts';

	/// en: 'Check'
	String get check => 'Check';

	/// en: 'Info'
	String get info => 'Info';

	/// en: 'Name'
	String get name => 'Name';

	/// en: 'Path'
	String get path => 'Path';

	/// en: 'Size'
	String get size => 'Size';

	/// en: 'Modified time'
	String get modifiedTime => 'Modified time';

	/// en: 'Recycle Bin'
	String get recycleBin => 'Recycle Bin';

	/// en: 'Rename'
	String get rename => 'Rename';

	/// en: 'OK'
	String get ok => 'OK';

	/// en: 'Delete'
	String get delete => 'Delete';

	/// en: 'Are you sure?'
	String get areYouSure => 'Are you sure?';

	/// en: 'Open in External'
	String get openInExt => 'Open in External';

	/// en: 'Copy path'
	String get copyPath => 'Copy path';

	/// en: 'New'
	String get tNew => 'New';

	/// en: 'Folder'
	String get folder => 'Folder';

	/// en: 'File'
	String get file => 'File';

	/// en: 'Search'
	String get search => 'Search';

	/// en: 'Empty'
	String get empty => 'Empty';

	/// en: 'Nothing found'
	String get nothingFound => 'Nothing found';

	/// en: 'Loading...'
	String get loading => 'Loading...';

	/// en: 'Dir'
	String get dir => 'Dir';

	/// en: 'History'
	String get history => 'History';

	/// en: '$count selected'
	String countSelected({required Object count}) => '${count} selected';

	/// en: 'Copy'
	String get copy => 'Copy';

	/// en: 'Move'
	String get move => 'Move';

	/// en: 'Paste'
	String get paste => 'Paste';

	/// en: 'Back'
	String get back => 'Back';

	/// en: 'Type'
	String get type => 'Type';

	/// en: 'Last modified time'
	String get lastModifiedTime => 'Last modified time';

	/// en: 'Sort'
	String get sort => 'Sort';

	/// en: 'Ascending'
	String get ascending => 'Ascending';

	/// en: 'Folder first'
	String get folderFirst => 'Folder first';

	/// en: 'Apply to this folder only'
	String get applyToThisFolderOnly => 'Apply to this folder only';

	/// en: 'Find'
	String get find => 'Find';

	/// en: 'Previous'
	String get previous => 'Previous';

	/// en: 'Next'
	String get next => 'Next';

	/// en: 'None'
	String get none => 'None';

	/// en: 'Replace'
	String get replace => 'Replace';

	/// en: 'Replace All'
	String get replaceAll => 'Replace All';

	/// en: 'Cut'
	String get cut => 'Cut';

	/// en: 'Select All'
	String get selectAll => 'Select All';

	/// en: 'Recent'
	String get recent => 'Recent';

	/// en: 'Undo'
	String get undo => 'Undo';

	/// en: 'Redo'
	String get redo => 'Redo';

	/// en: 'Save'
	String get save => 'Save';

	/// en: 'Saved'
	String get saved => 'Saved';

	/// en: 'Unsaved data will lost'
	String get unsavedDateWillLost => 'Unsaved data will lost';

	/// en: 'Go to'
	String get goTo => 'Go to';

	/// en: 'Font Size'
	String get fontSize => 'Font Size';

	/// en: 'Auto'
	String get auto => 'Auto';

	/// en: 'Light'
	String get light => 'Light';

	/// en: 'Dark'
	String get dark => 'Dark';

	/// en: 'Require restart to apply new theme'
	String get requireRestartToApplyNewTheme => 'Require restart to apply new theme';

	/// en: 'Please login'
	String get pleaseLogin => 'Please login';

	/// en: 'Login or Register'
	String get loginOrRegister => 'Login or Register';

	/// en: 'Login'
	String get login => 'Login';

	/// en: 'Register'
	String get register => 'Register';

	/// en: 'Oid'
	String get oid => 'Oid';

	/// en: 'Create Time'
	String get createTime => 'Create Time';

	/// en: 'Tag'
	String get tag => 'Tag';

	/// en: 'Restore'
	String get restore => 'Restore';

	/// en: 'Export'
	String get export => 'Export';

	/// en: 'View'
	String get view => 'View';

	/// en: 'Delete All'
	String get deleteAll => 'Delete All';

	/// en: 'Local'
	String get local => 'Local';

	/// en: 'Workdir'
	String get workdir => 'Workdir';

	/// en: 'Remote'
	String get remote => 'Remote';

	/// en: 'Done'
	String get done => 'Done';

	/// en: 'Diff'
	String get diff => 'Diff';

	/// en: 'Canceling'
	String get canceling => 'Canceling';

	/// en: 'Forgot password'
	String get forgotPassword => 'Forgot password';

	/// en: 'Email'
	String get email => 'Email';

	/// en: 'Username invalid, allowed: $pattern, at least: $minLength'
	String usernameInvalid({required Object pattern, required Object minLength}) => 'Username invalid, allowed: ${pattern}, at least: ${minLength}';

	/// en: 'Password invalid, allowed: $pattern, at least: $minLength'
	String passwordInvalid({required Object pattern, required Object minLength}) => 'Password invalid, allowed: ${pattern}, at least: ${minLength}';

	/// en: 'Register success'
	String get registerSuccess => 'Register success';

	/// en: 'Login success'
	String get loginSuccess => 'Login success';

	/// en: 'Confirm password'
	String get confirmPassword => 'Confirm password';

	/// en: 'Email invalid'
	String get emailInvalid => 'Email invalid';

	/// en: 'Change password'
	String get changePassword => 'Change password';

	/// en: 'Change email'
	String get changeEmail => 'Change email';

	/// en: 'Logged out'
	String get loggedOut => 'Logged out';

	/// en: 'Success'
	String get success => 'Success';

	/// en: 'Password didn't match'
	String get passwordDidntMatch => 'Password didn\'t match';

	/// en: 'New password'
	String get newPassword => 'New password';

	/// en: 'Old password'
	String get oldPassword => 'Old password';

	/// en: 'Confirm new password'
	String get confirmNewPassword => 'Confirm new password';

	/// en: 'Old and new passwords are the same'
	String get oldAndNewPasswordsAreTheSame => 'Old and new passwords are the same';

	/// en: 'New email'
	String get newEmail => 'New email';

	/// en: 'Old and new emails are the same'
	String get oldAndNewEmailsAreTheSame => 'Old and new emails are the same';

	/// en: 'Confirm master password'
	String get confirmMasterPassword => 'Confirm master password';

	/// en: 'Master password didn't match'
	String get masterPasswordDidntMatch => 'Master password didn\'t match';

	/// en: 'Please remember your master password! Your data will be encrypted with the master password before upload; if you forget the master password, the data cannot be decrypted!'
	String get masterPasswordNote => 'Please remember your master password! Your data will be encrypted with the master password before upload; if you forget the master password, the data cannot be decrypted!';

	/// en: 'Author'
	String get author => 'Author';

	/// en: 'Project'
	String get project => 'Project';

	/// en: 'Open link failed'
	String get openLinkFailed => 'Open link failed';

	/// en: 'Link is invalid'
	String get linkIsInvalid => 'Link is invalid';

	/// en: 'Reset token'
	String get resetToken => 'Reset token';

	/// en: 'How to get reset token: Use your registered email send an appeal email to me to get a reset token, my email is: $authorEmail email content example: 'My HahaNote username is xxx, I forgot my password, need a reset token to reset the password, thx' then I'll check your email address and your username, if they are match, I will send a reset token to you.'
	String resetTokenNote({required Object authorEmail}) => 'How to get reset token: Use your registered email send an appeal email to me to get a reset token, my email is: ${authorEmail}\n\nemail content example:\n\n\'My HahaNote username is xxx, I forgot my password, need a reset token to reset the password, thx\'\n\nthen I\'ll check your email address and your username, if they are match, I will send a reset token to you.';

	/// en: 'Last synced at: $time'
	String lastSyncedAt({required Object time}) => 'Last synced at: ${time}';

	/// en: 'No repo opened'
	String get noRepoOpened => 'No repo opened';

	/// en: 'Checking login'
	String get checkingLogin => 'Checking login';

	/// en: 'Syncing'
	String get syncing => 'Syncing';

	/// en: 'Privacy policy'
	String get privacyPolicy => 'Privacy policy';

	/// en: 'Refresh'
	String get refresh => 'Refresh';

	/// en: 'Sync complete: with $conflictsCount conflicts'
	String syncCompleteWithConflicts({required Object conflictsCount}) => 'Sync complete: with ${conflictsCount} conflicts';

	/// en: 'Sync complete'
	String get syncComplete => 'Sync complete';

	/// en: 'Contents are identical'
	String get contentsAreIdentical => 'Contents are identical';

	/// en: 'Copied'
	String get copied => 'Copied';

	/// en: 'Show Menu'
	String get showMenu => 'Show Menu';

	/// en: 'Hide Menu'
	String get hideMenu => 'Hide Menu';

	/// en: 'The line number maybe incorrect'
	String get lineNumIncorrectNote => 'The line number maybe incorrect';

	/// en: 'Please install an editor to open file'
	String get pleaseInstallAnEditorToOpenFile => 'Please install an editor to open file';

	/// en: 'Settings'
	String get settings => 'Settings';

	/// en: 'Text Editor'
	String get textEditor => 'Text Editor';

	/// en: 'If the browser doesn't open, please manually copy and paste the link into your browser to open it'
	String get openLinkByYourself => 'If the browser doesn\'t open, please manually copy and paste the link into your browser to open it';

	/// en: 'Repot Bug'
	String get reportBug => 'Repot Bug';

	/// en: 'Target dirs or files already exists, do you want to merge dirs and overwrite files?'
	String get askMergeDirsAndFiles => 'Target dirs or files already exists, do you want to merge dirs and overwrite files?';

	/// en: 'Sync started'
	String get syncStarted => 'Sync started';

	/// en: 'TLS Certs'
	String get tlsCerts => 'TLS Certs';

	/// en: 'General'
	String get general => 'General';

	/// en: 'Overwrite'
	String get overwrite => 'Overwrite';

	/// en: 'File already exists, do you want to overwrite it?'
	String get fileAlreadyExistsOverwriteAsk => 'File already exists, do you want to overwrite it?';

	/// en: 'path doesn't exist'
	String get pathDoesntExist => 'path doesn\'t exist';

	/// en: 'path already exists'
	String get pathAlreadyExists => 'path already exists';

	/// en: 'Open as text'
	String get openAsText => 'Open as text';

	/// en: 'Clear'
	String get clear => 'Clear';

	/// en: 'State'
	String get state => 'State';

	/// en: 'Client'
	String get client => 'Client';

	/// en: 'Brief'
	String get brief => 'Brief';

	/// en: 'Client Name'
	String get clientName => 'Client Name';

	/// en: 'Language'
	String get language => 'Language';

	/// en: 'Changes will take effect on next start'
	String get changesWillTakeEffectOnNextStart => 'Changes will take effect on next start';

	/// en: 'Update'
	String get update => 'Update';

	/// en: 'Show in Files'
	String get showInFiles => 'Show in Files';

	/// en: 'Copy File Name'
	String get copyFileName => 'Copy File Name';

	/// en: 'Copy Oid'
	String get copyOid => 'Copy Oid';

	/// en: 'Re-Authorize'
	String get reAuthorize => 'Re-Authorize';

	/// en: 'Client name identifies this device in history'
	String get clientNameNote => 'Client name identifies this device in history';

	/// en: 'Client name too long'
	String get clientNameTooLong => 'Client name too long';

	/// en: 'Quit'
	String get quit => 'Quit';

	/// en: 'Pack file size'
	String get packFileSize => 'Pack file size';

	/// en: 'When uploading files, multiple small files are aggregated into a single large file to reduce the number of requests. A larger value will reduce the number of requests but increase the amount of data transferred per request; a smaller value will increase the number of requests but decrease the data transferred per request. If using Dropbox, it is recommended to set this to at least $recommendedMinSizeForDropbox to avoid hitting per-second request limits; If using a self-hosted service, it is recommended to disable the server's per-second request limit and lower this value.'
	String packFileSizeNote({required Object recommendedMinSizeForDropbox}) => 'When uploading files, multiple small files are aggregated into a single large file to reduce the number of requests.\n\nA larger value will reduce the number of requests but increase the amount of data transferred per request; a smaller value will increase the number of requests but decrease the data transferred per request.\n\nIf using Dropbox, it is recommended to set this to at least ${recommendedMinSizeForDropbox} to avoid hitting per-second request limits; If using a self-hosted service, it is recommended to disable the server\'s per-second request limit and lower this value.';

	/// en: 'at least $least, at most $most'
	String packFileSizeLimit({required Object least, required Object most}) => 'at least ${least}, at most ${most}';

	/// en: 'Restore All'
	String get restoreAll => 'Restore All';

	/// en: 'This will restore all files to the working directory and may take a long time. Leaving the current page while the task is in progress will cancel the restore'
	String get restoreAllAsk => 'This will restore all files to the working directory and may take a long time. Leaving the current page while the task is in progress will cancel the restore';

	/// en: 'This will restore selected files to the working directory and may take a long time. Leaving the current page while the task is in progress will cancel the restore'
	String get restoreSelectedAsk => 'This will restore selected files to the working directory and may take a long time. Leaving the current page while the task is in progress will cancel the restore';

	/// en: 'Restore canceled (some files may already be restored to the workdir)'
	String get restoreCanceledNote => 'Restore canceled (some files may already be restored to the workdir)';

	/// en: 'Selected'
	String get selected => 'Selected';

	/// en: 'Items'
	String get items => 'Items';

	/// en: 'Delete Remote'
	String get deleteRemote => 'Delete Remote';

	/// en: 'Delete Local'
	String get deleteLocal => 'Delete Local';

	/// en: 'Deleting'
	String get deleting => 'Deleting';

	/// en: 'Deleted'
	String get deleted => 'Deleted';

	/// en: 'Error'
	String get error => 'Error';

	/// en: 'delete repo canceled (some files maybe already deleted)'
	String get deleteRepoCanceledNote => 'delete repo canceled (some files maybe already deleted)';

	/// en: 'Export all files associated with the node to a specified directory'
	String get exportFilesFromNodeNote => 'Export all files associated with the node to a specified directory';

	/// en: 'User'
	String get user => 'User';

	/// en: 'Remote and Local paths are the same'
	String get remoteAndLocalPathsAreTheSame => 'Remote and Local paths are the same';

	/// en: 'Root path is not allowed'
	String get rootPathIsNotAllowed => 'Root path is not allowed';

	/// en: 'Files will be permanently deleted and cannot be exported or viewed afterward. Continue?'
	String get permanentlyDeleteFilesAsk => 'Files will be permanently deleted and cannot be exported or viewed afterward. Continue?';

	/// en: 'Note: Permanently deleted files cannot be exported'
	String get cannotExportPermanentlyDeletedFilesNote => 'Note: Permanently deleted files cannot be exported';

	/// en: 'Buy Vip'
	String get buyVip => 'Buy Vip';

	/// en: 'Buy'
	String get buy => 'Buy';

	/// en: 'Requires Vip'
	String get requiresVip => 'Requires Vip';

	/// en: 'Vip: $vipLv (until: $expiresAt)'
	String vipLvAndExpiresAt({required Object vipLv, required Object expiresAt}) => 'Vip: ${vipLv} (until: ${expiresAt})';

	/// en: 'Vip Required'
	String get vipRequired => 'Vip Required';

	/// en: 'Requires Vip Level: $vipLv'
	String requiresVipLv({required Object vipLv}) => 'Requires Vip Level: ${vipLv}';

	/// en: 'Vip: Expired ($date)'
	String vipExpiredAndDate({required Object date}) => 'Vip: Expired (${date})';

	/// en: 'Proxy'
	String get proxy => 'Proxy';

	/// en: 'HTTP Proxy'
	String get httpProxy => 'HTTP Proxy';

	/// en: 'Socks5 Proxy'
	String get socks5Proxy => 'Socks5 Proxy';

	/// en: 'Port'
	String get port => 'Port';

	/// en: 'Invalid'
	String get invalid => 'Invalid';

	/// en: 'Invalid Port'
	String get invalidPort => 'Invalid Port';

	/// en: 'Copy workdir path'
	String get copyWorkdirPath => 'Copy workdir path';

	/// en: 'Copy object path'
	String get copyObjectPath => 'Copy object path';

	/// en: 'Git Backend'
	String get gitBackend => 'Git Backend';

	/// en: 'Git Pull Url'
	String get gitPullUrl => 'Git Pull Url';

	/// en: 'Git Push Url'
	String get gitPushUrl => 'Git Push Url';

	/// en: 'Git Sync Url'
	String get gitSyncUrl => 'Git Sync Url';

	/// en: 'Log Level'
	String get logLevel => 'Log Level';

	/// en: 'Log'
	String get log => 'Log';

	/// en: 'Dev Mode'
	String get devMode => 'Dev Mode';

	/// en: 'ON'
	String get On => 'ON';

	/// en: 'OFF'
	String get OFF => 'OFF';

	/// en: 'Enabled'
	String get enabled => 'Enabled';

	/// en: 'Disabled'
	String get disabled => 'Disabled';

	/// en: 'Copy App Config Dir Path'
	String get copyAppConfigDirPath => 'Copy App Config Dir Path';

	/// en: 'Copy Log File Path'
	String get copyLogFilePath => 'Copy Log File Path';

	/// en: 'Copy Log Dir Path'
	String get copyLogDirPath => 'Copy Log Dir Path';

	/// en: 'Repo Invalid'
	String get repoInvalid => 'Repo Invalid';

	/// en: 'Redeem'
	String get redeem => 'Redeem';

	/// en: 'Redeem Code'
	String get redeemCode => 'Redeem Code';

	/// en: 'Vip: $vipLv (expired: $date)'
	String expiredVipLvAndDate({required Object vipLv, required Object date}) => 'Vip: ${vipLv} (expired: ${date})';

	/// en: 'Vip has expired'
	String get vipExpired => 'Vip has expired';

	/// en: 'Redeem Code invalid'
	String get redeemCodeInvalid => 'Redeem Code invalid';

	/// en: 'Status'
	String get status => 'Status';

	/// en: 'Modified'
	String get modified => 'Modified';

	/// en: 'Added'
	String get added => 'Added';

	/// en: 'File doesn't exist'
	String get fileDoesntExist => 'File doesn\'t exist';

	/// en: 'Unknown Type'
	String get unknownType => 'Unknown Type';

	/// en: 'Copy Relative Path'
	String get copyRelativePath => 'Copy Relative Path';

	/// en: 'Hide Content'
	String get hideContent => 'Hide Content';

	/// en: 'Show Content'
	String get showContent => 'Show Content';

	/// en: 'Blank lines may be ignored'
	String get blankLinesMayBeIgnored => 'Blank lines may be ignored';

	/// en: 'Hide Line Num'
	String get hideLineNum => 'Hide Line Num';

	/// en: 'Show Line Num'
	String get showLineNum => 'Show Line Num';

	/// en: 'Copy Absolute Path'
	String get copyAbsolutePath => 'Copy Absolute Path';

	/// en: 'Will delete the file(s) on the disk'
	String get willDelFileOnDisk => 'Will delete the file(s) on the disk';

	/// en: 'Another task running, please try again later'
	String get anotherTaskRunningPleaseTryAgainLater => 'Another task running, please try again later';

	/// en: 'Ignore'
	String get ignore => 'Ignore';

	/// en: 'Permissions'
	String get permissions => 'Permissions';

	/// en: 'Manage Storage'
	String get manageStorage => 'Manage Storage';

	/// en: 'Disable Battery Optimization'
	String get disableBatteryOptimization => 'Disable Battery Optimization';

	/// en: 'Rejected'
	String get rejected => 'Rejected';

	/// en: 'Allowed'
	String get allowed => 'Allowed';

	/// en: 'Not Disabled'
	String get notDisabled => 'Not Disabled';

	/// en: 'This permission is required to store user files'
	String get manageStorageDesc => 'This permission is required to store user files';

	/// en: 'This permission is needed to prevent sync aborted or Dropbox auth failed when app in background'
	String get disableBatteryOptimizationDesc => 'This permission is needed to prevent sync aborted or Dropbox auth failed when app in background';

	/// en: 'App Info'
	String get appInfo => 'App Info';

	/// en: 'Click 'OK' to open app info, please find battery usage settings and allow app running in background'
	String get openAppInfoToDisableBatteryUsageDesc => 'Click \'OK\' to open app info, please find battery usage settings and allow app running in background';

	/// en: 'Nothing'
	String get nothing => 'Nothing';

	/// en: 'Resolve Strategy'
	String get resolveStrategy => 'Resolve Strategy';

	/// en: 'Selection Mode'
	String get selectionMode => 'Selection Mode';

	/// en: 'Git Backend (Requires PuppyGit)'
	String get gitBackendRequiresPuppyGit => 'Git Backend (Requires PuppyGit)';

	/// en: 'PuppyGit Pull Url'
	String get puppyGitPullUrl => 'PuppyGit Pull Url';

	/// en: 'PuppyGit Push Url'
	String get puppyGitPushUrl => 'PuppyGit Push Url';

	/// en: 'PuppyGit Sync Url'
	String get puppyGitSyncUrl => 'PuppyGit Sync Url';

	/// en: 'Options'
	String get options => 'Options';

	/// en: 'Remote Overwrite Workdir If Need Merge'
	String get remoteOverwriteWorkdirIfNeedMerge => 'Remote Overwrite Workdir If Need Merge';

	/// en: 'If merging is required when syncing, will use remote files overwrite workdir files. Your files may be deleted and cannot be recovered. Enable only if you are sure'
	String get remoteOverwriteWorkdirIfNeedMergeDesc => 'If merging is required when syncing, will use remote files overwrite workdir files. Your files may be deleted and cannot be recovered. Enable only if you are sure';

	/// en: 'Sync Mode'
	String get syncMode => 'Sync Mode';

	/// en: 'Merge Mode'
	String get mergeMode => 'Merge Mode';

	/// en: 'Merge Remote and Workdir'
	String get mergeRemoteAndWorkdir => 'Merge Remote and Workdir';

	/// en: 'Remote Overwrite Workdir'
	String get remoteOverwriteWorkdir => 'Remote Overwrite Workdir';

	/// en: 'Note'
	String get note => 'Note';

	/// en: 'Show Repo Data Dir In Files'
	String get showRepoDataDirInFiles => 'Show Repo Data Dir In Files';

	/// en: 'Repo Data Dir'
	String get repoDataDir => 'Repo Data Dir';

	/// en: 'Keep Empty Dir'
	String get keepEmptyDir => 'Keep Empty Dir';

	/// en: 'Empty files will be created in empty directories, so they will be included in the next sync'
	String get keepEmptyDirDesc => 'Empty files will be created in empty directories, so they will be included in the next sync';

	/// en: 'Deleted and Modified files will be restored, Added files will be deleted'
	String get statusRestoreDesc => 'Deleted and Modified files will be restored, Added files will be deleted';

	/// en: ''$name' will be deleted'
	String fileWillBeDeleted({required Object name}) => '\'${name}\' will be deleted';

	/// en: '$n item(s) will be deleted'
	String nItemsWillBeDeleted({required Object n}) => '${n} item(s) will be deleted';

	/// en: 'Clean'
	String get clean => 'Clean';

	/// en: 'Temp files will be deleted'
	String get cleanTempFilesDesc => 'Temp files will be deleted';

	/// en: 'Temp Files'
	String get tempFiles => 'Temp Files';

	/// en: 'Index'
	String get index => 'Index';

	/// en: 'After clearing the index, the next sync will re-scan workdir files'
	String get cleanIndexDesc => 'After clearing the index, the next sync will re-scan workdir files';

	/// en: 'Nothing need to push'
	String get nothingNeedToPush => 'Nothing need to push';

	/// en: 'Some files need to push'
	String get someFilesNeedToPush => 'Some files need to push';

	/// en: 'Checking'
	String get checking => 'Checking';

	/// en: 'No changes'
	String get noChanges => 'No changes';

	/// en: 'Have changes need to sync'
	String get haveChangesNeedToSync => 'Have changes need to sync';

	/// en: 'Set to 0 to use global settings'
	String get setToZeroToUseGlobalSettings => 'Set to 0 to use global settings';

	/// en: 'Cached Data'
	String get cachedData => 'Cached Data';

	/// en: 'Remove local cached objects, they will be re-downloaded when needed'
	String get cleanCachedDataDesc => 'Remove local cached objects, they will be re-downloaded when needed';

	/// en: 'Download Cache'
	String get downloadCache => 'Download Cache';

	/// en: 'Objects Cache'
	String get objectsCache => 'Objects Cache';

	/// en: 'Preview'
	String get preview => 'Preview';

	/// en: 'Theme'
	String get theme => 'Theme';

	/// en: 'Donate'
	String get donate => 'Donate';

	/// en: 'Color Scheme'
	String get colorScheme => 'Color Scheme';

	/// en: 'Changelog'
	String get changelog => 'Changelog';

	/// en: 'Every single bit of support is vital to us, click here to donate'
	String get donateWelcomeText => 'Every single bit of support is vital to us, click here to donate';

	/// en: 'Reveal in File Explorer'
	String get revealInFileExplorer => 'Reveal in File Explorer';

	/// en: 'Line Number'
	String get lineNumber => 'Line Number';

	/// en: 'Built-in'
	String get builtIn => 'Built-in';

	/// en: 'Soft-Wrap'
	String get softWrap => 'Soft-Wrap';

	/// en: 'Display Mode'
	String get displayMode => 'Display Mode';

	/// en: 'Landscape'
	String get landscape => 'Landscape';

	/// en: 'Portrait'
	String get portrait => 'Portrait';
}

/// The flat map containing all translations for locale <en>.
/// Only for edge cases! For simple maps, use the map function of this library.
///
/// The Dart AOT compiler has issues with very large switch statements,
/// so the map is split into smaller functions (512 entries each).
extension on Translations {
	dynamic _flatMapFunction(String path) {
		return switch (path) {
			'appName' => 'HahaNote',
			'appDesc' => 'HahaNote is an e2ee note-taking and syncing app',
			'create' => 'Create',
			'import' => 'Import',
			'open' => 'Open',
			'edit' => 'Edit',
			'unknown' => 'Unknown',
			'username' => 'Username',
			'password' => 'Password',
			'host' => 'Host',
			'authorize' => 'Authorize',
			'remotePath' => 'Remote Path',
			'localPath' => 'Local Path',
			'choose' => 'Choose',
			'submit' => 'Submit',
			'cancel' => 'Cancel',
			'masterPassword' => 'Master Password',
			'invalidEmail' => 'Invalid Email',
			'pleaseInput' => 'Please Input',
			'pleaseAuthorizeDropbox' => 'Please complete the Dropbox authorization',
			'repoAlreadyAdded' => 'Repo already added',
			'localRepoPathAlreadyExists' => 'Local repo path already exists',
			'localRepoPathIsNotEmpty' => 'Local repo path is not empty',
			'unknownRemoteType' => 'Unknown remote type',
			'remotePathAlreadyExists' => 'Remote path already exists',
			'remotePathDoesntExist' => 'Remote path doesn\'t exist',
			'unknownMode' => 'Unknown mode',
			'home' => 'Home',
			'repo' => 'Repo',
			'files' => 'Files',
			'editor' => 'Editor',
			'logout' => 'Logout',
			'invalidPath' => 'Invalid path',
			'pathIsNotAbsolute' => 'Path is not absolute',
			'remoteType' => 'Remote type',
			'sync' => 'Sync',
			'reload' => 'Reload',
			'close' => 'Close',
			'conflict' => 'Conflict',
			'about' => 'About',
			'thereAreConflicts' => ({required Object count}) => 'There are ${count} conflicts',
			'check' => 'Check',
			'info' => 'Info',
			'name' => 'Name',
			'path' => 'Path',
			'size' => 'Size',
			'modifiedTime' => 'Modified time',
			'recycleBin' => 'Recycle Bin',
			'rename' => 'Rename',
			'ok' => 'OK',
			'delete' => 'Delete',
			'areYouSure' => 'Are you sure?',
			'openInExt' => 'Open in External',
			'copyPath' => 'Copy path',
			'tNew' => 'New',
			'folder' => 'Folder',
			'file' => 'File',
			'search' => 'Search',
			'empty' => 'Empty',
			'nothingFound' => 'Nothing found',
			'loading' => 'Loading...',
			'dir' => 'Dir',
			'history' => 'History',
			'countSelected' => ({required Object count}) => '${count} selected',
			'copy' => 'Copy',
			'move' => 'Move',
			'paste' => 'Paste',
			'back' => 'Back',
			'type' => 'Type',
			'lastModifiedTime' => 'Last modified time',
			'sort' => 'Sort',
			'ascending' => 'Ascending',
			'folderFirst' => 'Folder first',
			'applyToThisFolderOnly' => 'Apply to this folder only',
			'find' => 'Find',
			'previous' => 'Previous',
			'next' => 'Next',
			'none' => 'None',
			'replace' => 'Replace',
			'replaceAll' => 'Replace All',
			'cut' => 'Cut',
			'selectAll' => 'Select All',
			'recent' => 'Recent',
			'undo' => 'Undo',
			'redo' => 'Redo',
			'save' => 'Save',
			'saved' => 'Saved',
			'unsavedDateWillLost' => 'Unsaved data will lost',
			'goTo' => 'Go to',
			'fontSize' => 'Font Size',
			'auto' => 'Auto',
			'light' => 'Light',
			'dark' => 'Dark',
			'requireRestartToApplyNewTheme' => 'Require restart to apply new theme',
			'pleaseLogin' => 'Please login',
			'loginOrRegister' => 'Login or Register',
			'login' => 'Login',
			'register' => 'Register',
			'oid' => 'Oid',
			'createTime' => 'Create Time',
			'tag' => 'Tag',
			'restore' => 'Restore',
			'export' => 'Export',
			'view' => 'View',
			'deleteAll' => 'Delete All',
			'local' => 'Local',
			'workdir' => 'Workdir',
			'remote' => 'Remote',
			'done' => 'Done',
			'diff' => 'Diff',
			'canceling' => 'Canceling',
			'forgotPassword' => 'Forgot password',
			'email' => 'Email',
			'usernameInvalid' => ({required Object pattern, required Object minLength}) => 'Username invalid, allowed: ${pattern}, at least: ${minLength}',
			'passwordInvalid' => ({required Object pattern, required Object minLength}) => 'Password invalid, allowed: ${pattern}, at least: ${minLength}',
			'registerSuccess' => 'Register success',
			'loginSuccess' => 'Login success',
			'confirmPassword' => 'Confirm password',
			'emailInvalid' => 'Email invalid',
			'changePassword' => 'Change password',
			'changeEmail' => 'Change email',
			'loggedOut' => 'Logged out',
			'success' => 'Success',
			'passwordDidntMatch' => 'Password didn\'t match',
			'newPassword' => 'New password',
			'oldPassword' => 'Old password',
			'confirmNewPassword' => 'Confirm new password',
			'oldAndNewPasswordsAreTheSame' => 'Old and new passwords are the same',
			'newEmail' => 'New email',
			'oldAndNewEmailsAreTheSame' => 'Old and new emails are the same',
			'confirmMasterPassword' => 'Confirm master password',
			'masterPasswordDidntMatch' => 'Master password didn\'t match',
			'masterPasswordNote' => 'Please remember your master password! Your data will be encrypted with the master password before upload; if you forget the master password, the data cannot be decrypted!',
			'author' => 'Author',
			'project' => 'Project',
			'openLinkFailed' => 'Open link failed',
			'linkIsInvalid' => 'Link is invalid',
			'resetToken' => 'Reset token',
			'resetTokenNote' => ({required Object authorEmail}) => 'How to get reset token: Use your registered email send an appeal email to me to get a reset token, my email is: ${authorEmail}\n\nemail content example:\n\n\'My HahaNote username is xxx, I forgot my password, need a reset token to reset the password, thx\'\n\nthen I\'ll check your email address and your username, if they are match, I will send a reset token to you.',
			'lastSyncedAt' => ({required Object time}) => 'Last synced at: ${time}',
			'noRepoOpened' => 'No repo opened',
			'checkingLogin' => 'Checking login',
			'syncing' => 'Syncing',
			'privacyPolicy' => 'Privacy policy',
			'refresh' => 'Refresh',
			'syncCompleteWithConflicts' => ({required Object conflictsCount}) => 'Sync complete: with ${conflictsCount} conflicts',
			'syncComplete' => 'Sync complete',
			'contentsAreIdentical' => 'Contents are identical',
			'copied' => 'Copied',
			'showMenu' => 'Show Menu',
			'hideMenu' => 'Hide Menu',
			'lineNumIncorrectNote' => 'The line number maybe incorrect',
			'pleaseInstallAnEditorToOpenFile' => 'Please install an editor to open file',
			'settings' => 'Settings',
			'textEditor' => 'Text Editor',
			'openLinkByYourself' => 'If the browser doesn\'t open, please manually copy and paste the link into your browser to open it',
			'reportBug' => 'Repot Bug',
			'askMergeDirsAndFiles' => 'Target dirs or files already exists, do you want to merge dirs and overwrite files?',
			'syncStarted' => 'Sync started',
			'tlsCerts' => 'TLS Certs',
			'general' => 'General',
			'overwrite' => 'Overwrite',
			'fileAlreadyExistsOverwriteAsk' => 'File already exists, do you want to overwrite it?',
			'pathDoesntExist' => 'path doesn\'t exist',
			'pathAlreadyExists' => 'path already exists',
			'openAsText' => 'Open as text',
			'clear' => 'Clear',
			'state' => 'State',
			'client' => 'Client',
			'brief' => 'Brief',
			'clientName' => 'Client Name',
			'language' => 'Language',
			'changesWillTakeEffectOnNextStart' => 'Changes will take effect on next start',
			'update' => 'Update',
			'showInFiles' => 'Show in Files',
			'copyFileName' => 'Copy File Name',
			'copyOid' => 'Copy Oid',
			'reAuthorize' => 'Re-Authorize',
			'clientNameNote' => 'Client name identifies this device in history',
			'clientNameTooLong' => 'Client name too long',
			'quit' => 'Quit',
			'packFileSize' => 'Pack file size',
			'packFileSizeNote' => ({required Object recommendedMinSizeForDropbox}) => 'When uploading files, multiple small files are aggregated into a single large file to reduce the number of requests.\n\nA larger value will reduce the number of requests but increase the amount of data transferred per request; a smaller value will increase the number of requests but decrease the data transferred per request.\n\nIf using Dropbox, it is recommended to set this to at least ${recommendedMinSizeForDropbox} to avoid hitting per-second request limits; If using a self-hosted service, it is recommended to disable the server\'s per-second request limit and lower this value.',
			'packFileSizeLimit' => ({required Object least, required Object most}) => 'at least ${least}, at most ${most}',
			'restoreAll' => 'Restore All',
			'restoreAllAsk' => 'This will restore all files to the working directory and may take a long time. Leaving the current page while the task is in progress will cancel the restore',
			'restoreSelectedAsk' => 'This will restore selected files to the working directory and may take a long time. Leaving the current page while the task is in progress will cancel the restore',
			'restoreCanceledNote' => 'Restore canceled (some files may already be restored to the workdir)',
			'selected' => 'Selected',
			'items' => 'Items',
			'deleteRemote' => 'Delete Remote',
			'deleteLocal' => 'Delete Local',
			'deleting' => 'Deleting',
			'deleted' => 'Deleted',
			'error' => 'Error',
			'deleteRepoCanceledNote' => 'delete repo canceled (some files maybe already deleted)',
			'exportFilesFromNodeNote' => 'Export all files associated with the node to a specified directory',
			'user' => 'User',
			'remoteAndLocalPathsAreTheSame' => 'Remote and Local paths are the same',
			'rootPathIsNotAllowed' => 'Root path is not allowed',
			'permanentlyDeleteFilesAsk' => 'Files will be permanently deleted and cannot be exported or viewed afterward. Continue?',
			'cannotExportPermanentlyDeletedFilesNote' => 'Note: Permanently deleted files cannot be exported',
			'buyVip' => 'Buy Vip',
			'buy' => 'Buy',
			'requiresVip' => 'Requires Vip',
			'vipLvAndExpiresAt' => ({required Object vipLv, required Object expiresAt}) => 'Vip: ${vipLv} (until: ${expiresAt})',
			'vipRequired' => 'Vip Required',
			'requiresVipLv' => ({required Object vipLv}) => 'Requires Vip Level: ${vipLv}',
			'vipExpiredAndDate' => ({required Object date}) => 'Vip: Expired (${date})',
			'proxy' => 'Proxy',
			'httpProxy' => 'HTTP Proxy',
			'socks5Proxy' => 'Socks5 Proxy',
			'port' => 'Port',
			'invalid' => 'Invalid',
			'invalidPort' => 'Invalid Port',
			'copyWorkdirPath' => 'Copy workdir path',
			'copyObjectPath' => 'Copy object path',
			'gitBackend' => 'Git Backend',
			'gitPullUrl' => 'Git Pull Url',
			'gitPushUrl' => 'Git Push Url',
			'gitSyncUrl' => 'Git Sync Url',
			'logLevel' => 'Log Level',
			'log' => 'Log',
			'devMode' => 'Dev Mode',
			'On' => 'ON',
			'OFF' => 'OFF',
			'enabled' => 'Enabled',
			'disabled' => 'Disabled',
			'copyAppConfigDirPath' => 'Copy App Config Dir Path',
			'copyLogFilePath' => 'Copy Log File Path',
			'copyLogDirPath' => 'Copy Log Dir Path',
			'repoInvalid' => 'Repo Invalid',
			'redeem' => 'Redeem',
			'redeemCode' => 'Redeem Code',
			'expiredVipLvAndDate' => ({required Object vipLv, required Object date}) => 'Vip: ${vipLv} (expired: ${date})',
			'vipExpired' => 'Vip has expired',
			'redeemCodeInvalid' => 'Redeem Code invalid',
			'status' => 'Status',
			'modified' => 'Modified',
			'added' => 'Added',
			'fileDoesntExist' => 'File doesn\'t exist',
			'unknownType' => 'Unknown Type',
			'copyRelativePath' => 'Copy Relative Path',
			'hideContent' => 'Hide Content',
			'showContent' => 'Show Content',
			'blankLinesMayBeIgnored' => 'Blank lines may be ignored',
			'hideLineNum' => 'Hide Line Num',
			'showLineNum' => 'Show Line Num',
			'copyAbsolutePath' => 'Copy Absolute Path',
			'willDelFileOnDisk' => 'Will delete the file(s) on the disk',
			'anotherTaskRunningPleaseTryAgainLater' => 'Another task running, please try again later',
			'ignore' => 'Ignore',
			'permissions' => 'Permissions',
			'manageStorage' => 'Manage Storage',
			'disableBatteryOptimization' => 'Disable Battery Optimization',
			'rejected' => 'Rejected',
			'allowed' => 'Allowed',
			'notDisabled' => 'Not Disabled',
			'manageStorageDesc' => 'This permission is required to store user files',
			'disableBatteryOptimizationDesc' => 'This permission is needed to prevent sync aborted or Dropbox auth failed when app in background',
			'appInfo' => 'App Info',
			'openAppInfoToDisableBatteryUsageDesc' => 'Click \'OK\' to open app info, please find battery usage settings and allow app running in background',
			'nothing' => 'Nothing',
			'resolveStrategy' => 'Resolve Strategy',
			'selectionMode' => 'Selection Mode',
			'gitBackendRequiresPuppyGit' => 'Git Backend (Requires PuppyGit)',
			'puppyGitPullUrl' => 'PuppyGit Pull Url',
			'puppyGitPushUrl' => 'PuppyGit Push Url',
			'puppyGitSyncUrl' => 'PuppyGit Sync Url',
			'options' => 'Options',
			'remoteOverwriteWorkdirIfNeedMerge' => 'Remote Overwrite Workdir If Need Merge',
			'remoteOverwriteWorkdirIfNeedMergeDesc' => 'If merging is required when syncing, will use remote files overwrite workdir files. Your files may be deleted and cannot be recovered. Enable only if you are sure',
			'syncMode' => 'Sync Mode',
			'mergeMode' => 'Merge Mode',
			'mergeRemoteAndWorkdir' => 'Merge Remote and Workdir',
			'remoteOverwriteWorkdir' => 'Remote Overwrite Workdir',
			'note' => 'Note',
			'showRepoDataDirInFiles' => 'Show Repo Data Dir In Files',
			'repoDataDir' => 'Repo Data Dir',
			'keepEmptyDir' => 'Keep Empty Dir',
			'keepEmptyDirDesc' => 'Empty files will be created in empty directories, so they will be included in the next sync',
			'statusRestoreDesc' => 'Deleted and Modified files will be restored, Added files will be deleted',
			'fileWillBeDeleted' => ({required Object name}) => '\'${name}\' will be deleted',
			'nItemsWillBeDeleted' => ({required Object n}) => '${n} item(s) will be deleted',
			'clean' => 'Clean',
			'cleanTempFilesDesc' => 'Temp files will be deleted',
			'tempFiles' => 'Temp Files',
			'index' => 'Index',
			'cleanIndexDesc' => 'After clearing the index, the next sync will re-scan workdir files',
			'nothingNeedToPush' => 'Nothing need to push',
			'someFilesNeedToPush' => 'Some files need to push',
			'checking' => 'Checking',
			'noChanges' => 'No changes',
			'haveChangesNeedToSync' => 'Have changes need to sync',
			'setToZeroToUseGlobalSettings' => 'Set to 0 to use global settings',
			'cachedData' => 'Cached Data',
			'cleanCachedDataDesc' => 'Remove local cached objects, they will be re-downloaded when needed',
			'downloadCache' => 'Download Cache',
			'objectsCache' => 'Objects Cache',
			'preview' => 'Preview',
			'theme' => 'Theme',
			'donate' => 'Donate',
			'colorScheme' => 'Color Scheme',
			'changelog' => 'Changelog',
			'donateWelcomeText' => 'Every single bit of support is vital to us, click here to donate',
			'revealInFileExplorer' => 'Reveal in File Explorer',
			'lineNumber' => 'Line Number',
			'builtIn' => 'Built-in',
			'softWrap' => 'Soft-Wrap',
			'displayMode' => 'Display Mode',
			'landscape' => 'Landscape',
			'portrait' => 'Portrait',
			_ => null,
		};
	}
}
