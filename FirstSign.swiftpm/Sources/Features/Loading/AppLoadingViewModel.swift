import Foundation
import SwiftUI

@MainActor
final class AppLoadingViewModel: ObservableObject {
    @Published private(set) var filledSegments = 0
    @Published private(set) var didFinishLoading = false
    let totalSegments = 16
    var onLoadingFinished: (() -> Void)?

    private var isAnimating = false

    func startLoadingAnimation() {
        guard !isAnimating else { return }
        isAnimating = true
        filledSegments = 0
        didFinishLoading = false

        Task { @MainActor in
            for index in 1...totalSegments {
                try? await Task.sleep(nanoseconds: 150_000_000)
                withAnimation(.linear(duration: 0.08)) {
                    filledSegments = index
                }
            }
            isAnimating = false
            didFinishLoading = true
            onLoadingFinished?()
        }
    }
}
