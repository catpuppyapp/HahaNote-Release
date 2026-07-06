# flutter pub get then use sed to add build-id=none to CMakeLists.txt for pass the RB, else maybe generate difference apks
# see: https://codeberg.org/IzzyOnDroid/repodata/issues/327#issuecomment-18667955
flutter pub get
echo flutter_pub_cache_path_is:
echo ${PUB_CACHE}
sed -i -e 's/-Wl,/-Wl,--build-id=none,/' ${PUB_CACHE}/hosted/*/jni-*/src/CMakeLists.txt
