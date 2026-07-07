#!/usr/bin/env bash

# install rust toolchain
# install rustup
# the command must run in rust-toolchain.toml dir (or it's parent?)
# sh -s -- -y, the -s is read from stdin
# -y is answer yes
curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y
. "$HOME/.cargo/env"
# run the command will trigger rust toolchains download, 
# the version specified rust-toolchain.toml file, 
# find current dir first, if not found, find parent, most maybe 3 layers dirs
. versions.sh
rustup toolchain install ${VER_RUST_TOOLCHAIN}
rustup default ${VER_RUST_TOOLCHAIN}
export RUSTUP_TOOLCHAIN=${VER_RUST_TOOLCHAIN}
# reload rust env
. "$HOME/.cargo/env"

# rustup target add \
#   aarch64-linux-android \
#   armv7-linux-androideabi \
#   i686-linux-android \
#   x86_64-linux-android \
#   x86_64-pc-windows-gnu \
#   x86_64-unknown-linux-gnu

# rustup toolchain uninstall stable


# check version
echo rust print: rust toolchain version is:
cargo --version
rustc -Vv
echo rustup show
rustup show


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

