// BrightnessProcessor.mm
// DZ — Автоматическая адаптационная регулировка яркости видеопотока
//
// Реализация алгоритма обработки кадров:
//   1. Анализ гистограммы яркости (BT.709 luma)
//   2. CLAHE — Contrast Limited Adaptive Histogram Equalization
//   3. Адаптивная гамма-коррекция с нейросетевым взвешиванием признаков
//   4. Временное сглаживание (temporal smoothing) против мерцания
//   5. Цветосохраняющее масштабирование RGB

#import "BrightnessProcessor.h"
#import <Accelerate/Accelerate.h>
#import <mach/mach_time.h>
#include <algorithm>
#include <cmath>
#include <vector>
#include <array>
#include <numeric>
#include <cstring>

// ============================================================================
// MARK: - Вспомогательные C++ функции
// ============================================================================

namespace adaptive {

// ----------------------------------------------------------------------------
// Вычислить гистограмму одноканального буфера
// ----------------------------------------------------------------------------
static void computeHistogram(const uint8_t *data, int width, int height, int stride,
                              int hist[256])
{
    std::memset(hist, 0, 256 * sizeof(int));
    for (int y = 0; y < height; y++) {
        const uint8_t *row = data + y * stride;
        for (int x = 0; x < width; x++) {
            hist[row[x]]++;
        }
    }
}

// ----------------------------------------------------------------------------
// CLAHE: отсечение с перераспределением и построение CDF-LUT для тайла
// ----------------------------------------------------------------------------
static void buildTileLUT(const uint8_t *data, int width, int height,
                          int imgStride, int x0, int y0, int tileW, int tileH,
                          float clipLimitFactor, uint8_t lut[256])
{
    int actualW = std::min(tileW, width  - x0);
    int actualH = std::min(tileH, height - y0);
    int pixCount = actualW * actualH;
    int clipLimit = std::max(1, static_cast<int>(clipLimitFactor * pixCount / 256.0f));

    int hist[256] = {};
    for (int y = y0, ey = y0 + actualH; y < ey; y++) {
        const uint8_t *row = data + y * imgStride + x0;
        for (int x = 0; x < actualW; x++) {
            hist[row[x]]++;
        }
    }

    // Отсечение и равномерное перераспределение избытка
    int excess = 0;
    for (int i = 0; i < 256; i++) {
        if (hist[i] > clipLimit) { excess += hist[i] - clipLimit; hist[i] = clipLimit; }
    }
    int add = excess / 256, rem = excess % 256;
    for (int i = 0; i < 256; i++) {
        hist[i] += add;
        if (i < rem) hist[i]++;
    }

    // Построение CDF → LUT
    int cdf = 0;
    for (int i = 0; i < 256; i++) {
        cdf += hist[i];
        lut[i] = static_cast<uint8_t>(std::min(255, static_cast<int>(
            std::roundf(static_cast<float>(cdf) * 255.0f / pixCount)
        )));
    }
}

// ----------------------------------------------------------------------------
// Применить CLAHE с билинейной интерполяцией LUT соседних тайлов
// ----------------------------------------------------------------------------
static void applyCLAHE(uint8_t *Y, int width, int height, int stride,
                        int gridRows, int gridCols, float clipLimitFactor)
{
    int tileW = (width  + gridCols - 1) / gridCols;
    int tileH = (height + gridRows - 1) / gridRows;

    // LUT[row][col][256]
    std::vector<std::array<uint8_t, 256>> luts(gridRows * gridCols);

    for (int gr = 0; gr < gridRows; gr++) {
        for (int gc = 0; gc < gridCols; gc++) {
            buildTileLUT(Y, width, height, stride,
                         gc * tileW, gr * tileH, tileW, tileH,
                         clipLimitFactor, luts[gr * gridCols + gc].data());
        }
    }

    // Применить с билинейной интерполяцией
    for (int y = 0; y < height; y++) {
        // Координата в пространстве тайлов (центр тайла = 0.5)
        float gy  = (static_cast<float>(y) + 0.5f) / tileH - 0.5f;
        int   gr0 = std::max(0, std::min(gridRows - 1, static_cast<int>(std::floorf(gy))));
        int   gr1 = std::max(0, std::min(gridRows - 1, gr0 + 1));
        float wy  = gy - std::floorf(gy);

        uint8_t *row = Y + y * stride;
        for (int x = 0; x < width; x++) {
            float gx  = (static_cast<float>(x) + 0.5f) / tileW - 0.5f;
            int   gc0 = std::max(0, std::min(gridCols - 1, static_cast<int>(std::floorf(gx))));
            int   gc1 = std::max(0, std::min(gridCols - 1, gc0 + 1));
            float wx  = gx - std::floorf(gx);

            uint8_t v   = row[x];
            float   v00 = luts[gr0 * gridCols + gc0][v];
            float   v01 = luts[gr0 * gridCols + gc1][v];
            float   v10 = luts[gr1 * gridCols + gc0][v];
            float   v11 = luts[gr1 * gridCols + gc1][v];

            float res = v00 * (1.f-wx) * (1.f-wy)
                      + v01 * wx       * (1.f-wy)
                      + v10 * (1.f-wx) * wy
                      + v11 * wx       * wy;

            row[x] = static_cast<uint8_t>(
                std::min(255.f, std::max(0.f, std::roundf(res)))
            );
        }
    }
}

// ----------------------------------------------------------------------------
// Применить гамма-коррекцию через LUT (быстро, O(N) lookup)
// ----------------------------------------------------------------------------
static void applyGammaLUT(uint8_t *data, int count, float gamma)
{
    uint8_t lut[256];
    for (int i = 0; i < 256; i++) {
        float v = std::powf(i / 255.0f, gamma) * 255.0f;
        lut[i] = static_cast<uint8_t>(std::min(255.f, std::max(0.f, v)));
    }
    for (int i = 0; i < count; i++) {
        data[i] = lut[data[i]];
    }
}

// ----------------------------------------------------------------------------
// Нейросетевое взвешивание признаков → адаптивная гамма
//
// Аналог однослойного перцептрона:
//   gamma_raw = f(meanY, darkRatio, brightRatio, contrast, entropy)
//
// Признаки нормированы к [0..1]. Веса подобраны эмпирически по принципу
// минимизации перцептивной ошибки яркости (аналог MSE loss при обучении).
// ----------------------------------------------------------------------------
static float neuralAdaptiveGamma(float meanY, float darkRatio,
                                  float brightRatio, float contrast,
                                  float entropy)
{
    // ------------------------------------------------------------------
    // Нейросетевое взвешивание признаков → адаптивная гамма
    //
    // Диапазон [0.5, 1.8] выбран с учётом того, что камера iPhone
    // с автоэкспозицией уже удерживает normMean ≈ 0.45–0.60.
    // Агрессивная гамма >2.0 приводит к неоправданному затемнению.
    // ------------------------------------------------------------------
    const float targetY = 0.48f;                          // целевая яркость
    const float safeY   = std::max(0.01f,                 // нижняя граница
                          std::min(0.995f, meanY));        // верхняя (log≠0)
    float gammaBase = std::logf(targetY) / std::logf(safeY);

    // Веса признаков (аналог скрытого слоя персептрона)
    const float w_dark    =  0.15f;   // тёмная сцена → чуть осветлить
    const float w_bright  = -0.10f;   // пересвет → чуть затемнить
    const float w_contrast = -0.05f;  // высокий контраст → меньше трогать
    const float w_entropy  =  0.02f;  // богатая сцена → точнее подстроить

    float correction = w_dark * darkRatio
                     + w_bright * brightRatio
                     + w_contrast * contrast
                     + w_entropy * entropy;

    // Ограничение выходного слоя (аналог ReLU + clamp)
    correction = std::max(-0.15f, std::min(0.15f, correction));

    // Итоговая гамма: [0.5, 1.8] — консервативный диапазон
    return std::max(0.5f, std::min(1.8f, gammaBase + correction));
}

// ----------------------------------------------------------------------------
// Вычислить энтропию Шеннона гистограммы
// ----------------------------------------------------------------------------
static float histEntropy(const int hist[256], int totalPixels)
{
    float entropy = 0.0f;
    if (totalPixels <= 0) return 0.f;
    for (int i = 0; i < 256; i++) {
        if (hist[i] > 0) {
            float p = static_cast<float>(hist[i]) / totalPixels;
            entropy -= p * std::log2f(p);
        }
    }
    return entropy / 8.0f;  // нормировать к [0..1] (max=log2(256)=8)
}

} // namespace adaptive

// ============================================================================
// MARK: - FrameMetrics
// ============================================================================

@implementation FrameMetrics
- (instancetype)init {
    if ((self = [super init])) {
        _meanBrightness = 0.5f;
        _darkPixelRatio = 0.f;
        _brightPixelRatio = 0.f;
        _contrast = 0.5f;
        _entropy = 0.5f;
        _lightingType = SceneLightingTypeNormal;
        _adaptiveGamma = 1.0f;
        _processingTimeMs = 0.f;
        _histogram = @[];
    }
    return self;
}
@end

// ============================================================================
// MARK: - BrightnessProcessor
// ============================================================================

@implementation BrightnessProcessor {
    float _prevGamma;   ///< гамма предыдущего кадра для сглаживания
}

- (instancetype)init {
    if ((self = [super init])) {
        _processingEnabled       = YES;
        _claheClipLimit          = 3.0f;
        _claheTileGrid           = 8;
        _temporalSmoothingFactor = 0.75f;
        _prevGamma               = 1.0f;
    }
    return self;
}

- (void)dealloc { }

// ----------------------------------------------------------------------------
// Основной метод: CVPixelBuffer → UIImage + FrameMetrics
// ----------------------------------------------------------------------------
- (nullable UIImage *)processPixelBuffer:(CVPixelBufferRef)pixelBuffer
                                 metrics:(FrameMetrics * _Nullable * _Nullable)metricsOut
{
    if (!pixelBuffer) return nil;

    // -- Засечь время обработки -------------------------------------------
    mach_timebase_info_data_t tbInfo;
    mach_timebase_info(&tbInfo);
    uint64_t t0 = mach_absolute_time();

    CVPixelBufferLockBaseAddress(pixelBuffer, kCVPixelBufferLock_ReadOnly);

    const int width  = (int)CVPixelBufferGetWidth(pixelBuffer);
    const int height = (int)CVPixelBufferGetHeight(pixelBuffer);
    const int stride = (int)CVPixelBufferGetBytesPerRow(pixelBuffer);
    const uint8_t *src = static_cast<const uint8_t *>(
        CVPixelBufferGetBaseAddress(pixelBuffer)
    );

    // -- Выделить рабочий буфер BGRA ----------------------------------------
    const int outStride = width * 4;
    std::vector<uint8_t> buf(height * outStride);

    // Скопировать src → buf (выравниваем stride если нужно)
    if (stride == outStride) {
        std::memcpy(buf.data(), src, height * outStride);
    } else {
        for (int y = 0; y < height; y++) {
            std::memcpy(buf.data() + y * outStride, src + y * stride, outStride);
        }
    }

    CVPixelBufferUnlockBaseAddress(pixelBuffer, kCVPixelBufferLock_ReadOnly);

    // -- Вычислить Y-канал (BT.709 luma) для анализа -----------------------
    // BGRA: pixel[0]=B, pixel[1]=G, pixel[2]=R, pixel[3]=A
    const int N = width * height;
    std::vector<uint8_t> yChannel(N);
    {
        const uint8_t *p = buf.data();
        for (int i = 0; i < N; i++, p += 4) {
            // Y_709 = 0.0722*B + 0.7152*G + 0.2126*R
            yChannel[i] = static_cast<uint8_t>(
                0.0722f * p[0] + 0.7152f * p[1] + 0.2126f * p[2]
            );
        }
    }

    // -- Анализ гистограммы ------------------------------------------------
    int hist[256] = {};
    adaptive::computeHistogram(yChannel.data(), width, height, width, hist);

    float meanY        = 0.f, sumSq = 0.f;
    int   darkCount    = 0, brightCount = 0;
    for (int i = 0; i < 256; i++) {
        float fi = static_cast<float>(i);
        meanY    += fi * hist[i];
        sumSq    += fi * fi * hist[i];
        if (i < 50)  darkCount   += hist[i];
        if (i > 200) brightCount += hist[i];
    }
    meanY /= N;
    float stdDev  = std::sqrtf(std::max(0.f, sumSq / N - meanY * meanY));
    float darkR   = static_cast<float>(darkCount)   / N;
    float brightR = static_cast<float>(brightCount) / N;
    float contrast = stdDev / 128.0f;
    float entropy  = adaptive::histEntropy(hist, N);
    float normMean = meanY / 255.f;

    // -- Классификация освещённости ----------------------------------------
    SceneLightingType lightType;
    if      (normMean < 0.25f)                         lightType = SceneLightingTypeDark;
    else if (normMean > 0.75f && brightR > 0.30f)      lightType = SceneLightingTypeOverexposed;
    else if (normMean > 0.60f)                         lightType = SceneLightingTypeBright;
    else                                               lightType = SceneLightingTypeNormal;

    // -- Нейросетевая адаптивная гамма + сглаживание ----------------------
    float rawGamma = adaptive::neuralAdaptiveGamma(normMean, darkR, brightR, contrast, entropy);
    float alpha    = _temporalSmoothingFactor;
    float gamma    = alpha * _prevGamma + (1.f - alpha) * rawGamma;
    _prevGamma     = gamma;

    // -- Заполнить метрики ------------------------------------------------
    FrameMetrics *metrics = [[FrameMetrics alloc] init];
    metrics.meanBrightness  = normMean;
    metrics.darkPixelRatio  = darkR;
    metrics.brightPixelRatio = brightR;
    metrics.contrast        = contrast;
    metrics.entropy         = entropy;
    metrics.lightingType    = lightType;
    metrics.adaptiveGamma   = gamma;

    NSMutableArray<NSNumber *> *histArr = [NSMutableArray arrayWithCapacity:256];
    float maxH = 1.f;
    for (int i = 0; i < 256; i++) maxH = std::max(maxH, static_cast<float>(hist[i]));
    for (int i = 0; i < 256; i++) {
        [histArr addObject:@(static_cast<float>(hist[i]) / maxH)];
    }
    metrics.histogram = [histArr copy];

    // -- Если обработка выключена — вернуть оригинал ----------------------
    UIImage *result = nil;

    if (!_processingEnabled) {
        result = [self uiImageFromBuf:buf.data() width:width height:height stride:outStride];
    } else {
        // -- CLAHE на Y-канале -------------------------------------------
        int grid = static_cast<int>(_claheTileGrid);
        adaptive::applyCLAHE(yChannel.data(), width, height, width,
                             grid, grid, _claheClipLimit);

        // Применить гамма-LUT к Y
        adaptive::applyGammaLUT(yChannel.data(), N, gamma);

        // -- Восстановить RGB с сохранением цвета -----------------------
        // R' = R * (Y_new / Y_old); аналогично G, B
        uint8_t *p = buf.data();
        for (int i = 0; i < N; i++, p += 4) {
            float oldY = 0.0722f * p[0] + 0.7152f * p[1] + 0.2126f * p[2];
            if (oldY < 1.f) {
                // Для очень тёмных пикселей — просто подтянуть к значению CLAHE
                p[0] = p[1] = p[2] = yChannel[i];
            } else {
                float scale = static_cast<float>(yChannel[i]) / oldY;
                p[0] = static_cast<uint8_t>(std::min(255.f, p[0] * scale));
                p[1] = static_cast<uint8_t>(std::min(255.f, p[1] * scale));
                p[2] = static_cast<uint8_t>(std::min(255.f, p[2] * scale));
            }
        }

        result = [self uiImageFromBuf:buf.data() width:width height:height stride:outStride];
    }

    // -- Время обработки ---------------------------------------------------
    uint64_t dt = mach_absolute_time() - t0;
    metrics.processingTimeMs = static_cast<float>(dt) * tbInfo.numer / tbInfo.denom / 1e6f;
    if (metricsOut) *metricsOut = metrics;

    return result;
}

// ----------------------------------------------------------------------------
// BGRA буфер → UIImage
//
// Используем NSData + CGImageCreate вместо CGBitmapContext:
// NSData делает собственную копию пикселей → каждый UIImage независим
// и не разделяет буфер с другими кадрами (нет COW-конфликтов).
// ----------------------------------------------------------------------------
- (nullable UIImage *)uiImageFromBuf:(const uint8_t *)data
                               width:(int)width
                              height:(int)height
                              stride:(int)stride
{
    // Копируем пиксели в NSData — CGImage владеет этой памятью
    NSData *pixelData = [NSData dataWithBytes:data
                                       length:(NSUInteger)(height * stride)];
    CGDataProviderRef provider =
        CGDataProviderCreateWithCFData((__bridge CFDataRef)pixelData);
    if (!provider) return nil;

    CGColorSpaceRef cs = CGColorSpaceCreateDeviceRGB();
    // BGRA: kCGBitmapByteOrder32Little | kCGImageAlphaNoneSkipFirst
    // (LE-порядок байт → 0xAARRGGBB в памяти = B,G,R,A; Skip alpha = первый компонент)
    CGImageRef cgImg = CGImageCreate(
        (size_t)width, (size_t)height,
        8, 32, (size_t)stride,
        cs,
        kCGBitmapByteOrder32Little | kCGImageAlphaNoneSkipFirst,
        provider,
        NULL, NO,
        kCGRenderingIntentDefault
    );
    CGColorSpaceRelease(cs);
    CGDataProviderRelease(provider);
    if (!cgImg) return nil;

    UIImage *img = [UIImage imageWithCGImage:cgImg
                                       scale:1.0
                                 orientation:UIImageOrientationRight];
    CGImageRelease(cgImg);
    return img;
}

@end
