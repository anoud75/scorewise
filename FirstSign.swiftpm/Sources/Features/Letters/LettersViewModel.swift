import Foundation
import SwiftUI

struct LetterCardItem: Identifiable, Equatable {
    let id: String
    let letter: String
    let assetName: String
}

@MainActor
final class LettersViewModel: ObservableObject {
    let items: [LetterCardItem] = (0..<26).map { offset in
        let scalar = UnicodeScalar(65 + offset)!
        let letter = String(Character(scalar))
        return LetterCardItem(
            id: letter.lowercased(),
            letter: letter,
            assetName: "letters-card-\(letter.lowercased())"
        )
    }
}
