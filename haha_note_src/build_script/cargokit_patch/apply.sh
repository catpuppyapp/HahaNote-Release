#!/usr/bin/env bash

# if any non-zero returned, then abort this script, 
# but will not abort github workflow, 
# just abort to run the commands in this file after the line which return non-zero
# `echo $?` to show returned of last executed command
set -e

echo "BEGIN: apply cargokit_patch for code_forge"

# path cannot add quote sign "", else the path will not expand
CODE_FORGE_BASE=$(ls -d ${PUB_CACHE}/hosted/pub.dev/code_forge-*)
cp -f cargokit.yaml "${CODE_FORGE_BASE}/rust/cargokit.yaml"
cp -f options.dart "${CODE_FORGE_BASE}/cargokit/build_tool/lib/src/options.dart"

# test set -e (expect: after commands will not execute, result: passed)
# cp -f abc.txt /bad/path/abc/def/bad.txt.1701428416127150

echo "END: apply cargokit_patch for code_forge"
