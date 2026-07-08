#!/usr/bin/env bash

set -e

# path cannot add quote sign "", else the path will not expand
CODE_FORGE_BASE=$(ls -d ${PUB_CACHE}/hosted/pub.dev/code_forge-*)
cp -f cargokit.yaml "${CODE_FORGE_BASE}/rust/cargokit.yaml"
cp -f options.dart "${CODE_FORGE_BASE}/cargokit/build_tool/lib/src/options.dart"

# test set -e
cp -f abc.txt /bad/path/abc/def/gkdjgkdjglkd.txt
