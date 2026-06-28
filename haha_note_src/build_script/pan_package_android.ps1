cd ..

# debug sign apk
apksigner sign --ks %USERPROFILE%/.myandroid/mydebugkey-android.jks --ks-key-alias android --ks-pass pass:android --key-pass pass:android --out build\app\outputs\flutter-apk\debug-sign-arm64.apk build\app\outputs\flutter-apk\app-arm64-v8a-release.apk
apksigner verify build\app\outputs\flutter-apk\debug-sign-arm64.apk

cd build_script

# echo "explorer ..\build\app\outputs\flutter-apk"
