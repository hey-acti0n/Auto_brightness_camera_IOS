// BrightnessMetrics.swift
// DZ — Swift-обёртка над FrameMetrics из Objective-C++

import SwiftUI

// ---------------------------------------------------------------------------
// MARK: - SceneLightingType расширение
// ---------------------------------------------------------------------------
extension SceneLightingType {
    var title: String {
        switch self {
        case .dark:        return "Тёмная сцена"
        case .normal:      return "Нормальное освещение"
        case .bright:      return "Яркая сцена"
        case .overexposed: return "Переэкспонирование"
        @unknown default:  return "Неизвестно"
        }
    }

    var icon: String {
        switch self {
        case .dark:        return "moon.fill"
        case .normal:      return "sun.min.fill"
        case .bright:      return "sun.max.fill"
        case .overexposed: return "sun.max.trianglebadge.exclamationmark"
        @unknown default:  return "questionmark"
        }
    }

    var accentColor: Color {
        switch self {
        case .dark:        return Color(red: 0.33, green: 0.55, blue: 1.0)
        case .normal:      return Color(red: 0.28, green: 0.85, blue: 0.47)
        case .bright:      return Color(red: 1.0,  green: 0.78, blue: 0.1)
        case .overexposed: return Color(red: 1.0,  green: 0.33, blue: 0.27)
        @unknown default:  return .white
        }
    }
}

// ---------------------------------------------------------------------------
// MARK: - Swift-значение метрик кадра
// ---------------------------------------------------------------------------
struct BrightnessMetrics: Sendable {
    var meanBrightness:   Float = 0.5
    var darkPixelRatio:   Float = 0.0
    var brightPixelRatio: Float = 0.0
    var contrast:         Float = 0.5
    var entropy:          Float = 0.5
    var lightingType:     SceneLightingType = .normal
    var adaptiveGamma:    Float = 1.0
    var processingTimeMs: Float = 0.0
    var histogram:        [Float] = Array(repeating: 0, count: 256)

    init() {}

    /// Инициализация из ObjC-объекта
    init(from objc: FrameMetrics) {
        meanBrightness   = objc.meanBrightness
        darkPixelRatio   = objc.darkPixelRatio
        brightPixelRatio = objc.brightPixelRatio
        contrast         = objc.contrast
        entropy          = objc.entropy
        lightingType     = objc.lightingType
        adaptiveGamma    = objc.adaptiveGamma
        processingTimeMs = objc.processingTimeMs
        histogram        = objc.histogram.map { $0.floatValue }
    }

    /// Текстовое значение гаммы
    var gammaString: String { String(format: "%.2f", adaptiveGamma) }
    /// Средняя яркость в процентах
    var brightnessPercent: Int { Int((meanBrightness * 100).rounded()) }
    /// Контраст в процентах
    var contrastPercent: Int { Int((contrast * 100).rounded()) }
    /// FPS-эквивалент (только для индикации, не реальный FPS камеры)
    var estimatedFps: Float {
        processingTimeMs > 0 ? 1000.0 / processingTimeMs : 0
    }
}
