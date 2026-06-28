flutter clean
chmod +x blinux_build_linux.sh
chmod +x plinux_package_linux_bundle.sh
./blinux_build_linux.sh
./plinux_package_linux_bundle.sh

echo ../build/linux/x64/release
