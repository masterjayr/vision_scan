#!/usr/bin/env python3
"""Generate Native Distribution Learning Guide PDF for vision_scan."""

from pathlib import Path

from fpdf import FPDF

OUT = Path(__file__).resolve().parent / "native_distribution_learning_guide.pdf"


class GuidePDF(FPDF):
    def header(self):
        if self.page_no() == 1:
            return
        self.set_font("Helvetica", "I", 8)
        self.set_text_color(100, 100, 100)
        self.cell(0, 8, "vision_scan - Native Distribution Learning Guide", align="L")
        self.ln(10)

    def footer(self):
        self.set_y(-12)
        self.set_font("Helvetica", "I", 8)
        self.set_text_color(120, 120, 120)
        self.cell(0, 8, f"Page {self.page_no()}", align="C")

    def h1(self, text):
        self.set_x(self.l_margin)
        self.set_font("Helvetica", "B", 18)
        self.set_text_color(20, 20, 20)
        self.multi_cell(0, 10, text)
        self.set_x(self.l_margin)
        self.ln(2)

    def h2(self, text):
        self.ln(3)
        self.set_x(self.l_margin)
        self.set_font("Helvetica", "B", 13)
        self.set_text_color(30, 60, 110)
        self.multi_cell(0, 8, text)
        self.set_x(self.l_margin)
        self.ln(1)

    def h3(self, text):
        self.ln(2)
        self.set_x(self.l_margin)
        self.set_font("Helvetica", "B", 11)
        self.set_text_color(40, 40, 40)
        self.multi_cell(0, 7, text)
        self.set_x(self.l_margin)
        self.ln(1)

    def body(self, text):
        self.set_x(self.l_margin)
        self.set_font("Helvetica", "", 10)
        self.set_text_color(25, 25, 25)
        self.multi_cell(0, 5.5, text)
        self.set_x(self.l_margin)
        self.ln(1)

    def bullet(self, text, indent=8):
        self.set_x(self.l_margin + indent)
        self.set_font("Helvetica", "", 10)
        self.set_text_color(25, 25, 25)
        width = self.w - self.r_margin - self.l_margin - indent
        self.multi_cell(width, 5.5, f"- {text}")
        self.set_x(self.l_margin)

    def code(self, text):
        self.set_x(self.l_margin)
        self.set_font("Courier", "", 8.5)
        self.set_text_color(40, 40, 40)
        self.set_fill_color(245, 245, 245)
        self.multi_cell(0, 4.5, text, fill=True)
        self.set_x(self.l_margin)
        self.ln(2)

    def topic(self, title, why, research):
        self.set_x(self.l_margin)
        self.set_font("Helvetica", "B", 10)
        self.set_text_color(20, 20, 20)
        self.multi_cell(0, 5.5, title)
        self.set_x(self.l_margin)
        self.set_font("Helvetica", "", 9.5)
        self.set_text_color(50, 50, 50)
        self.multi_cell(0, 5, f"Why it matters here: {why}")
        self.set_x(self.l_margin)
        self.set_font("Helvetica", "I", 9)
        self.multi_cell(0, 5, f"Research: {research}")
        self.set_x(self.l_margin)
        self.ln(2)


def build():
    pdf = GuidePDF(format="A4")
    pdf.set_auto_page_break(auto=True, margin=16)
    pdf.add_page()

    pdf.h1("Native Distribution Learning Guide")
    pdf.body(
        "A research curriculum grounded in the vision_scan Flutter FFI plugin. "
        "Use this when you are ready to deepen how native code is built, packaged, "
        "published, and loaded on iOS, Android, and Windows."
    )
    pdf.body(
        "Repo mental model: C/C++ (OpenCV + ZXing) -> platform binary "
        "(.xcframework / .so / .dll) -> GitHub Release zip -> consumer fetch "
        "(CocoaPods / SPM / Gradle / setup_windows) -> Dart FFI."
    )

    pdf.h2("1. Big picture: what you already intuited")
    pdf.body(
        "iOS: You ship an XCFramework. Inside it are one or more .framework slices "
        "(device, maybe simulator). Each framework contains compiled machine code plus "
        "headers/module maps. At app build time the linker embeds/links that code into "
        "the app. Dart then uses DynamicLibrary.process() because symbols are already "
        "in the process."
    )
    pdf.body(
        "Android: You ship .so shared objects per ABI (arm64-v8a, armeabi-v7a, x86_64). "
        "They are packaged into the APK under lib/<abi>/. At runtime the dynamic linker "
        "loads them. Dart uses DynamicLibrary.open('libvision_scan_native.so'). "
        "Dependent .so files (OpenCV, libc++_shared) must also be packaged."
    )
    pdf.body(
        "Windows: You ship a .dll (plus OpenCV runtime DLLs). They must sit beside the "
        "Flutter runner .exe. Dart uses DynamicLibrary.open('vision_scan_native.dll'). "
        "Consumers run dart run vision_scan:setup_windows to fetch the zip."
    )

    pdf.h2("2. Suggested learning order")
    for i, step in enumerate(
        [
            "C ABI, headers, extern \"C\", and export macros",
            "Shared engine logic (native/src, qr_engine.h)",
            "CMake fundamentals (SHARED libs, imported deps)",
            "Android NDK cross-compile + jniLibs + Gradle packaging",
            "iOS frameworks / XCFrameworks + xcodebuild",
            "CocoaPods prepare_command vs SPM binaryTarget + checksum",
            "Windows MSVC / Visual Studio CMake generator + DLL loading",
            "Bash packaging scripts and deterministic zips",
            "GitHub Actions: runners, tags, artifacts, releases",
            "Dart FFI: DynamicLibrary, structs, memory ownership",
            "Release engineering: version coupling and failure modes",
        ],
        1,
    ):
        pdf.bullet(f"{i}. {step}")

    pdf.add_page()
    pdf.h2("3. Core topics to research (all platforms)")

    pdf.topic(
        "Machine code vs source distribution",
        "vision_scan does not ask consumers to compile OpenCV/ZXing. CI builds binaries; apps download them.",
        "prebuilt binaries vs building from source; reproducible builds; binary compatibility",
    )
    pdf.topic(
        "Static linking vs dynamic linking",
        "ZXing is often built as .a (static) then linked into your shared product. OpenCV may remain a separate .so/.dll/.framework.",
        "static vs shared libraries; rpath; DT_NEEDED; App Store bitcode/linking rules (historical)",
    )
    pdf.topic(
        "C ABI / calling conventions",
        "Dart FFI and C must agree on struct layout and symbol names (qr_engine.h).",
        "ABI stability; packing/alignment; name mangling; extern \"C\"",
    )
    pdf.topic(
        "CMake",
        "All three scripts use CMake to produce SHARED libraries and wire OpenCV/ZXing.",
        "add_library SHARED; IMPORTED targets; generators (Ninja, Visual Studio); toolchain files",
    )
    pdf.topic(
        "Cross-compilation",
        "Android builds on Linux/macOS for phone CPUs; iOS builds on macOS for arm64 device/sim.",
        "host vs target; sysroot; Android NDK toolchain; Apple SDKs",
    )
    pdf.topic(
        "Versioning & release assets",
        "Tag v0.0.9 must match pubspec, podspec, android/build.gradle.kts, Package.swift URL.",
        "semver; GitHub Releases; CDN caching; checksum integrity",
    )

    pdf.h2("4. iOS-specific research list")
    pdf.topic(
        "Framework vs XCFramework",
        "scripts/build_ios.sh archives a framework then wraps with xcodebuild -create-xcframework.",
        "Apple XCFramework docs; device vs simulator slices; Mac Catalyst pitfalls",
    )
    pdf.topic(
        "xcodebuild archive & destinations",
        "CI needs iOS platform installed; SUPPORTS_MACCATALYST=NO; generic/platform=iOS.",
        "xcodebuild CLI; destinations; downloadPlatform; BUILD_LIBRARY_FOR_DISTRIBUTION",
    )
    pdf.topic(
        "lipo and fat binaries",
        "Simulator ZXing arm64 + x86_64 are merged before XCFramework creation.",
        "lipo -create; thin vs fat; when XCFramework replaces fat frameworks",
    )
    pdf.topic(
        "CocoaPods vendored_frameworks + prepare_command",
        "ios/vision_scan.podspec downloads/symlinks vision_scan_native.xcframework at pod install.",
        "CocoaPods podspec DSL; prepare_command; vendored binaries",
    )
    pdf.topic(
        "Swift Package Manager binaryTarget",
        "ios/vision_scan/Package.swift uses URL + SHA256 checksum of the exact zip.",
        "SPM binary targets; swift package compute-checksum; Flutter plugin SPM layout",
    )
    pdf.topic(
        "DynamicLibrary.process() on iOS",
        "No open('lib...') - symbols come from the linked framework in the app process.",
        "dyld; embed frameworks; Flutter ffiPlugin iOS linking",
    )
    pdf.topic(
        "Privacy manifests & system frameworks",
        "PrivacyInfo.xcprivacy + AVFoundation/CoreVideo/CoreMedia/UIKit linker settings.",
        "Apple privacy manifests; Info.plist usage descriptions; camera entitlements",
    )

    pdf.add_page()
    pdf.h2("5. Android-specific research list")
    pdf.topic(
        "ABIs and jniLibs layout",
        "Per-ABI folders under android/src/main/jniLibs or Gradle intermediates.",
        "armeabi-v7a vs arm64-v8a vs x86_64; APK lib/ packing; split APKs / App Bundles",
    )
    pdf.topic(
        "Android NDK + CMake toolchain",
        "scripts/build_android.sh uses android.toolchain.cmake and ANDROID_NDK_HOME.",
        "NDK r26+; ANDROID_ABI; ANDROID_PLATFORM; libc++_shared.so",
    )
    pdf.topic(
        "Shared object dependencies",
        "libvision_scan_native.so needs libopencv_java4.so (and often libc++_shared.so) beside it.",
        "readelf/nm/ldd (or Android llvm-readelf); SONAME; load order",
    )
    pdf.topic(
        "Gradle prepareNativeLibs download pattern",
        "android/build.gradle.kts downloads android-<abi>.zip from GitHub Releases if local jniLibs missing.",
        "Gradle tasks; sourceSets.jniLibs; caching; flutter clean behavior",
    )
    pdf.topic(
        "DynamicLibrary.open on Android",
        "open('libvision_scan_native.so') - name must match add_library(...) output.",
        "System.loadLibrary; JNI_OnLoad (optional); Dart FFI without JNI",
    )

    pdf.h2("6. Windows-specific research list")
    pdf.topic(
        "MSVC / Visual Studio CMake generator",
        "scripts/build_windows.sh uses -G \"Visual Studio 17 2022\" -A x64; runners must pin windows-2022 when VS2022 is required.",
        "CMake generators; vswhere; msvc-dev-cmd; Ninja+MSVC alternative",
    )
    pdf.topic(
        "DLL search path",
        "vision_scan_native.dll + opencv_world*.dll copied next to the Flutter runner exe.",
        "Windows DLL search order; delay-load; dependency walker / dumpbin",
    )
    pdf.topic(
        "Consumer setup CLI",
        "bin/setup_windows.dart downloads windows-x64.zip from releases/latest (or --url).",
        "Dart CLI executables in pubspec; archive extraction; side-by-side deploy",
    )

    pdf.h2("7. Scripting & packaging to research")
    pdf.topic(
        "Bash for build orchestration",
        "scripts/build_ios.sh, build_android.sh, build_windows.sh, update_ios_spm_checksum.sh.",
        "set -euo pipefail; env vars; curl/unzip; path quoting; CI vs local",
    )
    pdf.topic(
        "Deterministic archives",
        "CI touches timestamps and uses zip -X so SPM checksums stay stable across retags.",
        "reproducible builds; zip metadata; SOURCE_DATE_EPOCH",
    )
    pdf.topic(
        "Artifact verification",
        "file / lipo -info / swift package compute-checksum / shasum.",
        "supply-chain integrity; checksums vs signatures",
    )

    pdf.add_page()
    pdf.h2("8. GitHub Actions & CI to research")
    pdf.body(
        "This repo's .github/workflows/native.yml is the living example. Topics:"
    )
    pdf.bullet("Triggers: push tags v*, workflow_dispatch")
    pdf.bullet("Runners: macos-26 (iOS/Xcode), ubuntu-latest (Android/NDK), windows-2022 (MSVC)")
    pdf.bullet("Caching vs downloading large deps (OpenCV zips from scanner-binaries)")
    pdf.bullet("actions/checkout, setup-java, setup-android, ilammy/msvc-dev-cmd")
    pdf.bullet("upload-artifact vs softprops/action-gh-release assets")
    pdf.bullet("Permissions: contents: write for attaching release files")
    pdf.bullet("Xcode platform installs: xcodebuild -downloadPlatform iOS")
    pdf.bullet("Android SDK package drift: obsolete 'tools' package vs platform-tools")
    pdf.bullet("Gates: SPM checksum validation after packaging")
    pdf.bullet("Force-moving tags and why release engineering often needs two passes")
    pdf.ln(2)
    pdf.topic(
        "What to study beyond this repo",
        "Same patterns appear in any binary-shipping Flutter/Rust/C++ plugin.",
        "GitHub Actions docs; OIDC; reusable workflows; matrix builds; caching",
    )

    pdf.h2("9. Dart FFI topics tied to this plugin")
    pdf.bullet("DynamicLibrary.process vs open - see lib/src/ffi/native_bindings.dart")
    pdf.bullet("Struct mirroring of C types (VSFrameResult, VSFinalResult, ...)")
    pdf.bullet("Ownership: who mallocs / who free_qr_string / free_qr_bytes")
    pdf.bullet("Isolates: calling native from a background isolate")
    pdf.bullet("ffiPlugin: true in pubspec.yaml vs MethodChannel plugins")
    pdf.bullet("Smoke tests: ping / opencv / zxing exported symbols")

    pdf.h2("10. vision_scan file map (cheat sheet)")
    pdf.code(
        "native/include/qr_engine.h          C API\n"
        "native/src/native.cpp               shared engine (Android/iOS path)\n"
        "native/android/CMakeLists.txt       Android .so build\n"
        "native/ios/vision_scan_native/      Xcode framework project\n"
        "native/windows/CMakeLists.txt       Windows DLL build\n"
        "scripts/build_{ios,android,windows}.sh\n"
        "ios/vision_scan.podspec             CocoaPods download/vendor\n"
        "ios/vision_scan/Package.swift       SPM binaryTarget\n"
        "android/build.gradle.kts            download .so zips\n"
        "bin/setup_windows.dart              Windows consumer setup\n"
        ".github/workflows/native.yml        CI release pipeline\n"
        "lib/src/ffi/native_bindings.dart    Dart FFI loader"
    )

    pdf.h2("11. Glossary")
    glossary = [
        ("XCFramework", "Apple multi-platform binary bundle (e.g. ios-arm64 + simulator)."),
        ("Framework", "Single-platform Apple package: binary + headers + modules."),
        ("ABI (Android)", "CPU slice folder: arm64-v8a, armeabi-v7a, x86_64."),
        (".so", "ELF shared object - Android dynamic library."),
        (".dll", "Windows dynamic library."),
        (".a", "Static archive linked at build time (e.g. ZXing)."),
        ("NDK", "Android Native Development Kit for cross-compiling C/C++."),
        ("CMake", "Build system generator used on all three platforms."),
        ("CocoaPods", "iOS dep manager; podspec prepare_command vendors XCFramework."),
        ("SPM", "Swift Package Manager; binaryTarget needs URL + checksum."),
        ("Checksum", "SHA-256 of the exact iOS zip SPM will download."),
        ("jniLibs", "Android convention for packaging .so into the APK."),
        ("FFI", "Dart calling C without MethodChannel for the scan path."),
        ("dyld / loader", "OS dynamic linker that maps shared libraries at runtime."),
        ("GitHub Release", "Versioned host for platform zip assets on tag v*."),
    ]
    for term, meaning in glossary:
        pdf.set_font("Helvetica", "B", 9.5)
        pdf.write(5, f"{term}: ")
        pdf.set_font("Helvetica", "", 9.5)
        pdf.multi_cell(0, 5, meaning)

    pdf.add_page()
    pdf.h2("12. Practice projects (when ready)")
    pdf.bullet("Build only ZXing for one Android ABI and inspect the .a/.so with llvm-readelf.")
    pdf.bullet("Create a tiny XCFramework from a hello.c and load it from a sample app.")
    pdf.bullet("Write a Gradle task that downloads a zip and wires jniLibs like prepareNativeLibs.")
    pdf.bullet("Add a GitHub Actions job that publishes a zip on tag and prints its checksum.")
    pdf.bullet("Break SPM on purpose (wrong checksum) and read the Xcode error - then fix it.")
    pdf.bullet("Compare DynamicLibrary.process vs open by logging loaded images (iOS) / maps (Android).")

    pdf.h2("13. Recommended external reading (search terms)")
    pdf.bullet("Apple: Distributing binary frameworks as Swift packages")
    pdf.bullet("Apple: Creating an XCFramework")
    pdf.bullet("Android: Distribute your app native libraries / NDK CMake guides")
    pdf.bullet("Flutter: Bind to native code using FFI / legacy ffiPlugin")
    pdf.bullet("Flutter: Swift Package Manager for plugin authors")
    pdf.bullet("CMake: cmake-toolchains and imported targets")
    pdf.bullet("GitHub Docs: Using workflow run artifacts and releasing binaries")
    pdf.bullet("ELF/DLL: How dynamic loaders resolve dependencies")

    pdf.ln(6)
    pdf.set_font("Helvetica", "I", 10)
    pdf.multi_cell(
        0,
        5.5,
        "Generated for the vision_scan repository. Revisit this guide whenever you change "
        "how binaries are built or published - distribution knowledge is the difference "
        "between \"it works on my machine\" and \"consumers can upgrade to v0.0.9 cleanly.\"",
    )

    pdf.output(OUT)
    print(f"Wrote {OUT}")


if __name__ == "__main__":
    build()
