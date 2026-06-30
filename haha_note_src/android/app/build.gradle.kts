plugins {
    id("com.android.application")
//    id("kotlin-android")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
    id("kotlin-parcelize")
}

android {
    packaging {
        // dex.useLegacyPackaging + jniLibs.useLegacyPackaging can be make app installer smaller,
        // maybe compress the libs? if it is, then maybe make install process slower a little bit
        dex {
            useLegacyPackaging = true
        }
        jniLibs {
            // 此参数作用是: "安装apk后把 .so libs 导出到对应架构的目录"，不然可能不会导出
            //
            // 详细解释：
            // 由于安卓10以上对 "/data/data/包名" 下的目录做了 “可写和可执行互斥”的限制，而app对此目录下又可写，
            // 所以把可执行文件放这个目录就不能执行，会抛权限被拒绝的异常
            // 但对 "/data/app/乱码/包名.乱码/lib/架构" 下的so库则是可执行不可写，
            // 因此，可以把可执行文件放到 lib 目录就能使其可执行了
            //
            // 注：可写和可执行互斥是为了避免app安装后被恶意利用，下载文件，执行，或者被黑客利用，
            // 修改原本应该被执行的文件执行任意代码，总之主要是为了安全考虑，有此限制就可在多数情况
            // 下确保应用执行的一定是安装时携带的文件，而安装后下载或创建的文件则不被执行
            useLegacyPackaging = true
        }
    }

    // quit include google signature block in the built apk file, these info using google public key encrypted, if don't publish app to google play, is nonsense
    // see: https://developer.android.com/build/dependencies?hl=zh-cn#dependency-info-play
    dependenciesInfo {
        // Disables dependency metadata when building APKs.
        includeInApk = false
        // Disables dependency metadata when building Android App Bundles.
        includeInBundle = false
    }

    // 这个必须用字面量，否则有可能只是AndroidManifest.xml找不到包名
    namespace = "com.catpuppyapp.hahanote"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

//    kotlinOptions {
//        jvmTarget = JavaVersion.VERSION_17.toString()
//    }

//    sourceSets["main"].jniLibs.srcDir("jniLibs")


    defaultConfig {
        //ndk {
        //    abiFilters += listOf("arm64-v8a", "x86_64", "x86", "armeabi-v7a")
        //}

        // TODO: Specify your own unique Application ID (https://developer.android.com/studio/build/application-id.html).
        applicationId = namespace
        // You can update the following values to match your application needs.
        // For more information, see: https://flutter.dev/to/review-gradle-config.
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName



        //这两个file provider的值必须一样
        //可以在代码里用`BuildConfig.变量名`使用的值
        // 4个引号的原因：三个是raw string，另外一个是为了赋值变量时包含引号，不然会直接裸值替换上去，就不是String类型了
        buildConfigField("String", "FILE_PROVIDIER_AUTHORITY", """"$applicationId.file_provider"""")
        //可以在xml里用“@string/变量名”使用的值，目前在 `AndroidManifest.xml` 里使用了
        resValue("string", "file_provider_authority", "$applicationId.file_provider")

    }


    buildFeatures {
//        compose = true

        //不开这个不能用BuildConfig，我是为了用来获取versionName和versionCode
        //导入： import 包名.BuildConfig，然后就能使用BuildConfig了
        buildConfig = true
    }


    buildTypes {
        release {
            // TODO: Add your own signing config for the release build.
            // Signing with the debug keys for now, so `flutter run --release` works.
            // 禁用签名，不然它直接用debug key签我的release apk了
//            signingConfig = signingConfigs.getByName("debug")
        }
    }
}

kotlin {
    compilerOptions {
        jvmTarget = org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_17
    }
}


flutter {
    source = "../.."
}

dependencies {
    // Kotlin 项目（首选）
    implementation("androidx.core:core-ktx:1.16.0")



    // 或者仅使用 core（Java）
    // implementation("androidx.core:core:1.9.0")
}
