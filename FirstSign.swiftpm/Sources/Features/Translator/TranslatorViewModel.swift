import Foundation

struct FingerspellKeyboardKey: Identifiable, Equatable {
    let letter: String
    var id: String { letter }
}

enum TranslatorMode: String {
    case englishToFingerspell
    case fingerspellToEnglish

    var title: String {
        switch self {
        case .englishToFingerspell:
            return "English -> Fingerspell"
        case .fingerspellToEnglish:
            return "Fingerspell -> English"
        }
    }
}

@MainActor
final class TranslatorViewModel: ObservableObject {
    @Published var mode: TranslatorMode = .englishToFingerspell
    @Published var englishInput = ""
    @Published var fingerspellLetters: [String] = []

    let keys: [FingerspellKeyboardKey] = (0..<26).map {
        let scalar = UnicodeScalar(65 + $0)!
        return FingerspellKeyboardKey(letter: String(Character(scalar)))
    }

    var englishToFingerspellTokens: [FingerSpellingToken] {
        FingerSpellingService.tokens(for: sanitizedEnglishInput)
    }

    var fingerspellToEnglishText: String {
        fingerspellLetters.joined()
    }

    var sanitizedEnglishInput: String {
        englishInput
            .map { character in
                if character.isLetter {
                    return String(character)
                }
                if character.isWhitespace {
                    return " "
                }
                return ""
            }
            .joined()
    }

    func updateEnglishInput(_ value: String) {
        englishInput = value
    }

    func toggleMode() {
        mode = (mode == .englishToFingerspell) ? .fingerspellToEnglish : .englishToFingerspell
    }

    func appendFingerLetter(_ letter: String) {
        guard letter.count == 1 else { return }
        fingerspellLetters.append(letter.uppercased())
    }

    func appendSpace() {
        guard fingerspellLetters.last != " " else { return }
        fingerspellLetters.append(" ")
    }

    func backspace() {
        guard !fingerspellLetters.isEmpty else { return }
        fingerspellLetters.removeLast()
    }

    func clearFingerspellInput() {
        fingerspellLetters = []
    }
}
