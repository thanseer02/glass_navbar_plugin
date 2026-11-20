group = "com.tnitish.native_glass_navbar"
version = "1.0-SNAPSHOT"

plugins {
    id("com.android.library")
}

configure<com.android.build.api.dsl.LibraryExtension> {
    namespace = "com.tnitish.native_glass_navbar"
    compileSdk = 35

    defaultConfig {
        minSdk = 24
        consumerProguardFiles("consumer-rules.pro")
    }

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_11
        targetCompatibility = JavaVersion.VERSION_11
    }
}

dependencies {
    compileOnly("androidx.annotation:annotation:1.9.1")
    compileOnly("androidx.core:core-ktx:1.15.0")
}
