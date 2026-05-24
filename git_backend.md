### HahaNote support use Git as backend to store your encrypted data.
<br>

#### If you can use DropBox/WebDav or other way to sync your HahaNote data, then you should not use git, see the `Limits` below

Tutorial on Android: https://www.youtube.com/watch?v=k-f1JKRgeVM
<br>
Tutorial on PC: https://www.youtube.com/watch?v=b_7LMknoTI4
<br>

#### NOTE: HahaNote can only use git to storage encrypted files, that means git can't know your files content, and the git diff and other git features not available for your decrypted files.
---
### Limits
1. Due to HahaNote data base all is binary file, so it make your git repo fast to fat, your GitHub storage maybe excedded, you can regular run below commands to clean unused git objects:
    - on your local device, cd to your git dir, run git log, find first commit, do `git reset --soft firstCommitHash`, then `git add -A`, then do `git commit -m reset_to_first_commit` and `git push --force`
    - on git platform(linke GitHub): go to repository settings page, and find options like "GC" or "Clean repo", then do a GC to free unused data.

---
### On Android:
##### Create:
0. assume your git repo named "my_git_repo", and haha note repo named "my_haha_repo"
1. install PuppyGit, HahaNote need it to do git operations
2. enable http service in PuppyGit and make sure allow PuppyGit running in background and disable Battery optimization for it
3. create and clone your git repo in PuppyGit
4. go to HahaNote, create your repo
5. choose LocalDir as remote, and checked "Git backend"
6. fill your git repo path that cloned just now via PuppyGit, and append your repo name, got a path like: /storage/emulate/0/PuppyGit/my_git_repo/my_haha_repo, use it as your remote path
7. go to PuppyGit, select your git repo, click bottom bar menu icon, choose "Api", then copy pull/push/sync url to haha note.
8. choose a path as local dir, that save your decrypted files
9. set a master password to protect your data
10. submit

##### Import
almost same as Create, just clone your git repo, and choose Import in hahanote, then fill your gitrepo/hahanote repo path, and copy pull/push/sync url from PuppyGit.

---

### On Pc:
##### Create:
0. assume your git repo named "my_git_repo", and haha note repo named "my_haha_repo"
1. install Git: https://git-scm.com/install/
2. set git to your PATH, usually is set up after you installed git, you can open an terminal and type git to verify it
3. create a dedicated repo for haha note on git platform, like github/gitlab
3. clone your git repo to local dir, set your git user.email/user.name, and make sure your git credential is remembered, otherwise HahaNote will got err when call git pull/push.
4. use HahaNote create a "LocalDir" repo under your git repo, e.g. your git repo is /home/user/mygitrepo, then your HahaNote repo's remote can be like: /home/user/mygitrepo/my_hahanote_data
<br>
then HahaNote will auto do git pull/push when you do sync in HahaNote

##### Import
1. install Git
2. clone it
3. choose "Import" in HahaNote, and choose "LocalDir", then select your cloned git repo as remote
4. the other steps just like Create
