plugins {
    kotlin("jvm") version "2.4.20"
    `java-library`
    `maven-publish`
}

group = "com.abcp"
version = "0.1.0"

repositories { mavenCentral() }

dependencies {
    // Connect runtime + OkHttp transport (the caller owns the transport).
    api("com.connectrpc:connect-kotlin:0.9.0")
    api("com.connectrpc:connect-kotlin-okhttp:0.9.0")
    // Protobuf-lite SerializationStrategy: connect-kotlin is transport-only and
    // needs an explicit strategy for the LITE messages the generator emits.
    api("com.connectrpc:connect-kotlin-google-javalite-ext:0.9.0")
    // The generated messages use the protobuf LITE runtime (matches `opt: lite`).
    api("com.google.protobuf:protobuf-javalite:4.36.2")
    // The generated `*Kt.kt` DSL builders need the Kotlin lite runtime.
    api("com.google.protobuf:protobuf-kotlin-lite:4.36.2")
}

java {
    sourceCompatibility = JavaVersion.VERSION_17
    targetCompatibility = JavaVersion.VERSION_17
}

kotlin {
    compilerOptions {
        jvmTarget.set(org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_17)
    }
}

tasks.withType<JavaCompile>().configureEach {
    options.release.set(17)
}
