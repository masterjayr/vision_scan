#pragma once

#include <stdint.h>

#ifdef __cplusplus
extern "C"
{
#endif

    typedef struct QRResult
    {
        char *text;
        int success;
    } QRResult;
    // Returns a newly-allocated UTF-8 string (null-terminated) with the decoded QR text,
    // or nullptr if not found.
    // Caller MUST free the returned string using free_qr_string().
    QRResult decode_qr_gray(
        uint8_t *grayData,
        int width,
        int height);

    // Frees a string returned by decode_qr_gray().
    void free_qr_string(const char *p);

#ifdef __cplusplus
} // extern "C"
#endif
