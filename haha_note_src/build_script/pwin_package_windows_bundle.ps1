Push-Location .
$targetPath="..\build\windows\x64\runner"
cd $targetPath
$old="Release"; $new="HahaNote"; $zip="HahaNote_windows_x64.zip"; $zipp="HahaNote_windows_x64_portable.zip"
Rename-Item $old $new
# AI说：& 确保调用外部命令而不是脚本内部同名变量或函数，我没验证
# & 7z a -tzip -r -y $zip $new
Compress-Archive -Path $new -DestinationPath $zip -Force
New-Item "$new\portable" -ItemType File -Force | Out-Null
# & 7z a -tzip -r -y $zipp $new
Compress-Archive -Path $new -DestinationPath $zipp -Force
# echo "explorer $targetPath"
Pop-Location
