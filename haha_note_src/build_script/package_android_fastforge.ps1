cd ..
fastforge package --platform=android --targets=apk --flutter-build-args=release,obfuscate,"split-debug-info=build/symbols_mapping/apk"
cd build_script
