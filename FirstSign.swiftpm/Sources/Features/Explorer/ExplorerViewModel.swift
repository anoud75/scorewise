import Foundation
import SwiftUI
import UIKit

@MainActor
final class ExplorerViewModel: ObservableObject {
    @Published var selectedImage: UIImage?
    @Published var objectText = ""
    @Published var fingerSpellingText = ""
    @Published var confidenceText = ""
    @Published var statusText = "Use camera or choose an image, then detect the object."
    @Published var isProcessing = false
    @Published var isLiveCameraMode = false
    @Published var showModelError = false
    @Published var fingerTokens: [FingerSpellingToken] = []

    private let classifier: ObjectClassifying
    private(set) var modelErrorMessage = "Model unavailable."
    private(set) var isUsingFallbackClassifier = false
    private var isLiveFrameProcessing = false
    private var lastLiveDetectionDate = Date.distantPast
    private let liveDetectionInterval: TimeInterval = 0.6

    init(classifier: ObjectClassifying? = nil) {
        if let classifier {
            self.classifier = classifier
            return
        }

        do {
            self.classifier = try MobileNetObjectClassifier()
        } catch {
            self.classifier = VisionFallbackClassifier()
            self.modelErrorMessage = "MobileNetV2 not found. Using built-in classifier."
            self.isUsingFallbackClassifier = true
            self.statusText = "Model fallback active. Live/object detection still works."
        }
    }

    func updateSelectedImage(_ image: UIImage) {
        isLiveCameraMode = false
        selectedImage = image
        statusText = "Image selected."
    }

    func setLiveCameraMode(_ enabled: Bool) {
        guard enabled != isLiveCameraMode else { return }
        isLiveCameraMode = enabled
        if enabled {
            statusText = "Live camera active. Point to an object."
            selectedImage = nil
        } else {
            isLiveFrameProcessing = false
            statusText = "Live camera stopped."
        }
    }

    func detectObject() {
        guard let selectedImage else {
            statusText = "Select an image first."
            return
        }
        runDetection(on: selectedImage, source: .manual)
    }

    func processLiveFrame(_ image: UIImage) {
        guard isLiveCameraMode else { return }
        guard !isLiveFrameProcessing else { return }

        let now = Date()
        guard now.timeIntervalSince(lastLiveDetectionDate) >= liveDetectionInterval else { return }
        lastLiveDetectionDate = now
        isLiveFrameProcessing = true
        runDetection(on: image, source: .live)
    }

    private func runDetection(on image: UIImage, source: DetectionSource) {
        isProcessing = true
        if source == .manual {
            statusText = isUsingFallbackClassifier ? "Detecting object (fallback)..." : "Detecting object..."
        }

        Task {
            defer {
                isProcessing = false
                if source == .live {
                    isLiveFrameProcessing = false
                }
            }
            do {
                let result = try await classifier.classify(image: image)
                let normalized = FingerSpellingService.normalizedObjectLabel(from: result.label)
                objectText = normalized
                confidenceText = "Confidence: \(Int(result.confidence * 100))%"
                applyFingerSpelling()
                statusText = source == .live ? "Live: \(normalized)" : "Object detected."
            } catch {
                if source == .manual {
                    statusText = "Detection failed."
                    confidenceText = ""
                    objectText = ""
                    fingerSpellingText = ""
                    fingerTokens = []
                }
            }
        }
    }

    func applyFingerSpelling() {
        let tokens = FingerSpellingService.tokens(for: objectText)
        fingerTokens = tokens
        fingerSpellingText = FingerSpellingService.displayText(from: tokens)
    }

    func clear() {
        objectText = ""
        fingerSpellingText = ""
        confidenceText = ""
        fingerTokens = []
        statusText = "Cleared."
    }
}

private enum DetectionSource {
    case manual
    case live
}
