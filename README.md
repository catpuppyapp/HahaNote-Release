## HahaNote
#### Haha Note is a file-based + E2EE note sync app, can sync your notes to Dropbox/WebDav Server/Github(and other git platforms), support Windows/Linux/Android

### One-line summary
You can use any editor to edit your md/txt or any other files, then use HahaNote to sync them.

HahaNote is an E2EE note sync app, that means all your files decrypted on local and encrypted before leave your device, it can avoid platforms read your files. (example, even github or dropbox have data leak, your haha note data still safe, due to is encrypted)

### Sync your Obsidian notes By HahaNote
- Obsidian is an note taking app with optional sync plugin, HahaNote is an note sync app with basic text edit support, but both are file-based, so you can use HahaNote to sync your Obsidian valut as a choice.


### Key features
- support Windows/Linux/Android
- End-to-end encryption: notes are encrypted on-device before upload; remote servers store only ciphertext.
- Offline-first: full read/write access offline; changes sync when network returns with robust conflict resolution.
- File-based: you can use your feature editor to edit your file, then use HahaNote to securely sync them to your Dropbox/WebdavServer or Github
- Versioning: every file maintains an immutable version history so users can view, compare, and restore previous versions.
- Cross-platform clients: Windows, Linux, Android
- Privacy-first: HahaNote use Argon2id to devried secure key and use XChaCha20-Poly1305 to encrypted files, so only you can view your data.


### Cryptography details
- KDF: Argon2id
- Authenticated encryption: XChaCha20-Poly1305


### User flow
1. Account creation: register
2. Create an note repo, then you got '.haha_note' folder in your dir, this is haha_note data dir of your repo(just like .git folder for git), don't edit it by your self.
3. Create some files, then sync

