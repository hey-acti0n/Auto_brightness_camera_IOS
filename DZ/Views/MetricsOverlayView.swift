// MetricsOverlayView.swift
// DZ — Панель метрик яркости и гистограммы

import SwiftUI

// ---------------------------------------------------------------------------
// MARK: - Полоска метрики
// ---------------------------------------------------------------------------
private struct MetricBarRow: View {
    let label: String
    let value: Float
    let color: Color
    let text:  String

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack {
                Text(label)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.white.opacity(0.7))
                Spacer()
                Text(text)
                    .font(.system(size: 11, weight: .semibold, design: .monospaced))
                    .foregroundStyle(.white)
            }
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 2)
                        .fill(.white.opacity(0.15))
                        .frame(height: 5)
                    RoundedRectangle(cornerRadius: 2)
                        .fill(color)
                        .frame(width: geo.size.width * CGFloat(max(0, min(1, value))), height: 5)
                }
            }
            .frame(height: 5)
        }
    }
}

// ---------------------------------------------------------------------------
// MARK: - Мини-гистограмма
// ---------------------------------------------------------------------------
private struct HistogramView: View {
    let bins: [Float]

    var body: some View {
        GeometryReader { geo in
            let count = bins.count
            guard count > 0 else { return AnyView(EmptyView()) }
            let barW = geo.size.width / CGFloat(count)
            return AnyView(
                Canvas { ctx, size in
                    for i in 0..<count {
                        let h   = CGFloat(bins[i]) * size.height
                        let rect = CGRect(
                            x: CGFloat(i) * barW,
                            y: size.height - h,
                            width: max(1, barW - 0.5),
                            height: h
                        )
                        let hue   = Double(i) / 510.0
                        let color = Color(hue: hue, saturation: 0.8, brightness: 0.9)
                        ctx.fill(Path(rect), with: .color(color.opacity(0.85)))
                    }
                }
            )
        }
    }
}

// ---------------------------------------------------------------------------
// MARK: - MetricsOverlayView
// Просто контентная полоса — родитель (safeAreaInset) управляет позицией.
// ---------------------------------------------------------------------------
struct MetricsOverlayView: View {
    let metrics:       BrightnessMetrics
    let showHistogram: Bool

    private var accent: Color { metrics.lightingType.accentColor }

    var body: some View {
        VStack(spacing: 8) {
            // ── Строка 1: иконка + тип + гамма + время ──────────────────────
            HStack(spacing: 8) {
                Image(systemName: metrics.lightingType.icon)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(accent)
                Text(metrics.lightingType.title)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.white)
                Spacer()
                Text("γ=\(metrics.gammaString)")
                    .font(.system(size: 12, weight: .bold, design: .monospaced))
                    .foregroundStyle(accent)
                if metrics.processingTimeMs > 0 {
                    Text(String(format: "%.0fms", metrics.processingTimeMs))
                        .font(.system(size: 10))
                        .foregroundStyle(.white.opacity(0.45))
                }
            }

            // ── Строка 2: метрики в 2 колонки ───────────────────────────────
            HStack(spacing: 12) {
                VStack(spacing: 6) {
                    MetricBarRow(label: "Яркость",
                                 value: metrics.meanBrightness, color: accent,
                                 text: "\(metrics.brightnessPercent)%")
                    MetricBarRow(label: "Контраст",
                                 value: metrics.contrast, color: .cyan,
                                 text: "\(metrics.contrastPercent)%")
                }
                VStack(spacing: 6) {
                    MetricBarRow(label: "Тёмных px",
                                 value: metrics.darkPixelRatio,
                                 color: Color(red: 0.4, green: 0.6, blue: 1.0),
                                 text: String(format: "%.0f%%", metrics.darkPixelRatio * 100))
                    MetricBarRow(label: "Пересвет px",
                                 value: metrics.brightPixelRatio,
                                 color: Color(red: 1.0, green: 0.65, blue: 0.2),
                                 text: String(format: "%.0f%%", metrics.brightPixelRatio * 100))
                }
            }

            // ── Строка 3: гистограмма (опционально) ─────────────────────────
            if showHistogram && !metrics.histogram.isEmpty {
                HistogramView(bins: metrics.histogram)
                    .frame(height: 36)
                    .clipShape(RoundedRectangle(cornerRadius: 4))
                    .overlay(
                        RoundedRectangle(cornerRadius: 4)
                            .stroke(.white.opacity(0.1), lineWidth: 0.5)
                    )
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 10)
        .padding(.bottom, 12)
        .background {
            Rectangle()
                .fill(.ultraThinMaterial)
                .ignoresSafeArea(edges: .bottom)
                .environment(\.colorScheme, .dark)
        }
    }
}

// ---------------------------------------------------------------------------
#Preview {
    ZStack {
        Color.black.ignoresSafeArea()
        VStack {
            Spacer()
            MetricsOverlayView(metrics: BrightnessMetrics(), showHistogram: true)
        }
    }
}
