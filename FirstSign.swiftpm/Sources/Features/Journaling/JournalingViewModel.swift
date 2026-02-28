import Foundation
import SwiftUI

@MainActor
final class JournalingViewModel: ObservableObject {
    @Published var englishText = ""

    var fingerspellingTokens: [FingerSpellingToken] {
        FingerSpellingService.tokens(for: englishText)
    }

    var hasInput: Bool {
        !englishText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    func clear() {
        englishText = ""
    }
}
