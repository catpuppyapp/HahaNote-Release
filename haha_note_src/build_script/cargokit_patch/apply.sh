#!/usr/bin/env bash

# if any non-zero returned, then abort this script
set -e

echo "BEGIN: apply cargokit_patch for code_forge"

# path cannot add quote sign "", else the path will not expand
CODE_FORGE_BASE=$(ls -d ${PUB_CACHE}/hosted/pub.dev/code_forge-*)
cp -f cargokit.yaml "${CODE_FORGE_BASE}/rust/cargokit.yaml"
cp -f options.dart "${CODE_FORGE_BASE}/cargokit/build_tool/lib/src/options.dart"

# test set -e (expect: after commands will not execute)
cp -f abc.txt /bad/path/abc/def/gkdjgkdjglkd.txt

echo "END: apply cargokit_patch for code_forge"
