#!/usr/bin/env bash

# flutter pub get then use sed to add build-id=none to CMakeLists.txt for pass the RB, else maybe generate difference apks
# see: https://codeberg.org/IzzyOnDroid/repodata/issues/327#issuecomment-18667955
flutter pub get
echo flutter print: flutter_pub_cache_path_is:
echo ${PUB_CACHE}

echo "will try insert 'build-id=none' to 'flutter pub cache/middle dirs/CMakeLists.txt'"

# if file does not exist, will throw err
# sed -i -e 's/-Wl,/-Wl,--build-id=none,/' ${PUB_CACHE}/hosted/*/jni-*/src/CMakeLists.txt
# find then sed to avoid throw err, it will only run sed when file exists
find "${PUB_CACHE}/hosted/" -path "*/jni-*/src/CMakeLists.txt" -exec sed -i -e 's/-Wl,/-Wl,--build-id=none,/' {} +

# apply cargokit patch for code_forge, to make sure it use our expceted rust toolchain
echo "apply cargokit_patch (for code_forge)"
pushd cargokit_patch
chmod +x apply.sh
./apply.sh
popd
