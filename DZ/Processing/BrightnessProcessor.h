// BrightnessProcessor.h
// DZ — Автоматическая адаптационная регулировка яркости кадров видеопотока

#pragma once

#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
#import <CoreVideo/CoreVideo.h>

// NS_ASSUME_NONNULL_BEGIN/END говорит Swift-компилятору, что все
// указатели без явной пометки — ненулевые (non-optional).
NS_ASSUME_NONNULL_BEGIN

// ---------------------------------------------------------------------------
// Тип сцены по уровню освещённости
// ---------------------------------------------------------------------------
typedef NS_ENUM(NSInteger, SceneLightingType) {
    SceneLightingTypeDark        = 0,
    SceneLightingTypeNormal      = 1,
    SceneLightingTypeBright      = 2,
    SceneLightingTypeOverexposed = 3
} NS_SWIFT_NAME(SceneLightingType);

// ---------------------------------------------------------------------------
// Метрики одного обработанного кадра
// ---------------------------------------------------------------------------
NS_SWIFT_NAME(FrameMetrics)
@interface FrameMetrics : NSObject

@property (nonatomic) float meanBrightness;
@property (nonatomic) float darkPixelRatio;
@property (nonatomic) float brightPixelRatio;
@property (nonatomic) float contrast;
@property (nonatomic) float entropy;
@property (nonatomic) SceneLightingType lightingType;
@property (nonatomic) float adaptiveGamma;
@property (nonatomic) float processingTimeMs;
@property (nonatomic, strong) NSArray<NSNumber *> *histogram;

@end

// ---------------------------------------------------------------------------
// Основной обработчик кадров
// ---------------------------------------------------------------------------
NS_SWIFT_NAME(BrightnessProcessor)
@interface BrightnessProcessor : NSObject

/// Включить / выключить адаптивную обработку (по умолч. YES)
@property (nonatomic) BOOL processingEnabled;

/// Предел отсечения гистограммы CLAHE (по умолч. 3.0; диапазон 1..10)
@property (nonatomic) float claheClipLimit;

/// Размер сетки тайлов CLAHE N×N (по умолч. 8; допустимо 4..16)
@property (nonatomic) NSInteger claheTileGrid;

/// Коэффициент временного сглаживания гаммы (0..1; по умолч. 0.75)
@property (nonatomic) float temporalSmoothingFactor;

- (instancetype)init NS_DESIGNATED_INITIALIZER;

/**
 Обрабатывает кадр из CVPixelBuffer (формат BGRA).
 @param pixelBuffer  Входной буфер из AVFoundation.
 @param metricsOut   Указатель для возврата метрик (может быть nil).
 @return             Обработанное изображение или nil при ошибке.
 */
- (nullable UIImage *)processPixelBuffer:(CVPixelBufferRef)pixelBuffer
                                 metrics:(FrameMetrics * _Nullable * _Nullable)metricsOut
    NS_SWIFT_NAME(process(pixelBuffer:metrics:));

@end

NS_ASSUME_NONNULL_END
