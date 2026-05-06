HahaNote support use git as backend to store your encrypted data.

Tutorial on Android: link
Tutorial on PC: link

NOTE: HahaNote can only use git to storage encrypted files, that means git can't know your files content, and the git diff and other git features not available for your decrypted files.

---
### On Android:
##### Create:
0. assume your git repo named "my_git_repo", and haha note repo named "my_haha_repo"
1. install PuppyGit, HahaNote need it to do git operations
2. enable http service in PuppyGit and make sure allow PuppyGit running in background and disable Battery optimization for it
3. create and clone your git repo in PuppyGit
4. go to HahaNote, create your repo
5. choose LocalDir as remote, and checked "Git backend"
6. filled your git repo path that cloned just now via PuppyGit, and append your repo name, got a path like: /storage/emulate/0/PuppyGit/my_git_repo/my_haha_repo, use it as your remote path
7. go to PuppyGit, select your git repo, click bottom bar menu icon, choose "Api", then copy pull/push/sync url to haha note.
8. choose a path as local dir, that save your decrypted files
9. set a master password to protect your data
10. submit

##### Import
almost same as Create, just clone your git repo, and choose Import in hahanote, then filled your gitrepo/hahanote repo path, and copy pull/push/sync url from PuppyGit, etc.

---

### On Pc:
##### Create:
0. assume your git repo named "my_git_repo", and haha note repo named "my_haha_repo"
1. install Git: https://git-scm.com/install/
2. set git to your path, usually is default, you can open an terminal and type git to verify it
3. create an dedicated repo for haha note on git platform, like github/gitlab
3. clone your git repo to local dir
4. use HahaNote create an "LocalDir" repo under your git repo
<br>
then HahaNote will auto do git pull/push when you sync in HahaNote

##### Import
1. install Git
2. clone it
3. choose "Import" in HahaNote, and choose "LocalDir", then select your cloned git repo as remote

