// ContentView.swift
// DZ — Главный экран: полноэкранная камера + адаптивная обработка

import SwiftUI

struct ContentView: View {

    @StateObject private var camera = CameraManager()

    var body: some View {
        Group {
            switch camera.permissionState {
            case .notDetermined: loadingView
            case .denied:        deniedView
            case .authorized:    cameraView
            }
        }
        .preferredColorScheme(.dark)
        .onAppear    { camera.start() }
        .onDisappear { camera.stop()  }
    }

    // -----------------------------------------------------------------------
    // MARK: - Основной экран с камерой
    // -----------------------------------------------------------------------
    @ViewBuilder
    private var cameraView: some View {
        let displayImage = camera.showOriginal
            ? camera.originalFrame
            : camera.processedFrame

        GeometryReader { proxy in
            ZStack {
                Color.black.ignoresSafeArea()
                CameraDisplayView(image: displayImage).ignoresSafeArea()

                // Слой поверх камеры (теперь тоже SwiftUI — порядок гарантирован)
                HStack(alignment: .top, spacing: 0) {
                    Button {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            camera.showOriginal.toggle()
                        }
                    } label: {
                        Text(camera.showOriginal ? "ОРИГИНАЛ" : "ОБРАБОТАН")
                            .font(.system(size: 12, weight: .bold))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 14)
                            .padding(.vertical, 8)
                            .background(
                                Capsule()
                                    .fill(camera.showOriginal
                                          ? Color.orange.opacity(0.85)
                                          : Color.black.opacity(0.55))
                            )
                    }
                    .padding(.leading, 16)

                    Spacer(minLength: 0)

                    BrightnessLevelIndicator(
                        level:  camera.metrics.meanBrightness,
                        accent: camera.metrics.lightingType.accentColor
                    )
                    .padding(.trailing, 14)
                }
                .padding(.top, proxy.safeAreaInsets.top + 10)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                .allowsHitTesting(true)
                .zIndex(1)
            }
            .frame(width: proxy.size.width, height: proxy.size.height)
            .ignoresSafeArea()
        }
        .ignoresSafeArea()
        .statusBarHidden(true)
    }

    // -----------------------------------------------------------------------
    // MARK: - Ожидание разрешения
    // -----------------------------------------------------------------------
    private var loadingView: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            VStack(spacing: 16) {
                ProgressView().tint(.white).scaleEffect(1.4)
                Text("Запрос доступа к камере…")
                    .foregroundStyle(.white.opacity(0.7))
                    .font(.system(size: 15))
            }
        }
    }

    // -----------------------------------------------------------------------
    // MARK: - Отказ в разрешении
    // -----------------------------------------------------------------------
    private var deniedView: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            VStack(spacing: 20) {
                Image(systemName: "camera.slash.fill")
                    .font(.system(size: 56))
                    .foregroundStyle(.red.opacity(0.8))
                Text("Нет доступа к камере")
                    .font(.title2.bold())
                    .foregroundStyle(.white)
                Text("Настройки → Конфиденциальность → Камера")
                    .font(.subheadline)
                    .foregroundStyle(.white.opacity(0.6))
                    .multilineTextAlignment(.center)
                Button("Открыть Настройки") {
                    if let url = URL(string: UIApplication.openSettingsURLString) {
                        UIApplication.shared.open(url)
                    }
                }
                .buttonStyle(.borderedProminent)
                .tint(.white)
                .foregroundStyle(.black)
            }
            .padding(32)
        }
    }
}

// ---------------------------------------------------------------------------
// MARK: - Индикатор уровня яркости (средняя luma кадра, 0…100 %)
// ---------------------------------------------------------------------------
private struct BrightnessLevelIndicator: View {
    let level:  Float
    let accent: Color

    private var clamped: CGFloat {
        CGFloat(min(1, max(0, level)))
    }

    private var percent: Int {
        Int((min(1, max(0, level)) * 100).rounded())
    }

    private let trackHeight: CGFloat = 112

    var body: some View {
        VStack(alignment: .trailing, spacing: 6) {
            Text("\(percent)%")
                .font(.system(size: 12, weight: .bold, design: .monospaced))
                .foregroundStyle(.white)
                .shadow(color: .black.opacity(0.45), radius: 2, x: 0, y: 1)

            ZStack(alignment: .bottom) {
                Capsule()
                    .fill(.white.opacity(0.22))
                Capsule()
                    .fill(
                        LinearGradient(
                            colors: [accent.opacity(0.55), accent],
                            startPoint: .bottom,
                            endPoint: .top
                        )
                    )
                    .frame(height: max(6, trackHeight * clamped))
                    .animation(.easeOut(duration: 0.12), value: clamped)
            }
            .frame(width: 10, height: trackHeight)

            Image(systemName: "sun.max.fill")
                .font(.system(size: 11))
                .foregroundStyle(.white.opacity(0.75))
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 10)
        .background {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(.black.opacity(0.45))
        }
    }
}

#Preview {
    ContentView()
}
