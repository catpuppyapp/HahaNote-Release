:: 需要手动执行以下命令，自动执行不知道为什么，第2条命令不会执行
dart run build_runner build -d

:: 这个不知道为什么执行脚本时不会执行，可能是因为我之前使用的linux换行符？
:: 更新mac和ios配置文件，添加对应语种的
:: 只有在新增或删除了语种后，才需要运行这个
dart run slang configure
