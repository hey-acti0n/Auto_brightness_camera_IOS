// CameraManager.swift
// DZ — Управление камерой, захват и обработка кадров в реальном времени

import AVFoundation
import Combine
import CoreImage
import UIKit

// ---------------------------------------------------------------------------
enum CameraPermissionState {
    case notDetermined, authorized, denied
}

// ---------------------------------------------------------------------------
// MARK: - CameraManager
// ---------------------------------------------------------------------------
final class CameraManager: NSObject, ObservableObject {

    // Публикуемые свойства
    @Published var processedFrame: UIImage?
    @Published var originalFrame:  UIImage?
    @Published var metrics         = BrightnessMetrics()
    @Published var isRunning       = false
    @Published var permissionState: CameraPermissionState = .notDetermined
    @Published var showOriginal    = false
    @Published var showHistogram   = true

    // Настройки алгоритма — при изменении передают значение в процессор
    @Published var processingEnabled: Bool = true {
        didSet { processor.processingEnabled = processingEnabled }
    }
    @Published var claheClipLimit: Float = 3.0 {
        didSet { processor.claheClipLimit = claheClipLimit }
    }
    @Published var claheTileGrid: Int = 8 {
        didSet { processor.claheTileGrid = claheTileGrid }
    }
    @Published var smoothing: Float = 0.75 {
        didSet { processor.temporalSmoothingFactor = smoothing }
    }

    // -----------------------------------------------------------------------
    // Явный тип BrightnessProcessor (не-опциональный).
    // Инициализируется до super.init(), что убирает optional-вывод.
    // -----------------------------------------------------------------------
    private let processor: BrightnessProcessor

    private let session         = AVCaptureSession()
    private let videoOutput     = AVCaptureVideoDataOutput()
    private let processingQueue = DispatchQueue(
        label: "ru.dz.adaptive-brightness.processing",
        qos: .userInteractive
    )

    /// Растеризация оригинала в CGImage (UIImage(ciImage:) даёт «лёгкий» CI-UIImage,
    /// который SwiftUI Image(uiImage:) на устройстве часто рисует как чёрный экран).
    private static let ciRasterContext = CIContext(options: [
        CIContextOption.useSoftwareRenderer: false
    ])

    // -----------------------------------------------------------------------
    override init() {
        processor = BrightnessProcessor()   // гарантированно не-nil
        super.init()
        checkPermission()
    }

    // -----------------------------------------------------------------------
    // MARK: - Разрешения
    // -----------------------------------------------------------------------
    func checkPermission() {
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            permissionState = .authorized
            setupSession()
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .video) { [weak self] granted in
                DispatchQueue.main.async {
                    self?.permissionState = granted ? .authorized : .denied
                }
                if granted { self?.setupSession() }
            }
        default:
            permissionState = .denied
        }
    }

    // -----------------------------------------------------------------------
    // MARK: - Настройка сессии
    // -----------------------------------------------------------------------
    private func setupSession() {
        session.beginConfiguration()
        session.sessionPreset = .hd1280x720

        guard
            let camera = AVCaptureDevice.default(.builtInWideAngleCamera,
                                                  for: .video,
                                                  position: .back),
            let input  = try? AVCaptureDeviceInput(device: camera),
            session.canAddInput(input)
        else {
            session.commitConfiguration()
            return
        }
        session.addInput(input)

        videoOutput.videoSettings = [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA
        ]
        videoOutput.alwaysDiscardsLateVideoFrames = true
        videoOutput.setSampleBufferDelegate(self, queue: processingQueue)

        guard session.canAddOutput(videoOutput) else {
            session.commitConfiguration()
            return
        }
        session.addOutput(videoOutput)

        session.commitConfiguration()
    }

    // -----------------------------------------------------------------------
    // MARK: - Старт / Стоп
    // -----------------------------------------------------------------------
    func start() {
        guard !session.isRunning else { return }
        processingQueue.async { [weak self] in
            self?.session.startRunning()
            DispatchQueue.main.async { self?.isRunning = true }
        }
    }

    func stop() {
        guard session.isRunning else { return }
        processingQueue.async { [weak self] in
            self?.session.stopRunning()
            DispatchQueue.main.async { self?.isRunning = false }
        }
    }
}

// ---------------------------------------------------------------------------
// MARK: - AVCaptureVideoDataOutputSampleBufferDelegate
// ---------------------------------------------------------------------------
extension CameraManager: AVCaptureVideoDataOutputSampleBufferDelegate {

    func captureOutput(
        _ output: AVCaptureOutput,
        didOutput sampleBuffer: CMSampleBuffer,
        from connection: AVCaptureConnection
    ) {
        guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }

        var objcMetrics: FrameMetrics?
        let processed = processor.process(pixelBuffer: pixelBuffer, metrics: &objcMetrics)
        let metricsValue = objcMetrics.map { BrightnessMetrics(from: $0) } ?? BrightnessMetrics()

        // Растровый оригинал (после process — буфер ещё валиден в этом же вызове делегата)
        let original = makeRasterOriginalImage(from: pixelBuffer) ?? processed

        DispatchQueue.main.async { [weak self] in
            self?.originalFrame  = original
            self?.processedFrame = processed ?? original
            self?.metrics        = metricsValue
        }
    }

    /// CVPixelBuffer → bitmap UIImage (совместимо с SwiftUI Image(uiImage:)).
    private func makeRasterOriginalImage(from pixelBuffer: CVPixelBuffer) -> UIImage? {
        let ci = CIImage(cvPixelBuffer: pixelBuffer)
        let extent = ci.extent.integral
        guard extent.width > 1, extent.height > 1 else { return nil }
        guard let cg = Self.ciRasterContext.createCGImage(ci, from: extent) else { return nil }
        return UIImage(cgImage: cg, scale: 1.0, orientation: .right)
    }
}
