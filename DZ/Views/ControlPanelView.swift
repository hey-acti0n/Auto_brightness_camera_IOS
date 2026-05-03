// ControlPanelView.swift
// DZ — Панель управления параметрами алгоритма

import SwiftUI

// ---------------------------------------------------------------------------
// MARK: - Ползунок с подписями
// ---------------------------------------------------------------------------
private struct LabeledSlider: View {
    let label: String
    let range:  ClosedRange<Float>
    @Binding var value: Float
    var format: String = "%.1f"
    var step: Float = 0

    var body: some View {
        VStack(spacing: 2) {
            HStack {
                Text(label)
                    .font(.system(size: 12))
                    .foregroundStyle(.white.opacity(0.8))
                Spacer()
                Text(String(format: format, value))
                    .font(.system(size: 12, weight: .semibold, design: .monospaced))
                    .foregroundStyle(.white)
                    .frame(minWidth: 38, alignment: .trailing)
            }
            // Шаг всегда Float — совпадает с типом Binding<Float>
            let stepValue: Float = step > 0 ? step : (range.upperBound - range.lowerBound) / 100.0
            Slider(value: $value, in: range, step: stepValue)
                .tint(.white)
        }
    }
}

// ---------------------------------------------------------------------------
// MARK: - Панель управления
// ---------------------------------------------------------------------------
struct ControlPanelView: View {
    @Binding var processingEnabled: Bool
    @Binding var showOriginal:      Bool
    @Binding var showHistogram:     Bool
    @Binding var claheClipLimit:    Float
    @Binding var claheTileGrid:     Int
    @Binding var smoothing:         Float

    @State private var expanded = false

    private var tileGridFloat: Binding<Float> {
        Binding(
            get:  { Float(claheTileGrid) },
            set:  { claheTileGrid = Int($0.rounded()) }
        )
    }

    var body: some View {
        VStack(spacing: 0) {
            // Основная строка кнопок
            HStack(spacing: 12) {
                // ON/OFF обработки
                Button {
                    withAnimation(.spring(duration: 0.25)) {
                        processingEnabled.toggle()
                    }
                } label: {
                    Label(
                        processingEnabled ? "АДАПТИВ" : "ОТКЛ",
                        systemImage: processingEnabled ? "wand.and.stars" : "wand.and.stars.inverse"
                    )
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(processingEnabled ? .black : .white)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 7)
                    .background(
                        Capsule()
                            .fill(processingEnabled ? .white : .white.opacity(0.15))
                    )
                }

                // Сравнение оригинал/обработанный
                // Кнопка показывает ЧТО СЕЙЧАС на экране и позволяет переключиться
                Button {
                    withAnimation(.easeInOut(duration: 0.2)) { showOriginal.toggle() }
                } label: {
                    Label(
                        showOriginal ? "Оригинал" : "Обработан",
                        systemImage: showOriginal ? "photo.on.rectangle" : "wand.and.sparkles"
                    )
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 7)
                    .background(
                        Capsule()
                            .fill(showOriginal ? .orange.opacity(0.7) : .blue.opacity(0.5))
                    )
                }

                Spacer()

                // Кнопка раскрытия настроек
                Button {
                    withAnimation(.spring(duration: 0.3)) { expanded.toggle() }
                } label: {
                    Image(systemName: expanded ? "chevron.down.circle.fill" : "slider.horizontal.3")
                        .font(.system(size: 20))
                        .foregroundStyle(.white.opacity(0.8))
                }
            }

            // Расширенная панель
            if expanded {
                Divider()
                    .background(.white.opacity(0.2))
                    .padding(.vertical, 8)

                VStack(spacing: 10) {
                    LabeledSlider(
                        label: "CLAHE — предел отсечения",
                        range: 1.0...10.0,
                        value: $claheClipLimit,
                        format: "%.1f"
                    )
                    LabeledSlider(
                        label: "CLAHE — размер сетки \(claheTileGrid)×\(claheTileGrid)",
                        range: 4...16,
                        value: tileGridFloat,
                        format: "%.0f",
                        step: 2
                    )
                    LabeledSlider(
                        label: "Сглаживание гаммы",
                        range: 0.0...0.95,
                        value: $smoothing,
                        format: "%.2f"
                    )
                    // Гистограмма
                    HStack {
                        Text("Показать гистограмму")
                            .font(.system(size: 12))
                            .foregroundStyle(.white.opacity(0.8))
                        Spacer()
                        Toggle("", isOn: $showHistogram)
                            .tint(.white)
                            .scaleEffect(0.8)
                    }
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(.black.opacity(0.65))
                .overlay(
                    RoundedRectangle(cornerRadius: 16)
                        .stroke(.white.opacity(0.1), lineWidth: 0.5)
                )
        )
        .padding(.horizontal, 12)
        .padding(.bottom, 8)
    }
}

// ---------------------------------------------------------------------------
// MARK: - Preview
// ---------------------------------------------------------------------------
#Preview {
    ZStack {
        Color.black.ignoresSafeArea()
        VStack {
            Spacer()
            ControlPanelView(
                processingEnabled: .constant(true),
                showOriginal:      .constant(false),
                showHistogram:     .constant(true),
                claheClipLimit:    .constant(3.0),
                claheTileGrid:     .constant(8),
                smoothing:         .constant(0.75)
            )
        }
    }
}
