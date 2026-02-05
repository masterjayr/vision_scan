cmake_minimum_required(VERSION 3.10)

# 🔁 Project name
project(vision_scan_native)

set(CMAKE_CXX_STANDARD 17)
set(CMAKE_CXX_STANDARD_REQUIRED ON)
set(CMAKE_POSITION_INDEPENDENT_CODE ON)

# 🔁 Native shared library name
add_library(
    vision_scan_native
    SHARED
    ${CMAKE_CURRENT_SOURCE_DIR}/../src/native.cpp
)

target_include_directories(
    vision_scan_native
    PRIVATE
    ${CMAKE_CURRENT_SOURCE_DIR}/../include
)

# ----------------------------
# OpenCV (shared)
# ----------------------------
add_library(opencv_java4 SHARED IMPORTED)
set_target_properties(opencv_java4 PROPERTIES
    IMPORTED_LOCATION
    ${CMAKE_CURRENT_SOURCE_DIR}/${ANDROID_ABI}/libopencv_java4.so
)

# ----------------------------
# ZXing (static)
# ----------------------------
add_library(zxing STATIC IMPORTED)
set_target_properties(zxing PROPERTIES
    IMPORTED_LOCATION
    ${CMAKE_CURRENT_SOURCE_DIR}/${ANDROID_ABI}/libZXing.a
)

# ----------------------------
# Link everything
# ----------------------------
target_link_libraries(
    vision_scan_native
    opencv_java4
    zxing
)