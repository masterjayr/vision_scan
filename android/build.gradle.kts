import java.net.URL
import java.util.zip.ZipInputStream
import org.jetbrains.kotlin.gradle.dsl.JvmTarget

group = "com.vision.scan.vision_scan"
version = "0.0.8"

plugins {
    id("com.android.library")
}

android {
    namespace = "com.vision.scan.vision_scan"
    compileSdk = 36

    defaultConfig {
        minSdk = 24
    }

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    // 🔑 Load native libs from build/ (cleaned by `flutter clean`)
    sourceSets["main"].jniLibs.srcDirs(
        layout.buildDirectory.dir("intermediates/vision_scan_native")
    )
}

kotlin {
    compilerOptions {
        jvmTarget.set(JvmTarget.JVM_17)
    }
}

repositories {
    google()
    mavenCentral()
}

// -------------------------------------------------
// GitHub Releases config
// -------------------------------------------------
val pluginVersion = project.version.toString()
val baseUrl =
    "https://github.com/masterjayr/vision_scan/releases/download/v$pluginVersion"

val abis = listOf(
    "arm64-v8a",
    "armeabi-v7a",
    "x86_64"
)

val downloadsDir = layout.buildDirectory.dir("nativeDownloads")
val nativeOutDir = layout.buildDirectory.dir("intermediates/vision_scan_native")

fun ensureDir(dir: File) {
    if (!dir.exists()) dir.mkdirs()
}

fun downloadIfMissing(url: String, outFile: File) {
    if (outFile.exists() && outFile.length() > 0) {
        println("✅ Cached: ${outFile.name}")
        return
    }

    ensureDir(outFile.parentFile)
    println("⬇️  Downloading $url")
    URL(url).openStream().use { input ->
        outFile.outputStream().use { output ->
            input.copyTo(output)
        }
    }
}

fun unzip(zip: File, dest: File) {
    ZipInputStream(zip.inputStream().buffered()).use { zis ->
        while (true) {
            val entry = zis.nextEntry ?: break
            val out = File(dest, entry.name)

            if (entry.isDirectory) {
                out.mkdirs()
            } else {
                ensureDir(out.parentFile)
                out.outputStream().use { zis.copyTo(it) }
            }
            zis.closeEntry()
        }
    }
}

fun hasLocalNativeLibs(): Boolean {
    val jniDir = project.file("src/main/jniLibs")
    if (!jniDir.exists()) return false

    return jniDir.walkTopDown().any { it.isFile && it.extension == "so" }
}

tasks.register("prepareNativeLibs") {
    doLast {
        val downloadRoot = downloadsDir.get().asFile
        val nativeRoot = nativeOutDir.get().asFile

        ensureDir(downloadRoot)
        ensureDir(nativeRoot)

        if (hasLocalNativeLibs()) {
    println("🧪 Local native libs detected — skipping GitHub Releases download")
    return@doLast
}

abis.forEach { abi ->
    val zipName = "android-$abi.zip"
    val zipUrl = "$baseUrl/$zipName"
    val zipFile = File(downloadRoot, zipName)

    downloadIfMissing(zipUrl, zipFile)

    println("📦 Unzipping $zipName")
    unzip(zipFile, nativeRoot)

    val so = File(nativeRoot, "$abi/libvision_scan_native.so")
    if (!so.exists()) {
        error(
            "❌ Missing libvision_scan_native.so for $abi\n" +
            "Check GitHub Release contents."
        )
    } else {
        println("✅ Found ${so.path}")
    }
}

    
        }
    }


// Ensure native libs are ready before Android builds
tasks.matching { it.name == "preBuild" }.configureEach {
    dependsOn("prepareNativeLibs")
}