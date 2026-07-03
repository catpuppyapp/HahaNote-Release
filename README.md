## HahaNote
#### HahaNote is a file-based + E2EE note taking and syncing app, can sync your notes to Dropbox/WebDav Server/Github(and other git platforms), support Windows/Linux/Android


### Download
[GitHub Releases](https://github.com/catpuppyapp/HahaNote-Release/releases)

...izzyOnDroid comming soon


### Tutorial
[How To Use](how_to_use.md)

[Git Backend Tutorial](git_backend.md)


### Screenshots
<img src=fastlane/metadata/android/en-US/images/featureGraphic.png>


### Brief
HahaNote is an e2ee note sync app, it can treat a local directory on your device as a repository and encrypt and sync all files inside it to Dropbox/WebDav servers or GitHub.

So You can use any editor to edit your md/txt or any other files, then use HahaNote to sync them.


### Key features
- All your data on your own: HahaNote is file-based, so you can access your files anytime, no need to export them from "app-specified-data-format", your data under your control ever
- End-to-end encryption: Notes are encrypted on-device before upload, remote servers store only ciphertext. that means, even cloud drive platform have data leak, your data still safe
- Offline-first: Full read/write access offline
- File-based: You can use your favorite editor to edit your file, then use HahaNote to securely sync them to your Dropbox/Webdav Server or Git platform
- Versioning: Every file maintains an immutable version history, you can view, compare, and restore anytime
- Privacy-first: No tracking, respect your privacy
- Markdown preview supported
- Cross-platform: Windows/Linux/Android


### Cryptography details
- KDF: Argon2id
- Authenticated encryption: XChaCha20-Poly1305


### Why E2EE
HahaNote is an E2EE note sync app, that means all your files decrypted on local and encrypted before leave your device, it can avoid platforms read your files. (example, even github or dropbox have data leak, your haha note data still safe, due to is encrypted)

E2EE promise data encrypted before leaving your device, but on your local device, all data is decrypted, so you can edit them by any regular text editor, like VSCode, Zed, Notepad++, Obsidian.

### Help translate
1. Download `haha_note_src/lib/i18n/en.i18n.json`
2. Translate the value to your language, note: words starts with '$' are placeholders, please do not translate them, e.g. $username, it will replace to username when running
3. create a pr, and choose the "New Language Submission", and attaching your translated file
4. then I will add the new language in to the app


### MacOS
It will support mac when I got a Mac


### Recommended
#### WebDav Server
[dufs(self-hosted)](https://github.com/sigoden/dufs)

#### Cloud Drive
[InfiniCloud(WebDav supported, hosted in JP)](https://infini-cloud.net)

#### Editors on PC
[Zed](https://zed.dev)
[VSCodium](https://github.com/VSCodium/vscodium/releases)
[VSCode](https://code.visualstudio.com/Download)
[Notepad++](https://notepad-plus-plus.org)

#### Editors on Android
[Markor(markdown editor)](https://github.com/gsantner/markor)
[PuppyGit(Git with an editor)](https://github.com/catpuppyapp/PuppyGit)


### For Chinese users, Not Supported some Drives（不支持的一些网盘）
坚果云：并不是HahaNote不支持，而是这个网盘虽然支持WebDav，但是对第三方app有请求数限制，尽管平台声明30分钟600次，但实际比他们声明的更严苛，比如10分钟内100次就可能导致被临时封禁，所以如果你使用坚果云的webdav，那么这个app对你来说基本没法用，建议使用dropbox或其他webdav服务。



## To early users (before 1.0.3 released)
#### I decide to open source of it and remove account system, old versions(before 1.0.3) will unavailable in the future, must update to latest version, but don't worry, your note still available.
#### after open source, then I will focus improve the ui and performence. You can [donate](https://github.com/catpuppyapp/PuppyGit/blob/main/donate.md) to support me.


## Thx the packages developers!
https://pub.dev/packages/cryptography
https://pub.dev/packages/code_forge
https://pub.dev/packages/markdown
https://pub.dev/packages/json_serializable
https://pub.dev/packages/hive_ce
... and other all dependencies developers!

