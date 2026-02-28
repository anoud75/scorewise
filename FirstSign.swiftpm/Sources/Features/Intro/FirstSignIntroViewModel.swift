import Foundation
import SwiftUI

@MainActor
final class FirstSignIntroViewModel: ObservableObject {
    @Published var isWindowVisible = true

    let model: FirstSignIntroModel

    init(model: FirstSignIntroModel = .sample) {
        self.model = model
    }

    func didTapInstall() {
        // Navigation is handled by the app flow view model.
    }

    func didTapClose() {
        withAnimation(.easeInOut(duration: 0.2)) {
            isWindowVisible = false
        }
    }
}
