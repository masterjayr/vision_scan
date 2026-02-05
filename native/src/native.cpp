#include "qr_engine.h"
#include <cstdint>
#include <opencv2/core.hpp>
#include <opencv2/imgproc.hpp>
#include <cstdlib> // malloc/free
#include <cstring>
#include "ZXing/ImageView.h"
#include "ZXing/ReadBarcode.h"

#ifdef __cplusplus
extern "C"
{
#endif

    QRResult decode_qr_from_gray(
        uint8_t *grayData,
        int width,
        int height)
    {
        ZXing::ImageView image(
            grayData,
            width,
            height,
            ZXing::ImageFormat::Lum);

        ZXing::DecodeHints hints;
        hints.setTryHarder(true);
        hints.setFormats(ZXing::BarcodeFormat::QRCode);

        auto result = ZXing::ReadBarcode(image, hints);

        QRResult out{};

        if (result.isValid())
        {
            const std::string &text = result.text();
            char *copy = static_cast<char *>(std::malloc(text.size() + 1));
            std::memcpy(copy, text.c_str(), text.size() + 1);

            out.text = copy;
            out.success = 1;
        }
        else
        {
            out.text = nullptr;
            out.success = 0;
        }

        return out;
    }

    void free_qr_string(char *p)
    {
        std::free(p);
    }
#ifdef __cplusplus
}
#endif