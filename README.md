## HahaNote
#### Haha Note is a file-based + E2EE note sync app, can sync your notes to Dropbox/WebDav Server/Github(and other git platforms), support Windows/Linux/Android


### Download
https://github.com/catpuppyapp/HahaNote-Release/releases


### How To Use
<a href=how_to_user.md>See</a>


### Screenshots
<img src=img/pc_file_history.jpg width=300>
<img src=img/pc_sync_page.jpg width=300>
<img src=img/pc_text_editor.jpg width=300>


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
