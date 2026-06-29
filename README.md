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
- All your data on your own: HahaNote is file-based, so you can access your files anytime, no need to export them from "app-specified-data-format", anytime, your data under your control.
- End-to-end encryption: notes are encrypted on-device before upload; remote servers store only ciphertext. that means, even cloud drive platorm have data leak, your data still safe.
- Offline-first: full read/write access offline; changes sync when network returns with robust conflict resolution.
- File-based: you can use your feature editor to edit your file, then use HahaNote to securely sync them to your Dropbox/WebdavServer or Github
- Versioning: every file maintains an immutable version history so users can view, compare, and restore previous versions.
- Privacy-first: HahaNote use Argon2id to devried secure key and use XChaCha20-Poly1305 to encrypted files, so only you can view your data.
- Cross-platform: Windows, Linux, Android


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
坚果云：并不是HahaNote不支持，而是这个网盘虽然支持WebDav，但是对第三方app有请求数限制，尽管平台声明30分钟600次，但实际测试可能更严苛，10分钟内100次就可能导致被临时封禁，所以如果你使用坚果云的webdav，那么这个app对你来说基本没法用，建议换其他方式同步笔记，比如使用其他支持webdav的网盘，或者自建webdav服务器，或者用国内的git平台。



## To early users (before 1.0.3 released)
#### I decide to open source of it and remove account system, old versions(before 1.0.3) will unavailable in the future, must update to latest version, but don't worry, your note still available.
#### after open source, then I will focus improve desktop ui and improve performence. You can [donate](https://github.com/catpuppyapp/PuppyGit/blob/main/donate.md) to support me. If I got more donations, then I can improve the performance of the app, and add more features, make the UI looks better...
