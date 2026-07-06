# install rust toolchain
# install rustup
curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh
# run the command will trigger rust toolchains download, 
# the version specified rust-toolchain.toml file, 
# find current dir first, if not found, find parent, most maybe 3 layers dirs
rustc -Vv


# flutter pub get then use sed to add build-id=none to CMakeLists.txt for pass the RB, else maybe generate difference apks
# see: https://codeberg.org/IzzyOnDroid/repodata/issues/327#issuecomment-18667955
flutter pub get
echo flutter print: flutter_pub_cache_path_is:
echo ${PUB_CACHE}

echo rust print: rustc version is:
rustc -Vv

sed -i -e 's/-Wl,/-Wl,--build-id=none,/' ${PUB_CACHE}/hosted/*/jni-*/src/CMakeLists.txt
