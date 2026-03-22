#include "qr_engine.h"
#include <cstdint>
#include <opencv2/core.hpp>
#include <opencv2/imgproc.hpp>
#include <opencv2/imgcodecs.hpp>

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

    VSScanResult scan_qr_from_gray(const uint8_t *gray, int32_t width, int32_t height)
    {
        VSScanResult out{};
        out.success = 0;
        out.text = nullptr;
        if (!gray || width <= 0 || height <= 0)
            return out;
        QRResult qr = decode_qr_from_gray(const_cast<uint8_t *>(gray), width, height);
        out.success = qr.success;
        out.text = qr.text;
        return out;
    }

    static char *dup_cstr(const std::string &s)
    {
        if (s.empty())
            return nullptr;
        auto *p = (char *)std::malloc(s.size() + 1);
        std::memcpy(p, s.c_str(), s.size() + 1);
        return p;
    }

    static void fill_corners_from_zxing(const ZXing::Result &res, float outCorners[8])
    {
        auto pos = res.position();

        for (int i = 0; i < 8; i++)
            outCorners[i] = 0.f;

        for (int i = 0; i < 4; i++)
        {
            outCorners[i * 2 + 0] = static_cast<float>(pos[i].x);
            outCorners[i * 2 + 1] = static_cast<float>(pos[i].y);
        }
    }

    static std::vector<uint8_t> encode_jpeg(const cv::Mat &img, int quality = 90)
    {
        std::vector<uint8_t> buf;
        std::vector<int> params = {cv::IMWRITE_JPEG_QUALITY, quality};
        cv::imencode(".jpg", img, buf, params);
        return buf;
    }

    static cv::Mat warp_crop_qr(const cv::Mat &gray, const float corners[8])
    {
        std::vector<cv::Point2f> src(4);
        for (int i = 0; i < 4; i++)
        {
            src[i] = cv::Point2f(corners[i * 2], corners[i * 2 + 1]);
        }

        auto dist = [](const cv::Point2f &a, const cv::Point2f &b)
        {
            float dx = a.x - b.x;
            float dy = a.y - b.y;
            return std::sqrt(dx * dx + dy * dy);
        };

        float d01 = dist(src[0], src[1]);
        float d12 = dist(src[1], src[2]);
        float d23 = dist(src[2], src[3]);
        float d30 = dist(src[3], src[0]);
        float maxEdge = std::max(std::max(d01, d12), std::max(d23, d30));

        // clamp
        int outSize = (int)std::clamp(maxEdge * 2.0f, 256.0f, 1024.0f);

        std::vector<cv::Point2f> dst = {
            {0.f, 0.f},
            {(float)(outSize - 1), 0.f},
            {(float)(outSize - 1), (float)(outSize - 1)},
            {0.f, (float)(outSize - 1)}};

        cv::Mat M = cv::getPerspectiveTransform(src, dst);
        cv::Mat warped;
        cv::warpPerspective(gray, warped, M, cv::Size(outSize, outSize), cv::INTER_LINEAR);
        return warped;
    }

    static bool detect_quad_opencv(const cv::Mat &gray, float outCorners[8])
    {
        cv::Mat blurred;
        cv::GaussianBlur(gray, blurred, cv::Size(5, 5), 0);

        cv::Mat edges;
        cv::Canny(blurred, edges, 50, 150);

        std::vector<std::vector<cv::Point>> contours;
        cv::findContours(edges, contours, cv::RETR_LIST, cv::CHAIN_APPROX_SIMPLE);

        double maxArea = 0.0;
        std::vector<cv::Point> bestQuad;

        for (const auto &contour : contours)
        {
            double area = cv::contourArea(contour);
            if (area < 1000)
                continue;

            std::vector<cv::Point> approx;
            cv::approxPolyDP(contour, approx, 0.04 * cv::arcLength(contour, true), true);

            if (approx.size() == 4 && cv::isContourConvex(approx))
            {
                if (area > maxArea)
                {
                    maxArea = area;
                    bestQuad = approx;
                }
            }
        }

        if (bestQuad.size() != 4)
            return false;

        // Convert to float

        std::vector<cv::Point2f> pts;
        for (int i = 0; i < 4; i++)
            pts.push_back(cv::Point2f(bestQuad[i].x, bestQuad[i].y));

        // order corners (TL, TR, BR, BL)
        std::sort(pts.begin(), pts.end(), [](const cv::Point2f &a, const cv::Point2f &b)
                  { return a.y < b.y; });

        cv::Point2f tl = pts[0].x < pts[1].x ? pts[0] : pts[1];
        cv::Point2f tr = pts[0].x > pts[1].x ? pts[0] : pts[1];
        cv::Point2f bl = pts[2].x < pts[3].x ? pts[2] : pts[3];
        cv::Point2f br = pts[2].x > pts[3].x ? pts[2] : pts[3];

        std::vector<cv::Point2f> ordered = {tl, tr, br, bl};

        for (int i = 0; i < 4; i++)
        {
            outCorners[i * 2 + 0] = ordered[i].x;
            outCorners[i * 2 + 1] = ordered[i].y;
        }

        return true;
    }

    VSFrameResult detect_qr_from_gray(const uint8_t *gray, int32_t width, int32_t height)
    {
        VSFrameResult out{};
        out.detected = 0;
        out.decoded = 0;
        out.text = nullptr;
        for (int i = 0; i < 8; i++)
            out.corners[i] = 0.f;

        if (!gray || width <= 0 || height <= 0)
            return out;

        ZXing::ImageView iv(gray, width, height, ZXing::ImageFormat::Lum);

        ZXing::DecodeHints hints;
        hints.setFormats(ZXing::BarcodeFormat::QRCode);
        hints.setTryHarder(true);

        // 🔥 CRITICAL: return geometry even when decoding fails
        hints.setReturnErrors(true);

        auto res = ZXing::ReadBarcode(iv, hints);

        // ---- DETECTION (corners) ----
        // We consider it "detected" if ZXing gives us a non-zero quad.
        // (ZXing may return errors but still provide position.)
        auto pos = res.position();

        bool hasPos = true;
        for (int i = 0; i < 4; i++)
        {
            if (pos[i].x == 0 && pos[i].y == 0)
            {
                hasPos = false;
                break;
            }
        }

        if (!hasPos)
        {
            return out; // nothing to draw
        }

        out.detected = 1;
        fill_corners_from_zxing(res, out.corners);

        // ---- DECODING (text) ----
        if (res.isValid())
        {
            auto txt = res.text();
            if (!txt.empty())
            {
                out.decoded = 1;
                out.text = dup_cstr(txt);
            }
        }

        return out;
    }

    VSFinalResult capture_qr_from_gray(const uint8_t *gray, int32_t width, int32_t height)
    {
        VSFinalResult out{};
        out.success = 0;
        out.decoded = 0;
        out.text = nullptr;
        out.cropped_jpeg = nullptr;
        out.cropped_len = 0;
        out.frame_jpeg = nullptr;
        out.frame_len = 0;

        for (int i = 0; i < 8; i++)
            out.corners[i] = 0.f;

        if (!gray || width <= 0 || height <= 0)
            return out;

        ZXing::ImageView iv(gray, width, height, ZXing::ImageFormat::Lum);

        ZXing::DecodeHints hints;
        hints.setFormats(ZXing::BarcodeFormat::QRCode);
        hints.setTryHarder(true);

        auto res = ZXing::ReadBarcode(iv, hints);
        if (!res.isValid())
            return out;

        out.success = 1;
        fill_corners_from_zxing(res, out.corners);

        auto txt = res.text();
        if (!txt.empty())
        {
            out.decoded = 1;
            out.text = dup_cstr(txt);
        }

        cv::Mat grayMat(height, width, CV_8UC1, const_cast<uint8_t *>(gray));

        auto frameJpg = encode_jpeg(grayMat, 90);
        out.frame_len = (int32_t)frameJpg.size();
        if (out.frame_len > 0)
        {
            out.frame_jpeg = (uint8_t *)std::malloc(out.frame_len);
            std::memcpy(out.frame_jpeg, frameJpg.data(), out.frame_len);
        }

        cv::Mat cropped = warp_crop_qr(grayMat, out.corners);
        auto cropJpg = encode_jpeg(cropped, 90);
        out.cropped_len = (int32_t)cropJpg.size();
        if (out.cropped_len > 0)
        {
            out.cropped_jpeg = (uint8_t *)std::malloc(out.cropped_len);
            std::memcpy(out.cropped_jpeg, cropJpg.data(), out.cropped_len);
        }
        return out;
    }

    void free_qr_string(char *p)
    {
        if (p)
            std::free(p);
    }

    void free_qr_bytes(uint8_t *p)
    {
        if (p)
            std::free(p);
    }

#ifdef __cplusplus
}
#endif