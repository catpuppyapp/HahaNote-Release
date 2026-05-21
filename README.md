## HahaNote
#### Haha Note is a file-based + E2EE note sync app, can sync your notes to Dropbox/WebDav Server/Github(and other git platforms), support Windows/Linux/Android


### Download
[GitHub Releases](https://github.com/catpuppyapp/HahaNote-Release/releases)


### Tutorial
<a href=how_to_use.md>How To Use</a>
<a href=git_backend.md>Git Backend Tutorial</a>


### Screenshots
<span> 
<img src=img/pc_file_history.jpg width=150>
<img src=img/pc_sync_page.jpg width=150>
<img src=img/pc_text_editor.jpg width=150>
</span>


### Brief
HahaNote is an e2ee note sync app, it can treat a local directory on your device as a repository and encrypt and sync all files inside it to Dropbox/WebDav servers or GitHub.

So You can use any editor to edit your md/txt or any other files, then use HahaNote to sync them.


### Key features
- End-to-end encryption: notes are encrypted on-device before upload; remote servers store only ciphertext.
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


### Recommended
#### WebDav Server
[dufs(self-hosted)](https://github.com/sigoden/dufs)

#### Cloud Drive
[InfiniCloud(WebDav supported, hosted in JP)](https://infini-cloud.net)

#### Editor on PC
[VSCodium](https://github.com/VSCodium/vscodium/releases)
[VSCode](https://code.visualstudio.com/Download)
[Obsidian](https://obsidian.md/download)

#### Editor on Android
[Markor(markdown editor)](https://github.com/gsantner/markor)
[PuppyGit(Git with an editor)](https://github.com/catpuppyapp/PuppyGit)


### Not Supported （不支持）
坚果云：并不是HahaNote不支持，而是这个网盘虽然支持WebDav，但是对第三方app有请求数限制，尽管平台声明30分钟600次，但实际测试可能更严苛，10分钟内100次就可能导致被临时封禁，所以如果你使用坚果云的webdav，那么这个app对你来说基本没法用，建议换其他方式同步笔记，比如使用国内的git平台（配置有些麻烦，不过只麻烦一次，后续就省心了），或者自托管webdav服务器，或者如果你可以连接上的话，可以使用Dropbox（可能延迟会比较高，很慢）。
