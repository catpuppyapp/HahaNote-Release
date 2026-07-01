1. copy an implemented remote, e.g. `haha_note_src/lib/cloud_disk_note/remotes/dropbox.dart`, then rename it to the cloud drive name which you will implement, e.g. `xxdrive.dart`, then implement the necessary functions.

2. add your remote type to `RemoteType.supportedTypes` (at `haha_note_src/lib/cloud_disk_note/remotes/base/remote.dart`), and implement ui for it.

3. test

4. send pr to the project


note:
if need register developer on the cloud drive platform, you should register a test name and keep the name `HahaNote` to us.
