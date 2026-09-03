

---
更新app流程 20260822：
更新 pubspec.yaml 中的版本号
更新 changelog.md 中的更新日志
更新 changelog_dialog.dart 中的更新日志
fastlane下，创建 新版本号.txt，并填入对应语言的更新内容

---
更新code_forge 20260822:
初次：
1 克隆我的fork: https://github.com/Bandeapart1964/code_forge.git
2 切换到分支 support_rustup_toolchain_from_env: git checkout support_rustup_toolchain_from_env
3 添加源仓库: git remote add src https://github.com/heckmon/code_forge.git
4 fetch源仓库: git fetch src
5 rebase我的patch到源仓库最新提交（在我的fork仓库的 support_rustup_toolchain_from_env 执行）: git rebase src/main
6 推送我的提交: `git push --force-with-lease` or `git push --force`
7 force-with-lease应该是比较远程和本地提交的最新分支，如果一样再强制推送，否则拒绝，可避免覆盖远程存在但本地不存在的提交（实现猜想：先记录本地 origin/分支 的提交号，然后fetch，如果fetch后的提交号和之前一样，则强推，否则拒绝强推，并非百分百避免覆盖远程提交，但能大幅降低错误覆盖的概率，更进一步，可手动指定一个提交，只有远程分支最新提交是你期望的提交时，才覆盖，而git确保提交相同则后续历史相同，因此只比较提交就可确保本地和远程拥有相同的提交历史，这样如果依然发生小概率的错误覆盖的话，可通过本地恢复之前被覆盖的数据，git reflog 找下被覆盖的提交号即可）
8 更新项目中的 pubspec.yaml 为如下：
``` yaml
  code_forge:
    git:
      url: https://github.com/Bandeapart1964/code_forge.git
      ref: 你的fork的最新提交
```

后续更新：
从第4步开始执行即可。
若有多个非连续提交需要合并，可用cherry-pick替代rebase，具体流程如下：
1. 先checkout到 src/main (detached HEAD或创建临时分支都行，建议创建临时分支，合并时用分支名就行，不然还得记提交号)
2. 再 cherry-pick (可cherry-pick多个提交，例如 `cherry-pick 提交1 提交2 提交4`)
3. 把support_rustup_toolchain_from_env hard reset到刚才合并完成的提交

---
更新tls证书流程 20260822：
下载证书: https://curl.se/ca/cacert.pem
证书来自网页: https://curl.se/docs/caextract.html

复制证书到 test/res/bundled_certs.pem
修改cert_test.dart中的更新时间和证书时间
执行cert_test.dart
执行项目根目录下的 cp_tls_cert.sh （作用是拷贝证书到指定目录）

