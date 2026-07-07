#!/usr/bin/env bash

chmod +x prebuild.sh
./prebuild.sh

pushd ..
flutter build apk --release --split-per-abi


popd
# echo "explorer ..\build\app\outputs\flutter-apk"
