#!/usr/bin/env bash

chmod +x prebuild.sh
# `. ./script` or `source ./script`,
# both run script in current shell,
# so can share envs
# the `. ./script` most commonly accepted by many shells(更通用)
. ./prebuild.sh

pushd ..
flutter build apk --release --split-per-abi


popd
# echo "explorer ..\build\app\outputs\flutter-apk"
