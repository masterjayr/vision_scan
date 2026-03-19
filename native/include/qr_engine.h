#pragma once

#include <stdint.h>

#if defined(_WIN32) && !defined(VISION_SCAN_NATIVE_EXPORT)
#define VISION_SCAN_NATIVE_EXPORT __declspec(dllimport)
#elif defined(_WIN32)
#define VISION_SCAN_NATIVE_EXPORT __declspec(dllexport)
#else
#define VISION_SCAN_NATIVE_EXPORT
#endif

#ifdef __cplusplus
extern "C"
{
#endif

    typedef struct
    {
        int32_t detected;
        int32_t decoded;
        float corners[8];
        char *text;

    } VSFrameResult;

    typedef struct
    {
        int32_t success;
        int32_t decoded;
        float corners[8];

        char *text;

        uint8_t *cropped_jpeg;
        int32_t cropped_len;

        uint8_t *frame_jpeg;
        int32_t frame_len;
    } VSFinalResult;

    typedef struct QRResult
    {
        char *text;
        int success;
    } QRResult;
    // Returns a newly-allocated UTF-8 string (null-terminated) with the decoded QR text,
    // or nullptr if not found.
    // Caller MUST free the returned string using free_qr_string().
    VISION_SCAN_NATIVE_EXPORT QRResult decode_qr_gray(
        uint8_t *grayData,
        int width,
        int height);

    VISION_SCAN_NATIVE_EXPORT VSFrameResult detect_qr_from_gray(const uint8_t *gray, int32_t width, int32_t height);

    VISION_SCAN_NATIVE_EXPORT VSFinalResult capture_qr_from_gray(const uint8_t *gray, int32_t width, int32_t height);

    // Frees a string returned by decode_qr_gray().
    VISION_SCAN_NATIVE_EXPORT void free_qr_string(char *p);
    VISION_SCAN_NATIVE_EXPORT void free_qr_bytes(uint8_t *p);

#ifdef _WIN32
    // Windows-only: opens camera, preview, draw box, stabilize; returns VSFinalResult.
    VISION_SCAN_NATIVE_EXPORT VSFinalResult capture_qr_from_camera_windows(void);
#endif

#ifdef __cplusplus
} // extern "C"
#endif