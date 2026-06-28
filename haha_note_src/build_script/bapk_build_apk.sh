#!/usr/bin/env bash

cd ..
flutter build apk --release --split-per-abi


cd build_script
# echo "explorer ..\build\app\outputs\flutter-apk"
