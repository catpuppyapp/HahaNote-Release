plugins {
    id("com.android.application")
//    id("kotlin-android")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
    id("kotlin-parcelize")
}

android {
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
