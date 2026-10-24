import AVFoundation
import Foundation
import UIKit

/// Owns the AVFoundation capture session. Always the rear wide-angle camera at zoom 1.0 so
/// every capture in a session shares the same lens, as the protocol requires.
final class CameraService: NSObject, ObservableObject, AVCapturePhotoCaptureDelegate {
    enum CameraError: LocalizedError {
        case notAuthorized, noCamera, configurationFailed, captureFailed

        var errorDescription: String? {
            switch self {
            case .notAuthorized: return "Camera access is off. Turn it on in Settings to capture."
            case .noCamera: return "No rear camera is available on this device."
            case .configurationFailed: return "The camera could not be configured."
            case .captureFailed: return "The photo could not be captured. Try again."
            }
        }
    }

    let session = AVCaptureSession()
    @Published private(set) var isRunning = false
    @Published private(set) var errorMessage: String?

    private let sessionQueue = DispatchQueue(label: "org.research.symmetry.camera")
    private let photoOutput = AVCapturePhotoOutput()
    private var isConfigured = false
    private var continuation: CheckedContinuation<Data, Error>?

    func start() {
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            startSession()
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .video) { [weak self] granted in
                if granted { self?.startSession() } else { self?.report(.notAuthorized) }
            }
        default:
            report(.notAuthorized)
        }
    }

    func stop() {
        sessionQueue.async { [self] in
            if session.isRunning { session.stopRunning() }
            DispatchQueue.main.async { self.isRunning = false }
        }
    }

    private func startSession() {
        sessionQueue.async { [self] in
            do {
                try configureIfNeeded()
            } catch let error as CameraError {
                report(error)
                return
            } catch {
                report(.configurationFailed)
                return
            }
            if !session.isRunning { session.startRunning() }
            DispatchQueue.main.async { self.isRunning = self.session.isRunning }
        }
    }

    private func report(_ error: CameraError) {
        DispatchQueue.main.async { self.errorMessage = error.errorDescription }
    }

    private func configureIfNeeded() throws {
        guard !isConfigured else { return }
        session.beginConfiguration()
        defer { session.commitConfiguration() }
        session.sessionPreset = .photo

        guard let device = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back) else {
            throw CameraError.noCamera
        }
        let input = try AVCaptureDeviceInput(device: device)
        guard session.canAddInput(input) else { throw CameraError.configurationFailed }
        session.addInput(input)
        guard session.canAddOutput(photoOutput) else { throw CameraError.configurationFailed }
        session.addOutput(photoOutput)
        photoOutput.maxPhotoQualityPrioritization = .quality

        try device.lockForConfiguration()
        device.videoZoomFactor = max(device.minAvailableVideoZoomFactor, 1.0)
        if device.isFocusModeSupported(.continuousAutoFocus) { device.focusMode = .continuousAutoFocus }
        if device.isExposureModeSupported(.continuousAutoExposure) { device.exposureMode = .continuousAutoExposure }
        device.unlockForConfiguration()

        if let connection = photoOutput.connection(with: .video), connection.isVideoRotationAngleSupported(90) {
            connection.videoRotationAngle = 90 // portrait
        }
        isConfigured = true
    }

    /// Captures one JPEG. The data carries EXIF orientation; `ImageBridge` normalizes it.
    func capturePhoto() async throws -> Data {
        try await withCheckedThrowingContinuation { cont in
            sessionQueue.async { [self] in
                guard session.isRunning, continuation == nil else {
                    cont.resume(throwing: CameraError.captureFailed)
                    return
                }
                continuation = cont
                let settings: AVCapturePhotoSettings
                if photoOutput.availablePhotoCodecTypes.contains(.jpeg) {
                    settings = AVCapturePhotoSettings(format: [AVVideoCodecKey: AVVideoCodecType.jpeg])
                } else {
                    settings = AVCapturePhotoSettings()
                }
                settings.flashMode = .off
                settings.photoQualityPrioritization = .quality
                photoOutput.capturePhoto(with: settings, delegate: self)
            }
        }
    }

    func photoOutput(_ output: AVCapturePhotoOutput, didFinishProcessingPhoto photo: AVCapturePhoto, error: Error?) {
        sessionQueue.async { [self] in
            guard let cont = continuation else { return }
            continuation = nil
            if let error {
                cont.resume(throwing: error)
            } else if let data = photo.fileDataRepresentation() {
                cont.resume(returning: data)
            } else {
                cont.resume(throwing: CameraError.captureFailed)
            }
        }
    }
}
