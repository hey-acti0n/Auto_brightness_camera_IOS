// CameraDisplayView.swift
// DZ — Полноэкранный превью кадра (чистый SwiftUI, без UIImageView)

import SwiftUI
import UIKit

/// Отображение `UIImage` через `Image(uiImage:)` — порядок слоёв в `ZStack`/`overlay`
/// совпадает с остальным SwiftUI-интерфейсом (в отличие от UIViewRepresentable).
struct CameraDisplayView: View {
    let image: UIImage?

    var body: some View {
        GeometryReader { geo in
            Group {
                if let img = image {
                    Image(uiImage: img)
                        .resizable()
                        .interpolation(.low)
                        .scaledToFill()
                        .frame(width: geo.size.width, height: geo.size.height)
                        .clipped()
                } else {
                    Color.black
                }
            }
            .frame(width: geo.size.width, height: geo.size.height)
        }
        // Касания обрабатывают кнопки поверх, а не «пустое» превью
        .allowsHitTesting(false)
    }
}
