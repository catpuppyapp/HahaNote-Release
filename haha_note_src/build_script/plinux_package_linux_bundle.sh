#!/usr/bin/env bash
pushd . >/dev/null
targetPath="../build/linux/x64/release"
cd "$targetPath"
old="bundle"; new="HahaNote"; zip="HahaNote_linux_x64.zip"; zipp="HahaNote_linux_x64_portable.zip"
# -- 表示选项结束（end-of-options），告诉 mv 之后的参数都被当作位置参数（文件/目录名），即便它们以 - 开头也不会被解释为选项。常用于防止文件名以 - 开头被误识别为命令选项。
mv -- "$old" "$new"
# 重定向file descriptor 1>/dev/null 隐藏stdout(fd 1即stdout），2>/dev/null 隐藏stderr
zip -r "$zip" "$new" 1>/dev/null
touch -- "$new/portable"
zip -r "$zipp" "$new" 1>/dev/null
# echo "$targetPath"
popd >/dev/null
