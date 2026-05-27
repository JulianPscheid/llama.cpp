#!/bin/bash
# Build llama.cpp as XCFramework for Hedy (iOS + macOS)
# Mirrors whisper.cpp/build-xcframework.sh pattern
set -e

IOS_MIN_OS_VERSION=16.4
MACOS_MIN_OS_VERSION=13.3

BUILD_SHARED_LIBS=OFF
LLAMA_BUILD_COMMON=OFF
LLAMA_BUILD_EXAMPLES=OFF
LLAMA_BUILD_TESTS=OFF
LLAMA_BUILD_SERVER=OFF
# AIDEV-NOTE: app/ is the upstream unified binary (b9360+). Unlike tools/examples
# it is NOT gated behind LLAMA_BUILD_COMMON, so it builds even with COMMON=OFF and
# pulls in app/llama.cpp which needs a generated build-info.h we don't produce in
# the framework-only build. We only ship the llama library, so disable it.
LLAMA_BUILD_APP=OFF
GGML_METAL=ON
GGML_METAL_EMBED_LIBRARY=ON
GGML_BLAS_DEFAULT=ON
GGML_METAL_USE_BF16=ON
GGML_OPENMP=OFF

COMMON_C_FLAGS="-Wno-macro-redefined -Wno-shorten-64-to-32 -Wno-unused-command-line-argument -g"
COMMON_CXX_FLAGS="-Wno-macro-redefined -Wno-shorten-64-to-32 -Wno-unused-command-line-argument -g"

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
cd "$SCRIPT_DIR"

# AIDEV-NOTE: llama-bindings-injection; pass path so fork's CMakeLists.txt compiles our bindings
BINDINGS_SRC="${SCRIPT_DIR}/../llama_bindings.cpp"

COMMON_CMAKE_ARGS=(
    -DCMAKE_XCODE_ATTRIBUTE_CODE_SIGNING_REQUIRED=NO
    -DCMAKE_XCODE_ATTRIBUTE_CODE_SIGN_IDENTITY=""
    -DCMAKE_XCODE_ATTRIBUTE_CODE_SIGNING_ALLOWED=NO
    -DCMAKE_XCODE_ATTRIBUTE_DEBUG_INFORMATION_FORMAT="dwarf-with-dsym"
    -DCMAKE_XCODE_ATTRIBUTE_GCC_GENERATE_DEBUGGING_SYMBOLS=YES
    -DCMAKE_XCODE_ATTRIBUTE_COPY_PHASE_STRIP=NO
    -DBUILD_SHARED_LIBS=${BUILD_SHARED_LIBS}
    -DLLAMA_BUILD_COMMON=${LLAMA_BUILD_COMMON}
    -DLLAMA_BUILD_EXAMPLES=${LLAMA_BUILD_EXAMPLES}
    -DLLAMA_BUILD_TESTS=${LLAMA_BUILD_TESTS}
    -DLLAMA_BUILD_SERVER=${LLAMA_BUILD_SERVER}
    -DLLAMA_BUILD_APP=${LLAMA_BUILD_APP}
    -DGGML_METAL=${GGML_METAL}
    -DGGML_METAL_EMBED_LIBRARY=${GGML_METAL_EMBED_LIBRARY}
    -DGGML_BLAS_DEFAULT=${GGML_BLAS_DEFAULT}
    -DGGML_METAL_USE_BF16=${GGML_METAL_USE_BF16}
    -DGGML_OPENMP=${GGML_OPENMP}
    -DGGML_NATIVE=OFF
    -DHEDY_LLAMA_BINDINGS_SRC=${BINDINGS_SRC}
)

# Clean previous builds
rm -rf build-ios-sim build-ios-device build-macos build-apple

# ── Helper functions ──────────────────────────────────────────────

setup_framework_structure() {
    local build_dir=$1
    local min_version=$2
    local platform=$3

    local framework_dir="${build_dir}/framework/llama.framework"

    # Map platform to Apple SDK platform name for Info.plist
    local platform_name
    case "$platform" in
        macos) platform_name="MacOSX" ;;
        ios)   platform_name="iPhoneOS" ;;
        *)     platform_name="MacOSX" ;;
    esac

    if [[ "$platform" == "macos" ]]; then
        mkdir -p "${framework_dir}/Versions/A/Headers"
        mkdir -p "${framework_dir}/Versions/A/Resources"
        mkdir -p "${framework_dir}/Versions/A/Modules"

        # Symlinks
        ln -sf A "${framework_dir}/Versions/Current"
        ln -sf Versions/Current/Headers "${framework_dir}/Headers"
        ln -sf Versions/Current/Resources "${framework_dir}/Resources"
        ln -sf Versions/Current/Modules "${framework_dir}/Modules"
        ln -sf Versions/Current/llama "${framework_dir}/llama"

        local header_path="${framework_dir}/Versions/A/Headers/"
        local module_path="${framework_dir}/Versions/A/Modules/"
        local plist_path="${framework_dir}/Versions/A/Resources/Info.plist"
    else
        mkdir -p "${framework_dir}/Headers"
        mkdir -p "${framework_dir}/Modules"

        local header_path="${framework_dir}/Headers/"
        local module_path="${framework_dir}/Modules/"
        local plist_path="${framework_dir}/Info.plist"
    fi

    # Copy headers
    cp include/llama.h "${header_path}"
    cp ggml/include/ggml.h "${header_path}"
    cp ggml/include/ggml-alloc.h "${header_path}"
    cp ggml/include/ggml-backend.h "${header_path}"
    cp ggml/include/ggml-metal.h "${header_path}"
    cp ggml/include/ggml-cpu.h "${header_path}"
    cp ggml/include/ggml-blas.h "${header_path}"
    cp ggml/include/gguf.h "${header_path}"

    # Module map
    cat > "${module_path}module.modulemap" << MODULEMAP
framework module llama {
    header "llama.h"
    header "ggml.h"
    header "ggml-alloc.h"
    header "ggml-backend.h"
    header "ggml-metal.h"
    header "ggml-cpu.h"
    header "ggml-blas.h"
    header "gguf.h"

    link "c++"
    link framework "Accelerate"
    link framework "Metal"
    link framework "Foundation"

    export *
}
MODULEMAP

    # Info.plist (must match whisper.framework format for Xcode code-sign-on-copy)
    cat > "${plist_path}" << PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleDevelopmentRegion</key>
    <string>en</string>
    <key>CFBundleExecutable</key>
    <string>llama</string>
    <key>CFBundleIdentifier</key>
    <string>ai.hedy.llama</string>
    <key>CFBundleInfoDictionaryVersion</key>
    <string>6.0</string>
    <key>CFBundleName</key>
    <string>llama</string>
    <key>CFBundlePackageType</key>
    <string>FMWK</string>
    <key>CFBundleShortVersionString</key>
    <string>1.0</string>
    <key>CFBundleSupportedPlatforms</key>
    <array>
        <string>${platform_name}</string>
    </array>
    <key>CFBundleVersion</key>
    <string>1</string>
    <key>MinimumOSVersion</key>
    <string>${min_version}</string>
</dict>
</plist>
PLIST
}

combine_static_libraries() {
    local build_dir=$1
    local config_dir=$2
    local platform=$3
    local is_simulator=$4

    local framework_dir="${build_dir}/framework/llama.framework"

    # Find all static libraries in build_dir matching the config (e.g. Release-iphonesimulator)
    # Xcode puts them in various subdirs: src/, ggml/src/, ggml/src/ggml-metal/, etc.
    local libs=()
    while IFS= read -r lib; do
        libs+=("$lib")
    done < <(find "${build_dir}" -path "*/${config_dir}/lib*.a" -not -path "*/Objects-normal/*" -type f 2>/dev/null | sort -u)

    if [ ${#libs[@]} -eq 0 ]; then
        echo "ERROR: No static libraries found in ${lib_dir}"
        exit 1
    fi

    echo "Combining ${#libs[@]} libraries for ${platform}:"
    printf "  %s\n" "${libs[@]}"

    # Combine into single static archive
    local combined_lib="${build_dir}/libllama_combined.a"
    libtool -static -o "${combined_lib}" "${libs[@]}"

    # Create dynamic library from combined static
    if [ "$platform" = "macos" ]; then
        local install_name="@rpath/llama.framework/Versions/Current/llama"
        local binary_path="${framework_dir}/Versions/A/llama"
    else
        local install_name="@rpath/llama.framework/llama"
        local binary_path="${framework_dir}/llama"
    fi

    local dylib_flags=(-dynamiclib -install_name "${install_name}")
    if [ "$platform" = "ios" ]; then
        if [ "$is_simulator" = "true" ]; then
            dylib_flags+=(-isysroot "$(xcrun --sdk iphonesimulator --show-sdk-path)")
            dylib_flags+=(-target arm64-apple-ios${IOS_MIN_OS_VERSION}-simulator)
        else
            dylib_flags+=(-isysroot "$(xcrun --sdk iphoneos --show-sdk-path)")
            dylib_flags+=(-target arm64-apple-ios${IOS_MIN_OS_VERSION})
        fi
    elif [ "$platform" = "macos" ]; then
        dylib_flags+=(-target arm64-apple-macos${MACOS_MIN_OS_VERSION})
    fi

    dylib_flags+=(-framework Metal -framework Foundation -framework Accelerate)

    xcrun clang++ "${dylib_flags[@]}" \
        -Wl,-force_load,"${combined_lib}" \
        -o "${binary_path}"

    echo "Created dynamic library for ${platform}"

    # Generate dSYM
    mkdir -p "${build_dir}/dSYMs"
    dsymutil "${binary_path}" \
        -o "${build_dir}/dSYMs/llama.dSYM"
}

# ── Build platforms ───────────────────────────────────────────────

echo "Building llama.cpp for iOS simulator..."
cmake -B build-ios-sim -G Xcode \
    "${COMMON_CMAKE_ARGS[@]}" \
    -DCMAKE_OSX_DEPLOYMENT_TARGET=${IOS_MIN_OS_VERSION} \
    -DCMAKE_SYSTEM_NAME=iOS \
    -DCMAKE_OSX_SYSROOT=iphonesimulator \
    -DCMAKE_OSX_ARCHITECTURES="arm64;x86_64" \
    -DCMAKE_C_FLAGS="${COMMON_C_FLAGS}" \
    -DCMAKE_CXX_FLAGS="${COMMON_CXX_FLAGS}" \
    -S .
cmake --build build-ios-sim --config Release -- -quiet

echo "Building llama.cpp for iOS devices..."
cmake -B build-ios-device -G Xcode \
    "${COMMON_CMAKE_ARGS[@]}" \
    -DCMAKE_OSX_DEPLOYMENT_TARGET=${IOS_MIN_OS_VERSION} \
    -DCMAKE_SYSTEM_NAME=iOS \
    -DCMAKE_OSX_SYSROOT=iphoneos \
    -DCMAKE_OSX_ARCHITECTURES="arm64" \
    -DCMAKE_C_FLAGS="${COMMON_C_FLAGS}" \
    -DCMAKE_CXX_FLAGS="${COMMON_CXX_FLAGS}" \
    -S .
cmake --build build-ios-device --config Release -- -quiet

echo "Building llama.cpp for macOS..."
cmake -B build-macos -G Xcode \
    "${COMMON_CMAKE_ARGS[@]}" \
    -DCMAKE_OSX_DEPLOYMENT_TARGET=${MACOS_MIN_OS_VERSION} \
    -DCMAKE_OSX_ARCHITECTURES="arm64;x86_64" \
    -DCMAKE_C_FLAGS="${COMMON_C_FLAGS}" \
    -DCMAKE_CXX_FLAGS="${COMMON_CXX_FLAGS}" \
    -S .
cmake --build build-macos --config Release -- -quiet

# ── Package frameworks ────────────────────────────────────────────

echo "Setting up framework structures..."
setup_framework_structure "build-ios-sim" ${IOS_MIN_OS_VERSION} "ios"
setup_framework_structure "build-ios-device" ${IOS_MIN_OS_VERSION} "ios"
setup_framework_structure "build-macos" ${MACOS_MIN_OS_VERSION} "macos"

echo "Creating dynamic libraries from static libraries..."
combine_static_libraries "build-ios-sim" "Release-iphonesimulator" "ios" "true"
combine_static_libraries "build-ios-device" "Release-iphoneos" "ios" "false"
combine_static_libraries "build-macos" "Release" "macos" "false"

echo "Creating XCFramework..."
xcodebuild -create-xcframework \
    -framework $(pwd)/build-ios-sim/framework/llama.framework \
    -debug-symbols $(pwd)/build-ios-sim/dSYMs/llama.dSYM \
    -framework $(pwd)/build-ios-device/framework/llama.framework \
    -debug-symbols $(pwd)/build-ios-device/dSYMs/llama.dSYM \
    -framework $(pwd)/build-macos/framework/llama.framework \
    -debug-symbols $(pwd)/build-macos/dSYMs/llama.dSYM \
    -output $(pwd)/build-apple/llama.xcframework

echo "Done! XCFramework at: $(pwd)/build-apple/llama.xcframework"
