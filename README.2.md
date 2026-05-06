## HahaNote

### One-line summary
HahaNote is a file-based cross-platform notes app that synchronizes user data across devices with end-to-end encryption (E2EE), ensuring only the user can read their notes.

### Key features
- support Windows/Linux/Android
- End-to-end encryption: notes are encrypted on-device before upload; remote servers store only ciphertext.
- Offline-first: full read/write access offline; changes sync when network returns with robust conflict resolution.
- File-based: you can use your feature editor to edit your file, then use HahaNote to securely sync them to your Dropbox/WebdavServer or Github
- Versioning: every note and attachment maintains an immutable version history so users can view, compare, and restore previous versions.
- Encrypted: HahaNote use Argon2id to devried secure key and use XChaCha20-Poly1305 to encrypted files.
- Cross-platform clients: Windows, Linux, Android
- Privacy-first: all your data, even filename, encrypted before upload


### Cryptography details
- KDF: Argon2id
- Authenticated encryption: XChaCha20-Poly1305


### User flow
1. Account creation: register
2. Create an note repo, then you got '.haha_note' folder in your dir, this is haha_note data dir of your repo(just like .git folder for git), don't edit it by your self.
3. Create some files, then sync

