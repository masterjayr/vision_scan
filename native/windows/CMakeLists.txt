cmake_minimum_required(VERSION 3.15)
project(vision_scan_native)

set(CMAKE_CXX_STANDARD 17)
set(CMAKE_CXX_STANDARD_REQUIRED ON)

add_library(vision_scan_native SHARED vision_scan_windows.cpp)

target_include_directories(vision_scan_native
    PRIVATE
        ${CMAKE_CURRENT_SOURCE_DIR}/../include                 # qr_engine.h
        ${CMAKE_CURRENT_SOURCE_DIR}/libs/opencv/include        # opencv2/...
        ${CMAKE_CURRENT_SOURCE_DIR}/libs/zxing/include         # ZXing/...
)

target_link_directories(vision_scan_native
    PRIVATE
        ${CMAKE_CURRENT_SOURCE_DIR}/libs/opencv/lib
        ${CMAKE_CURRENT_SOURCE_DIR}/libs/zxing/lib
)

target_link_libraries(vision_scan_native
    PRIVATE
        opencv_world4120     # matches opencv_world4120.lib
        ZXing                # matches ZXing.lib (name without .lib)
)