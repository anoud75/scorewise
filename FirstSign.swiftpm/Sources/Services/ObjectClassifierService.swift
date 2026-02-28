import CoreML
import Foundation
import ImageIO
import UIKit
import Vision

struct ObjectClassificationResult {
    let label: String
    let confidence: Double
}

protocol ObjectClassifying {
    func classify(image: UIImage) async throws -> ObjectClassificationResult
}

enum ObjectClassifierError: LocalizedError {
    case modelNotFound
    case imageConversionFailed
    case noResults

    var errorDescription: String? {
        switch self {
        case .modelNotFound:
            return "Model file not found."
        case .imageConversionFailed:
            return "Unable to process the selected image."
        case .noResults:
            return "No object could be recognized."
        }
    }
}

final class MobileNetObjectClassifier: ObjectClassifying {
    private let visionModel: VNCoreMLModel

    init(bundle: Bundle = .main) throws {
        let coreMLModel = try Self.loadModel(bundle: bundle)
        self.visionModel = try VNCoreMLModel(for: coreMLModel)
    }

    func classify(image: UIImage) async throws -> ObjectClassificationResult {
        guard let cgImage = image.cgImage else {
            throw ObjectClassifierError.imageConversionFailed
        }

        return try await withCheckedThrowingContinuation { continuation in
            let request = VNCoreMLRequest(model: visionModel) { request, error in
                if let error {
                    continuation.resume(throwing: error)
                    return
                }

                guard
                    let observations = request.results as? [VNClassificationObservation],
                    let top = observations.first
                else {
                    continuation.resume(throwing: ObjectClassifierError.noResults)
                    return
                }

                continuation.resume(returning:
                    ObjectClassificationResult(
                        label: top.identifier,
                        confidence: Double(top.confidence)
                    )
                )
            }

            request.imageCropAndScaleOption = .centerCrop

            DispatchQueue.global(qos: .userInitiated).async {
                do {
                    let orientation = CGImagePropertyOrientation(image.imageOrientation)
                    let handler = VNImageRequestHandler(
                        cgImage: cgImage,
                        orientation: orientation,
                        options: [:]
                    )
                    try handler.perform([request])
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    private static func loadModel(bundle: Bundle) throws -> MLModel {
        var candidateURLs: [URL] = []
        if let compiledURL = bundle.url(forResource: "MobileNetV2", withExtension: "mlmodelc") {
            candidateURLs.append(compiledURL)
        }
        if let sourceURL = bundle.url(forResource: "MobileNetV2", withExtension: "mlmodel") {
            candidateURLs.append(sourceURL)
        }
        if let packageURL = bundle.url(forResource: "MobileNetV2", withExtension: "mlpackage") {
            candidateURLs.append(packageURL)
        }

        candidateURLs.append(contentsOf: AssetImageLoader.resourceURLs(named: "MobileNetV2", extensions: ["mlmodelc"]))
        candidateURLs.append(contentsOf: AssetImageLoader.resourceURLs(named: "MobileNetV2", extensions: ["mlmodel"]))
        candidateURLs.append(contentsOf: AssetImageLoader.resourceURLs(named: "MobileNetV2", extensions: ["mlpackage"]))

        var seen = Set<URL>()
        var uniqueCandidates: [URL] = []
        for url in candidateURLs where !seen.contains(url) {
            seen.insert(url)
            uniqueCandidates.append(url)
        }

        for url in uniqueCandidates {
            do {
                let ext = url.pathExtension.lowercased()
                if ext == "mlmodelc" {
                    return try MLModel(contentsOf: url)
                }
                if ext == "mlmodel" || ext == "mlpackage" {
                    let compiledURL = try MLModel.compileModel(at: url)
                    return try MLModel(contentsOf: compiledURL)
                }
            } catch {
                continue
            }
        }

        throw ObjectClassifierError.modelNotFound
    }
}

final class VisionFallbackClassifier: ObjectClassifying {
    func classify(image: UIImage) async throws -> ObjectClassificationResult {
        guard let cgImage = image.cgImage else {
            throw ObjectClassifierError.imageConversionFailed
        }

        return try await withCheckedThrowingContinuation { continuation in
            let request = VNClassifyImageRequest { request, error in
                if let error {
                    continuation.resume(throwing: error)
                    return
                }

                guard
                    let observations = request.results as? [VNClassificationObservation],
                    let top = observations.first
                else {
                    continuation.resume(throwing: ObjectClassifierError.noResults)
                    return
                }

                continuation.resume(returning:
                    ObjectClassificationResult(
                        label: top.identifier,
                        confidence: Double(top.confidence)
                    )
                )
            }

            DispatchQueue.global(qos: .userInitiated).async {
                do {
                    let orientation = CGImagePropertyOrientation(image.imageOrientation)
                    let handler = VNImageRequestHandler(
                        cgImage: cgImage,
                        orientation: orientation,
                        options: [:]
                    )
                    try handler.perform([request])
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }
}

private extension CGImagePropertyOrientation {
    init(_ orientation: UIImage.Orientation) {
        switch orientation {
        case .up: self = .up
        case .upMirrored: self = .upMirrored
        case .down: self = .down
        case .downMirrored: self = .downMirrored
        case .left: self = .left
        case .leftMirrored: self = .leftMirrored
        case .right: self = .right
        case .rightMirrored: self = .rightMirrored
        @unknown default: self = .up
        }
    }
}
