//
//  CameraManager.swift
//  CaptureMobile
//
//  Created by Maximilian Glasmacher on 20.03.26.
//

import AVFoundation
import UIKit
import Combine

final class CameraManager: NSObject, ObservableObject {
    @Published var isAuthorized = false
    @Published var capturedImage: UIImage?
    @Published var isCapturing = false
    @Published var permissionDenied = false

    private let session = AVCaptureSession()
    private let photoOutput = AVCapturePhotoOutput()
    private var currentInput: AVCaptureDeviceInput?
    private var usingFrontCamera = false

    var captureSession: AVCaptureSession { session }

    override init() {
        super.init()
        checkAuthorization()
    }

    // MARK: - Authorization

    func checkAuthorization() {
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            isAuthorized = true
        case .notDetermined:
            break
        default:
            permissionDenied = true
        }
    }

    func requestPermission() async {
        let granted = await AVCaptureDevice.requestAccess(for: .video)
        await MainActor.run {
            isAuthorized = granted
            permissionDenied = !granted
        }
    }

    // MARK: - Session Management

    func startSession() {
        guard isAuthorized else { return }

        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self else { return }
            guard !self.session.isRunning else { return }

            self.session.beginConfiguration()
            self.session.sessionPreset = .photo

            if self.session.inputs.isEmpty {
                guard let device = self.defaultDevice(),
                      let input = try? AVCaptureDeviceInput(device: device) else {
                    self.session.commitConfiguration()
                    return
                }
                if self.session.canAddInput(input) {
                    self.session.addInput(input)
                    self.currentInput = input
                }
            }

            if self.session.outputs.isEmpty, self.session.canAddOutput(self.photoOutput) {
                self.session.addOutput(self.photoOutput)
                self.photoOutput.isHighResolutionCaptureEnabled = true
            }

            self.session.commitConfiguration()
            self.session.startRunning()
        }
    }

    func stopSession() {
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            self?.session.stopRunning()
        }
    }

    // MARK: - Capture

    func capturePhoto() {
        guard !isCapturing else { return }
        isCapturing = true
        capturedImage = nil

        let settings = AVCapturePhotoSettings()
        settings.isHighResolutionPhotoEnabled = true
        photoOutput.capturePhoto(with: settings, delegate: self)
    }

    // MARK: - Camera Switching

    func switchCamera() {
        usingFrontCamera.toggle()

        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self else { return }
            self.session.beginConfiguration()

            if let current = self.currentInput {
                self.session.removeInput(current)
            }

            let position: AVCaptureDevice.Position = self.usingFrontCamera ? .front : .back
            guard let device = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: position),
                  let input = try? AVCaptureDeviceInput(device: device) else {
                self.session.commitConfiguration()
                return
            }

            if self.session.canAddInput(input) {
                self.session.addInput(input)
                self.currentInput = input
            }

            self.session.commitConfiguration()
        }
    }

    // MARK: - Focus

    func focus(at point: CGPoint) {
        guard let device = currentInput?.device else { return }
        guard device.isFocusPointOfInterestSupported || device.isExposurePointOfInterestSupported else { return }

        do {
            try device.lockForConfiguration()

            if device.isFocusPointOfInterestSupported {
                device.focusPointOfInterest = point
                device.focusMode = .autoFocus
            }
            if device.isExposurePointOfInterestSupported {
                device.exposurePointOfInterest = point
                device.exposureMode = .autoExpose
            }

            device.unlockForConfiguration()
        } catch {}
    }

    // MARK: - Helpers

    private func defaultDevice() -> AVCaptureDevice? {
        AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back)
    }

    private static func normalizeOrientation(_ image: UIImage) -> UIImage {
        guard image.imageOrientation != .up else { return image }
        let renderer = UIGraphicsImageRenderer(size: image.size)
        return renderer.image { _ in image.draw(at: .zero) }
    }

    private static func mirrorImage(_ image: UIImage) -> UIImage {
        let size = image.size
        let renderer = UIGraphicsImageRenderer(size: size)
        return renderer.image { context in
            let ctx = context.cgContext
            ctx.translateBy(x: size.width, y: 0)
            ctx.scaleBy(x: -1, y: 1)
            image.draw(at: .zero)
        }
    }
}

// MARK: - AVCapturePhotoCaptureDelegate

extension CameraManager: AVCapturePhotoCaptureDelegate {
    func photoOutput(
        _ output: AVCapturePhotoOutput,
        didFinishProcessingPhoto photo: AVCapturePhoto,
        error: Error?
    ) {
        DispatchQueue.main.async { [weak self] in
            self?.isCapturing = false
        }

        guard error == nil,
              let data = photo.fileDataRepresentation(),
              let image = UIImage(data: data) else {
            return
        }

        let finalImage = self.usingFrontCamera ? Self.mirrorImage(image) : Self.normalizeOrientation(image)

        DispatchQueue.main.async { [weak self] in
            self?.capturedImage = finalImage
        }
    }
}
