//
//  CameraView.swift
//  CaptureMobile
//
//  Created by Maximilian Glasmacher on 20.03.26.
//

import SwiftUI
import AVFoundation
import PostHog

struct CameraView: View {
    @StateObject private var cameraManager = CameraManager()
    @Binding var capturedPreview: UIImage?

    @State private var focusPoint: CGPoint?
    @State private var focusTapID: UUID?

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            if cameraManager.isAuthorized {
                cameraContent
            } else if cameraManager.permissionDenied {
                permissionDeniedView
            } else {
                permissionRequestView
            }
        }
        .ignoresSafeArea()
        .onChange(of: cameraManager.capturedImage) { newImage in
            guard let image = newImage else { return }
            PostHogSDK.shared.capture("camera_photo_captured")
            capturedPreview = image
            cameraManager.capturedImage = nil
            cameraManager.stopSession()
        }
        .onChange(of: capturedPreview) { newValue in
            if newValue == nil {
                cameraManager.startSession()
            }
        }
    }

    // MARK: - Camera Content

    private var cameraContent: some View {
        ZStack {
            CameraPreviewView(
                session: cameraManager.captureSession,
                onSingleTap: { devicePoint, viewPoint in
                    guard capturedPreview == nil else { return }
                    cameraManager.focus(at: devicePoint)
                    focusPoint = viewPoint
                    focusTapID = UUID()

                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) {
                        focusTapID = nil
                    }
                },
                onDoubleTap: {
                    guard capturedPreview == nil else { return }
                    cameraManager.switchCamera()
                }
            )
            .ignoresSafeArea()
            .onAppear { cameraManager.startSession() }
            .onDisappear { cameraManager.stopSession() }

            if let point = focusPoint, let tapID = focusTapID {
                FocusIndicator()
                    .id(tapID)
                    .position(point)
                    .allowsHitTesting(false)
            }

            if let preview = capturedPreview {
                Image(uiImage: preview)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .ignoresSafeArea()
            } else {
                VStack {
                    Spacer()
                    captureButton
                        .padding(.bottom, 120)
                }
            }
        }
    }

    // MARK: - Capture Button

    private var captureButton: some View {
        Button(action: { takePhoto() }) {
            Circle()
                .stroke(.white, lineWidth: 6)
                .frame(width: 84, height: 84)
        }
        .disabled(cameraManager.isCapturing)
        .opacity(cameraManager.isCapturing ? 0.5 : 1.0)
    }

    // MARK: - Permission Views

    private var permissionRequestView: some View {
        VStack(spacing: CaptureSpacing.lg) {
            Image(systemName: "camera.fill")
                .font(.system(size: 48))
                .foregroundStyle(.white.opacity(0.6))
            Text("Camera Access Required")
                .font(CaptureFont.headingLg)
                .foregroundStyle(.white)
            Text("Allow camera access to capture events, flyers, and schedules.")
                .font(CaptureFont.body)
                .foregroundStyle(.white.opacity(0.7))
                .multilineTextAlignment(.center)
                .padding(.horizontal, CaptureSpacing.xxxl)
            Button("Allow Camera") {
                Task { await cameraManager.requestPermission() }
            }
            .font(CaptureFont.caption)
            .fontWeight(.semibold)
            .foregroundStyle(CaptureColors.text)
            .padding(.horizontal, CaptureSpacing.xxl)
            .padding(.vertical, CaptureSpacing.md)
            .background(.white, in: RoundedRectangle(cornerRadius: CaptureRadius.md))
        }
    }

    private var permissionDeniedView: some View {
        VStack(spacing: CaptureSpacing.lg) {
            Image(systemName: "camera.badge.ellipsis")
                .font(.system(size: 48))
                .foregroundStyle(.white.opacity(0.6))
            Text("Camera Access Denied")
                .font(CaptureFont.headingLg)
                .foregroundStyle(.white)
            Text("Enable camera access in Settings to capture photos.")
                .font(CaptureFont.body)
                .foregroundStyle(.white.opacity(0.7))
                .multilineTextAlignment(.center)
                .padding(.horizontal, CaptureSpacing.xxxl)
            Button("Open Settings") {
                if let url = URL(string: UIApplication.openSettingsURLString) {
                    UIApplication.shared.open(url)
                }
            }
            .font(CaptureFont.caption)
            .fontWeight(.semibold)
            .foregroundStyle(CaptureColors.text)
            .padding(.horizontal, CaptureSpacing.xxl)
            .padding(.vertical, CaptureSpacing.md)
            .background(.white, in: RoundedRectangle(cornerRadius: CaptureRadius.md))
        }
    }

    // MARK: - Actions

    private func takePhoto() {
        PostHogSDK.shared.capture("camera_capture_tapped")
        cameraManager.capturePhoto()
    }
}

// MARK: - Focus Indicator

private struct FocusIndicator: View {
    @State private var scale: CGFloat = 1.4
    @State private var opacity: Double = 0.0
    @State private var pulseScale: CGFloat = 1.0

    var body: some View {
        Circle()
            .stroke(Color.white.opacity(0.9), lineWidth: 1.5)
            .frame(width: 60, height: 60)
            .scaleEffect(scale * pulseScale)
            .opacity(opacity)
            .onAppear {
                withAnimation(.spring(response: 0.15, dampingFraction: 0.7)) {
                    scale = 1.0
                    opacity = 1.0
                }
                withAnimation(.easeInOut(duration: 0.3).delay(0.15)) {
                    pulseScale = 0.85
                }
                withAnimation(.easeInOut(duration: 0.3).delay(0.45)) {
                    pulseScale = 1.0
                }
                withAnimation(.easeOut(duration: 0.3).delay(0.75)) {
                    opacity = 0
                }
            }
    }
}

// MARK: - Camera Preview UIViewRepresentable

struct CameraPreviewView: UIViewRepresentable {
    let session: AVCaptureSession
    var onSingleTap: ((CGPoint, CGPoint) -> Void)?
    var onDoubleTap: (() -> Void)?

    func makeUIView(context: Context) -> CameraPreviewUIView {
        let view = CameraPreviewUIView()
        view.previewLayer.session = session
        view.previewLayer.videoGravity = .resizeAspectFill

        let doubleTap = UITapGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.handleDoubleTap))
        doubleTap.numberOfTapsRequired = 2
        view.addGestureRecognizer(doubleTap)

        let singleTap = UITapGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.handleSingleTap(_:)))
        singleTap.numberOfTapsRequired = 1
        singleTap.require(toFail: doubleTap)
        view.addGestureRecognizer(singleTap)

        return view
    }

    func updateUIView(_ uiView: CameraPreviewUIView, context: Context) {
        context.coordinator.onSingleTap = onSingleTap
        context.coordinator.onDoubleTap = onDoubleTap
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(onSingleTap: onSingleTap, onDoubleTap: onDoubleTap)
    }

    class Coordinator: NSObject {
        var onSingleTap: ((CGPoint, CGPoint) -> Void)?
        var onDoubleTap: (() -> Void)?

        init(onSingleTap: ((CGPoint, CGPoint) -> Void)?, onDoubleTap: (() -> Void)?) {
            self.onSingleTap = onSingleTap
            self.onDoubleTap = onDoubleTap
        }

        @objc func handleSingleTap(_ gesture: UITapGestureRecognizer) {
            guard let view = gesture.view as? CameraPreviewUIView else { return }
            let viewPoint = gesture.location(in: view)
            let devicePoint = view.previewLayer.captureDevicePointConverted(fromLayerPoint: viewPoint)
            onSingleTap?(devicePoint, viewPoint)
        }

        @objc func handleDoubleTap() {
            onDoubleTap?()
        }
    }
}

class CameraPreviewUIView: UIView {
    override class var layerClass: AnyClass { AVCaptureVideoPreviewLayer.self }

    var previewLayer: AVCaptureVideoPreviewLayer {
        layer as! AVCaptureVideoPreviewLayer
    }
}
