#define VISION_SCAN_NATIVE_EXPORT __declspec(dllexport)
#include "qr_engine.h"
#include <opencv2/opencv.hpp>
#include <opencv2/imgproc.hpp>
#include <opencv2/imgcodecs.hpp>
#include <ZXing/DecodeHints.h>
#include <ZXing/BarcodeFormat.h>
#include <ZXing/ImageView.h>
#include <ZXing/ReadBarcode.h>
#include <cstdint>
#include <cstdlib>
#include <cstring>
#include <cmath>
#include <vector>
#include <thread>
#include <chrono>

// -----------------------------------------------------------------------------
// Helpers (shared with frame-based API)
// -----------------------------------------------------------------------------
static char* dup_cstr(const std::string& s) {
    if (s.empty()) return nullptr;
    auto* p = (char*)std::malloc(s.size() + 1);
    std::memcpy(p, s.c_str(), s.size() + 1);
    return p;
}

static void fill_corners_from_zxing(const ZXing::Result& res, float outCorners[8]) {
    auto pos = res.position();
    for (int i = 0; i < 8; i++) outCorners[i] = 0.f;
    for (int i = 0; i < 4; i++) {
        outCorners[i * 2 + 0] = static_cast<float>(pos[i].x);
        outCorners[i * 2 + 1] = static_cast<float>(pos[i].y);
    }
}

static std::vector<uint8_t> encode_jpeg(const cv::Mat& img, int quality = 90) {
    std::vector<uint8_t> buf;
    std::vector<int> params = { cv::IMWRITE_JPEG_QUALITY, quality };
    cv::imencode(".jpg", img, buf, params);
    return buf;
}

static cv::Mat warp_crop_qr(const cv::Mat& gray, const float corners[8]) {
    std::vector<cv::Point2f> src(4);
    for (int i = 0; i < 4; i++)
        src[i] = cv::Point2f(corners[i * 2], corners[i * 2 + 1]);
    auto dist = [](const cv::Point2f& a, const cv::Point2f& b) {
        float dx = a.x - b.x, dy = a.y - b.y;
        return std::sqrt(dx * dx + dy * dy);
    };
    float d01 = dist(src[0], src[1]), d12 = dist(src[1], src[2]);
    float d23 = dist(src[2], src[3]), d30 = dist(src[3], src[0]);
    float maxEdge = std::max(std::max(d01, d12), std::max(d23, d30));
    int outSize = (int)std::clamp(maxEdge * 2.0f, 256.0f, 1024.0f);
    std::vector<cv::Point2f> dst = {
        {0.f, 0.f}, {(float)(outSize - 1), 0.f},
        {(float)(outSize - 1), (float)(outSize - 1)}, {0.f, (float)(outSize - 1)}
    };
    cv::Mat M = cv::getPerspectiveTransform(src, dst);
    cv::Mat warped;
    cv::warpPerspective(gray, warped, M, cv::Size(outSize, outSize), cv::INTER_LINEAR);
    return warped;
}

using Position = ZXing::Quadrilateral<ZXing::PointI>;
static float avg_corner_shift(const Position& a, const Position& b) {
    float sum = 0.f;
    for (int i = 0; i < 4; i++) {
        float dx = static_cast<float>(a[i].x) - static_cast<float>(b[i].x);
        float dy = static_cast<float>(a[i].y) - static_cast<float>(b[i].y);
        sum += std::sqrt(dx * dx + dy * dy);
    }
    return sum / 4.f;
}

// -----------------------------------------------------------------------------
// Exported API
// -----------------------------------------------------------------------------
extern "C" {

__declspec(dllexport) int vision_scan_ping() {
    return 42;
}

__declspec(dllexport) int vision_scan_opencv_test() {
    cv::Mat img(10, 10, CV_8UC1, cv::Scalar(128));
    return img.rows * img.cols;
}

__declspec(dllexport) int vision_scan_zxing_test() {
    ZXing::DecodeHints hints;
    hints.setTryHarder(true);
    hints.setFormats(ZXing::BarcodeFormat::QRCode);
    return 1;
}

// ---- Frame-based (same ABI as mobile; used if Dart ever passes a buffer) ----
VISION_SCAN_NATIVE_EXPORT QRResult decode_qr_from_gray(uint8_t* grayData, int width, int height) {
    ZXing::ImageView image(grayData, width, height, ZXing::ImageFormat::Lum);
    ZXing::DecodeHints hints;
    hints.setTryHarder(true);
    hints.setFormats(ZXing::BarcodeFormat::QRCode);
    auto result = ZXing::ReadBarcode(image, hints);
    QRResult out{};
    if (result.isValid()) {
        const std::string& text = result.text();
        char* copy = static_cast<char*>(std::malloc(text.size() + 1));
        std::memcpy(copy, text.c_str(), text.size() + 1);
        out.text = copy;
        out.success = 1;
    } else {
        out.text = nullptr;
        out.success = 0;
    }
    return out;
}

VISION_SCAN_NATIVE_EXPORT VSFrameResult detect_qr_from_gray(const uint8_t* gray, int32_t width, int32_t height) {
    VSFrameResult out{};
    out.detected = 0;
    out.decoded = 0;
    out.text = nullptr;
    for (int i = 0; i < 8; i++) out.corners[i] = 0.f;
    if (!gray || width <= 0 || height <= 0) return out;

    ZXing::ImageView iv(gray, width, height, ZXing::ImageFormat::Lum);
    ZXing::DecodeHints hints;
    hints.setFormats(ZXing::BarcodeFormat::QRCode);
    hints.setTryHarder(true);
    hints.setReturnErrors(true);
    auto res = ZXing::ReadBarcode(iv, hints);
    auto pos = res.position();
    bool hasPos = true;
    for (int i = 0; i < 4; i++) {
        if (pos[i].x == 0 && pos[i].y == 0) { hasPos = false; break; }
    }
    if (!hasPos) return out;
    out.detected = 1;
    fill_corners_from_zxing(res, out.corners);
    if (res.isValid()) {
        auto txt = res.text();
        if (!txt.empty()) { out.decoded = 1; out.text = dup_cstr(txt); }
    }
    return out;
}

VISION_SCAN_NATIVE_EXPORT VSFinalResult capture_qr_from_gray(const uint8_t* gray, int32_t width, int32_t height) {
    VSFinalResult out{};
    out.success = 0;
    out.decoded = 0;
    out.text = nullptr;
    out.cropped_jpeg = nullptr;
    out.cropped_len = 0;
    out.frame_jpeg = nullptr;
    out.frame_len = 0;
    for (int i = 0; i < 8; i++) out.corners[i] = 0.f;
    if (!gray || width <= 0 || height <= 0) return out;

    ZXing::ImageView iv(gray, width, height, ZXing::ImageFormat::Lum);
    ZXing::DecodeHints hints;
    hints.setFormats(ZXing::BarcodeFormat::QRCode);
    hints.setTryHarder(true);
    auto res = ZXing::ReadBarcode(iv, hints);
    if (!res.isValid()) return out;
    out.success = 1;
    fill_corners_from_zxing(res, out.corners);
    auto txt = res.text();
    if (!txt.empty()) { out.decoded = 1; out.text = dup_cstr(txt); }
    cv::Mat grayMat(height, width, CV_8UC1, const_cast<uint8_t*>(gray));
    auto frameJpg = encode_jpeg(grayMat, 90);
    out.frame_len = (int32_t)frameJpg.size();
    if (out.frame_len > 0) {
        out.frame_jpeg = (uint8_t*)std::malloc(out.frame_len);
        std::memcpy(out.frame_jpeg, frameJpg.data(), out.frame_len);
    }
    cv::Mat cropped = warp_crop_qr(grayMat, out.corners);
    auto cropJpg = encode_jpeg(cropped, 90);
    out.cropped_len = (int32_t)cropJpg.size();
    if (out.cropped_len > 0) {
        out.cropped_jpeg = (uint8_t*)std::malloc(out.cropped_len);
        std::memcpy(out.cropped_jpeg, cropJpg.data(), out.cropped_len);
    }
    return out;
}

VISION_SCAN_NATIVE_EXPORT void free_qr_string(char* p) {
    if (p) std::free(p);
}

VISION_SCAN_NATIVE_EXPORT void free_qr_bytes(uint8_t* p) {
    if (p) std::free(p);
}

// ---- Windows-only: open camera, preview, draw box, stabilize, return VSFinalResult ----
VISION_SCAN_NATIVE_EXPORT VSFinalResult capture_qr_from_camera_windows(void) {
    VSFinalResult out{};
    out.success = 0;
    out.decoded = 0;
    out.text = nullptr;
    out.cropped_jpeg = nullptr;
    out.cropped_len = 0;
    out.frame_jpeg = nullptr;
    out.frame_len = 0;
    for (int i = 0; i < 8; i++) out.corners[i] = 0.f;

    cv::VideoCapture cap(0, cv::CAP_MSMF);
    if (!cap.isOpened()) {
        cap.release();
        cap.open(0, cv::CAP_DSHOW);
    }
    if (!cap.isOpened())
        return out;

    cap.set(cv::CAP_PROP_FRAME_WIDTH, 640);
    cap.set(cv::CAP_PROP_FRAME_HEIGHT, 480);

    ZXing::DecodeHints hints;
    hints.setFormats(ZXing::BarcodeFormat::QRCode);
    hints.setTryHarder(true);

    Position prevPos{};
    bool hasPrev = false;
    int stableCount = 0;
    const float shiftThresholdPx = 2.0f;
    const int stableFramesNeeded = 5;

    cv::Mat frame, gray;
    cv::namedWindow("QR Detection", cv::WINDOW_NORMAL);

    while (true) {
        if (!cap.read(frame) || frame.empty()) {
            std::this_thread::sleep_for(std::chrono::milliseconds(30));
            continue;
        }
        cv::cvtColor(frame, gray, cv::COLOR_BGR2GRAY);

        ZXing::ImageView iv(gray.data, gray.cols, gray.rows, ZXing::ImageFormat::Lum);
        auto result = ZXing::ReadBarcode(iv, hints);
        if (!result.isValid()) {
            hasPrev = false;
            stableCount = 0;
            cv::imshow("QR Detection", frame);
            if (cv::waitKey(1) == 27) break;
            continue;
        }

        Position pos = result.position();
        if (hasPrev) {
            float shift = avg_corner_shift(prevPos, pos);
            if (shift < shiftThresholdPx)
                ++stableCount;
            else
                stableCount = 0;
        } else {
            stableCount = 0;
            hasPrev = true;
        }
        prevPos = pos;

        std::vector<cv::Point> poly;
        for (int i = 0; i < 4; i++)
            poly.emplace_back(pos[i].x, pos[i].y);
        cv::polylines(frame, poly, true, cv::Scalar(0, 255, 0), 2);

        cv::imshow("QR Detection", frame);
        if (cv::waitKey(1) == 27) break;

        if (stableCount >= stableFramesNeeded) {
            out.success = 1;
            out.decoded = 1;
            out.text = dup_cstr(result.text());
            fill_corners_from_zxing(result, out.corners);
            std::vector<uint8_t> frameBuf;
            cv::imencode(".jpg", frame, frameBuf, { cv::IMWRITE_JPEG_QUALITY, 90 });
            out.frame_len = (int32_t)frameBuf.size();
            if (out.frame_len > 0) {
                out.frame_jpeg = (uint8_t*)std::malloc(out.frame_len);
                std::memcpy(out.frame_jpeg, frameBuf.data(), out.frame_len);
            }
            cv::Mat cropped = warp_crop_qr(gray, out.corners);
            auto cropJpg = encode_jpeg(cropped, 90);
            out.cropped_len = (int32_t)cropJpg.size();
            if (out.cropped_len > 0) {
                out.cropped_jpeg = (uint8_t*)std::malloc(out.cropped_len);
                std::memcpy(out.cropped_jpeg, cropJpg.data(), out.cropped_len);
            }
            break;
        }
    }

    cap.release();
    cv::destroyAllWindows();
    return out;
}

} // extern "C"
