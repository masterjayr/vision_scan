import com.android.build.api.variant.LibraryAndroidComponentsExtension
import java.net.URL
import java.util.zip.ZipInputStream
import org.gradle.api.DefaultTask
import org.gradle.api.file.DirectoryProperty
import org.gradle.api.provider.ListProperty
import org.gradle.api.provider.Property
import org.gradle.api.tasks.Input
import org.gradle.api.tasks.OutputDirectory
import org.gradle.api.tasks.TaskAction
import org.jetbrains.kotlin.gradle.dsl.JvmTarget

group = "com.vision.scan.vision_scan"
version = "0.0.10"

plugins {
    id("com.android.library")
}

android {
    namespace = "com.vision.scan.vision_scan"
    compileSdk = 37

    defaultConfig {
        minSdk = 24
    }

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    // Do NOT register Provider-based paths on sourceSets.jniLibs — AGP 9+ rejects that
    // ("You cannot add Provider instances to the Android SourceSet API").
    // Generated jniLibs are wired below via androidComponents / Variant Sources API.
}

kotlin {
    compilerOptions {
        jvmTarget = JvmTarget.JVM_17
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
val githubReleaseBaseUrl =
    "https://github.com/masterjayr/vision_scan/releases/download/v$pluginVersion"

val nativeAbis = listOf(
    "arm64-v8a",
    "armeabi-v7a",
    "x86_64",
)

/**
 * Downloads (or skips when src/main/jniLibs already has .so files) and writes
 * ABI-scoped native libs into [outputDirectory]. AGP wires this directory into
 * each variant via [SourceDirectories.addGeneratedSourceDirectory], which also
 * establishes the correct task dependency (AGP 8 + AGP 9).
 */
abstract class PrepareNativeLibsTask : DefaultTask() {
    @get:OutputDirectory
    abstract val outputDirectory: DirectoryProperty

    @get:Input
    abstract val releaseBaseUrl: Property<String>

    @get:Input
    abstract val abis: ListProperty<String>

    @get:Input
    abstract val localJniLibsPath: Property<String>

    @get:Input
    abstract val downloadsDirPath: Property<String>

    @TaskAction
    fun prepare() {
        val nativeRoot = outputDirectory.get().asFile
        val downloadRoot = File(downloadsDirPath.get())
        ensureDir(downloadRoot)
        ensureDir(nativeRoot)

        if (hasLocalNativeLibs(File(localJniLibsPath.get()))) {
            logger.lifecycle(
                "Local native libs detected at ${localJniLibsPath.get()} — " +
                    "skipping GitHub Releases download",
            )
            return
        }

        abis.get().forEach { abi ->
            val zipName = "android-$abi.zip"
            val zipUrl = "${releaseBaseUrl.get()}/$zipName"
            val zipFile = File(downloadRoot, zipName)

            downloadIfMissing(zipUrl, zipFile)

            logger.lifecycle("Unzipping $zipName -> ${nativeRoot.path}")
            unzip(zipFile, nativeRoot)

            val so = File(nativeRoot, "$abi/libvision_scan_native.so")
            if (!so.exists()) {
                error(
                    "Missing libvision_scan_native.so for $abi under ${nativeRoot.path}. " +
                        "Check GitHub Release contents at $zipUrl",
                )
            }
            logger.lifecycle("Found ${so.path}")
        }
    }

    private fun hasLocalNativeLibs(jniDir: File): Boolean {
        if (!jniDir.exists()) return false
        return jniDir.walkTopDown().any { it.isFile && it.extension == "so" }
    }

    private fun ensureDir(dir: File) {
        if (!dir.exists()) dir.mkdirs()
    }

    private fun downloadIfMissing(url: String, outFile: File) {
        if (outFile.exists() && outFile.length() > 0) {
            logger.lifecycle("Cached: ${outFile.name}")
            return
        }
        ensureDir(outFile.parentFile)
        logger.lifecycle("Downloading $url")
        URL(url).openStream().use { input ->
            outFile.outputStream().use { output -> input.copyTo(output) }
        }
    }

    private fun unzip(zip: File, dest: File) {
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
}

val prepareNativeLibs =
    tasks.register<PrepareNativeLibsTask>("prepareNativeLibs") {
        group = "build"
        description =
            "Download vision_scan native .so zips from GitHub Releases (or skip if local jniLibs exist)"
        releaseBaseUrl.set(githubReleaseBaseUrl)
        abis.set(nativeAbis)
        localJniLibsPath.set(project.file("src/main/jniLibs").absolutePath)
        downloadsDirPath.set(
            layout.buildDirectory.dir("nativeDownloads").map { it.asFile.absolutePath },
        )
        // Fixed location; also used as the generated jniLibs source directory.
        outputDirectory.set(layout.buildDirectory.dir("intermediates/vision_scan_native"))
    }

// AGP 8+/9: register generated jniLibs through Variant Sources API (not SourceSet Providers).
extensions.configure<LibraryAndroidComponentsExtension>("androidComponents") {
    onVariants { variant ->
        variant.sources.jniLibs?.addGeneratedSourceDirectory(
            prepareNativeLibs,
            PrepareNativeLibsTask::outputDirectory,
        )
    }
}
