import AVFoundation
import CoreImage
import PhotosUI
import QuartzCore
import SwiftUI
import UIKit

struct ExplorerView: View {
    @ObservedObject var viewModel: ExplorerViewModel
    let onClose: () -> Void

    @State private var selectedItem: PhotosPickerItem?

    var body: some View {
        ZStack(alignment: .topLeading) {
            Rectangle()
                .fill(Color(red: 0.72, green: 0.72, blue: 0.72))
                .overlay(
                    Rectangle()
                        .stroke(Color.black, lineWidth: 4)
                )

            VStack(spacing: 0) {
                ExplorerTitleBar(
                    onClose: onClose
                )
                .frame(height: 56)

                VStack(spacing: 16) {
                    imagePanel
                    resultPanel

                    if !viewModel.confidenceText.isEmpty {
                        HStack {
                            Text(viewModel.confidenceText)
                                .font(.system(size: 11, weight: .medium, design: .monospaced))
                            Spacer()
                        }
                    }

                    fingerPanel

                    if shouldShowStatusText {
                        HStack {
                            Text(viewModel.statusText)
                                .font(.system(size: 11, weight: .medium, design: .monospaced))
                                .lineLimit(1)
                                .minimumScaleFactor(0.75)
                            Spacer()
                        }
                    }

                    Spacer(minLength: 8)

                    ExplorerBottomBar()
                        .frame(height: 18)
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 14)
            }
        }
        .alert("Core ML Model Error", isPresented: $viewModel.showModelError) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(viewModel.modelErrorMessage)
        }
        .onChange(of: selectedItem) { _, newItem in
            guard let newItem else { return }
            Task {
                if let data = try? await newItem.loadTransferable(type: Data.self),
                   let image = UIImage(data: data) {
                    await MainActor.run {
                        viewModel.updateSelectedImage(image)
                        viewModel.detectObject()
                    }
                }
            }
        }
        .onDisappear {
            viewModel.setLiveCameraMode(false)
        }
    }

    private var imagePanel: some View {
        ZStack(alignment: .topTrailing) {
            Rectangle()
                .fill(Color.white)
                .overlay(
                    Rectangle()
                        .stroke(Color.black, lineWidth: 6)
                )

            Group {
                if viewModel.isLiveCameraMode {
                    LiveCameraPreview(isRunning: true) { frame in
                        viewModel.processLiveFrame(frame)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .overlay(alignment: .topLeading) {
                        Text("LIVE")
                            .font(.system(size: 12, weight: .bold, design: .monospaced))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(Color.red.opacity(0.9))
                            .clipShape(RoundedRectangle(cornerRadius: 6))
                            .padding(12)
                    }
                } else if let image = viewModel.selectedImage {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFit()
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .background(Color.black.opacity(0.05))
                } else {
                    ImagePlaceholderView()
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
            .padding(8)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .clipped()

            HStack(spacing: 8) {
                Button(action: toggleLiveCamera) {
                    ImageButton(
                        assetName: "explorer-action-camera",
                        fallbackText: viewModel.isLiveCameraMode ? "STOP" : "LIVE"
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 4)
                            .stroke(viewModel.isLiveCameraMode ? Color.red : Color.clear, lineWidth: 2)
                    )
                }
                .buttonStyle(.plain)

                PhotosPicker(selection: $selectedItem, matching: .images, preferredItemEncoding: .automatic) {
                    Image(systemName: "photo")
                        .font(.system(size: 24, weight: .regular))
                        .foregroundStyle(.black)
                        .padding(8)
                        .background(Color.white.opacity(0.85))
                        .clipShape(RoundedRectangle(cornerRadius: 6))
                }
                .buttonStyle(.plain)
            }
            .padding(12)

            if viewModel.isProcessing {
                ProgressView()
                    .progressViewStyle(.circular)
                    .tint(.black)
            }
        }
        .frame(maxWidth: .infinity)
        .frame(height: 420)
        .clipped()
    }

    private func toggleLiveCamera() {
        if viewModel.isLiveCameraMode {
            viewModel.setLiveCameraMode(false)
            return
        }

        guard UIImagePickerController.isSourceTypeAvailable(.camera) else {
            viewModel.statusText = "Camera is not available on this device."
            return
        }

        let cameraStatus = AVCaptureDevice.authorizationStatus(for: .video)
        switch cameraStatus {
        case .authorized:
            viewModel.setLiveCameraMode(true)
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .video) { granted in
                Task { @MainActor in
                    if granted {
                        viewModel.setLiveCameraMode(true)
                    } else {
                        viewModel.statusText = "Camera permission denied."
                    }
                }
            }
        case .restricted, .denied:
            viewModel.statusText = "Allow camera access in Settings to use live Explorer."
        @unknown default:
            viewModel.statusText = "Unable to access camera."
        }
    }

    private var resultPanel: some View {
        HStack(spacing: 10) {
            OutputFieldView(text: viewModel.objectText.isEmpty ? "Detected object..." : viewModel.objectText)

            Button(action: viewModel.applyFingerSpelling) {
                ImageButton(assetName: "explorer-action-a", fallbackText: "A")
            }
            .buttonStyle(.plain)
            .disabled(viewModel.isLiveCameraMode)
            .opacity(viewModel.isLiveCameraMode ? 0.45 : 1)
        }
    }

    private var fingerPanel: some View {
        HStack(spacing: 10) {
            OutputFieldView(text: viewModel.fingerSpellingText.isEmpty ? "Finger spelling..." : viewModel.fingerSpellingText)

            Button(action: viewModel.clear) {
                ImageButton(assetName: "explorer-action-smile", fallbackText: ":)")
            }
            .buttonStyle(.plain)
        }
    }

    private var shouldShowStatusText: Bool {
        let status = viewModel.statusText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !status.isEmpty else { return false }
        return status != "Object detected."
    }
}

private struct ExplorerTitleBar: View {
    let onClose: () -> Void

    var body: some View {
        ZStack {
            if let image = AssetImageLoader.image(named: "explorer-title-bar") {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
            } else {
                Rectangle().fill(Color(red: 0.09, green: 0.04, blue: 0.83))
            }

            HStack(spacing: 10) {
                if let icon = AssetImageLoader.image(named: "desktop-icon-explorer") {
                    Image(uiImage: icon)
                        .resizable()
                        .scaledToFit()
                        .frame(width: 40, height: 30)
                }
                Text("Explorer")
                    .font(.system(size: 20, weight: .regular, design: .monospaced))
                    .foregroundStyle(.white)

                Spacer()

                Button(action: onClose) {
                    if let closeImage = AssetImageLoader.image(named: "explorer-close-button") {
                        Image(uiImage: closeImage)
                            .resizable()
                            .scaledToFit()
                            .frame(width: 42, height: 42)
                    } else {
                        Rectangle()
                            .fill(Color(red: 0.82, green: 0.84, blue: 0.86))
                            .overlay(
                                Image(systemName: "xmark")
                                    .font(.system(size: 20, weight: .regular))
                                    .foregroundStyle(.black)
                            )
                            .frame(width: 42, height: 42)
                            .overlay(
                                Rectangle()
                                    .stroke(Color.black, lineWidth: 2)
                            )
                    }
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 14)
        }
    }
}

private struct OutputFieldView: View {
    let text: String

    var body: some View {
        ZStack(alignment: .leading) {
            if let image = AssetImageLoader.image(named: "explorer-input-field") {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
            } else {
                Rectangle()
                    .fill(Color(red: 0.91, green: 0.91, blue: 0.91))
                    .overlay(
                        Rectangle()
                            .stroke(Color.black, lineWidth: 3)
                    )
            }

            Text(text)
                .font(.system(size: 16, weight: .regular, design: .monospaced))
                .lineLimit(1)
                .minimumScaleFactor(0.7)
                .foregroundStyle(.black)
                .padding(.horizontal, 10)
        }
        .frame(height: 64)
    }
}

private struct ImageButton: View {
    let assetName: String
    let fallbackText: String

    var body: some View {
        ZStack {
            if let image = AssetImageLoader.image(named: assetName) {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFit()
            } else {
                Rectangle()
                    .fill(Color(red: 0.09, green: 0.9, blue: 0.35))
                    .overlay(
                        Rectangle()
                            .stroke(Color.black, lineWidth: 2)
                    )
                    .overlay(
                        Text(fallbackText)
                            .font(.system(size: 14, weight: .bold, design: .monospaced))
                            .foregroundStyle(.black)
                    )
            }
        }
        .frame(width: 60, height: 60)
    }
}

private struct ExplorerBottomBar: View {
    var body: some View {
        if let image = AssetImageLoader.image(named: "explorer-bottom-bar") {
            Image(uiImage: image)
                .resizable()
                .scaledToFill()
        } else {
            HStack(spacing: 2) {
                Rectangle().fill(Color.gray).frame(width: 18)
                Rectangle().fill(Color(red: 0.7, green: 0.7, blue: 0.7))
                Rectangle().fill(Color(red: 0.7, green: 0.7, blue: 0.7))
                Rectangle().fill(Color.gray).frame(width: 18)
            }
            .overlay(
                Rectangle()
                    .stroke(Color.black, lineWidth: 2)
            )
        }
    }
}

private struct ImagePlaceholderView: View {
    var body: some View {
        ZStack {
            if let windowAsset = AssetImageLoader.image(named: "explorer-window-placeholder") {
                Image(uiImage: windowAsset)
                    .resizable()
                    .scaledToFill()
            } else {
                Rectangle()
                    .fill(Color(red: 0.73, green: 0.88, blue: 0.9))
                    .overlay(
                        Image(systemName: "photo")
                            .font(.system(size: 68, weight: .regular))
                            .foregroundStyle(.white.opacity(0.9))
                    )
            }
        }
        .clipped()
    }
}

private struct LiveCameraPreview: UIViewRepresentable {
    let isRunning: Bool
    let onFrame: (UIImage) -> Void

    func makeUIView(context: Context) -> CameraPreviewView {
        let view = CameraPreviewView()
        context.coordinator.attach(to: view)
        return view
    }

    func updateUIView(_ uiView: CameraPreviewView, context: Context) {
        context.coordinator.onFrame = onFrame
        context.coordinator.setRunning(isRunning)
    }

    static func dismantleUIView(_ uiView: CameraPreviewView, coordinator: Coordinator) {
        coordinator.setRunning(false)
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(onFrame: onFrame)
    }

    final class Coordinator: NSObject, AVCaptureVideoDataOutputSampleBufferDelegate {
        private let session = AVCaptureSession()
        private let videoOutput = AVCaptureVideoDataOutput()
        private let sessionQueue = DispatchQueue(label: "explorer.live.camera.session.queue")
        private let videoQueue = DispatchQueue(label: "explorer.live.camera.frame.queue")
        private let ciContext = CIContext()
        private var isConfigured = false
        private var lastFrameTime: CFTimeInterval = 0
        private let frameInterval: CFTimeInterval = 0.35

        fileprivate var onFrame: (UIImage) -> Void
        private weak var previewView: CameraPreviewView?

        init(onFrame: @escaping (UIImage) -> Void) {
            self.onFrame = onFrame
        }

        func attach(to view: CameraPreviewView) {
            previewView = view
            view.previewLayer.session = session
        }

        func setRunning(_ running: Bool) {
            sessionQueue.async {
                if running {
                    self.configureIfNeeded()
                    guard !self.session.isRunning else { return }
                    self.session.startRunning()
                } else {
                    guard self.session.isRunning else { return }
                    self.session.stopRunning()
                }
            }
        }

        private func configureIfNeeded() {
            guard !isConfigured else { return }

            session.beginConfiguration()
            defer { session.commitConfiguration() }
            session.sessionPreset = .medium

            let discoveredCameras = AVCaptureDevice.DiscoverySession(
                deviceTypes: [.builtInWideAngleCamera, .builtInDualCamera, .builtInTripleCamera],
                mediaType: .video,
                position: .unspecified
            ).devices

            let prioritizedCameras = [
                discoveredCameras.first(where: { $0.position == .front }),
                discoveredCameras.first(where: { $0.position == .back }),
                AVCaptureDevice.default(for: .video)
            ].compactMap { $0 }

            var selectedCamera: AVCaptureDevice?
            var selectedInput: AVCaptureDeviceInput?
            for camera in prioritizedCameras {
                guard let input = try? AVCaptureDeviceInput(device: camera) else { continue }
                guard session.canAddInput(input) else { continue }
                selectedCamera = camera
                selectedInput = input
                break
            }

            guard
                let camera = selectedCamera,
                let input = selectedInput
            else {
                return
            }

            session.addInput(input)

            videoOutput.videoSettings = [
                kCVPixelBufferPixelFormatTypeKey as String: Int(kCVPixelFormatType_32BGRA)
            ]
            videoOutput.alwaysDiscardsLateVideoFrames = true
            videoOutput.setSampleBufferDelegate(self, queue: videoQueue)

            guard session.canAddOutput(videoOutput) else {
                return
            }
            session.addOutput(videoOutput)

            if let connection = videoOutput.connection(with: .video) {
                if connection.isVideoMirroringSupported {
                    connection.automaticallyAdjustsVideoMirroring = false
                    connection.isVideoMirrored = (camera.position == .front)
                }
                if connection.isVideoRotationAngleSupported(0) {
                    connection.videoRotationAngle = 0
                }
            }

            DispatchQueue.main.async { [weak self] in
                guard let self, let previewConnection = self.previewView?.previewLayer.connection else { return }

                if previewConnection.isVideoMirroringSupported {
                    previewConnection.automaticallyAdjustsVideoMirroring = false
                    previewConnection.isVideoMirrored = (camera.position == .front)
                }
                if previewConnection.isVideoRotationAngleSupported(0) {
                    previewConnection.videoRotationAngle = 0
                }
            }

            isConfigured = true
        }

        func captureOutput(
            _ output: AVCaptureOutput,
            didOutput sampleBuffer: CMSampleBuffer,
            from connection: AVCaptureConnection
        ) {
            guard session.isRunning else { return }
            let now = CACurrentMediaTime()
            guard now - lastFrameTime >= frameInterval else { return }
            lastFrameTime = now

            guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
            let ciImage = CIImage(cvPixelBuffer: pixelBuffer)
            guard let cgImage = ciContext.createCGImage(ciImage, from: ciImage.extent) else { return }

            let image = UIImage(cgImage: cgImage, scale: 1, orientation: .up)
            DispatchQueue.main.async {
                self.onFrame(image)
            }
        }
    }
}

private final class CameraPreviewView: UIView {
    override class var layerClass: AnyClass { AVCaptureVideoPreviewLayer.self }

    var previewLayer: AVCaptureVideoPreviewLayer {
        layer as! AVCaptureVideoPreviewLayer
    }

    override init(frame: CGRect) {
        super.init(frame: frame)
        previewLayer.videoGravity = .resizeAspectFill
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}

#Preview {
    ExplorerView(viewModel: ExplorerViewModel(), onClose: {})
}
