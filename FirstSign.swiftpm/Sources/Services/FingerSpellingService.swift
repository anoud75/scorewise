import Foundation

struct FingerSpellingToken: Identifiable {
    let id: String
    let value: String
    let assetName: String?
}

enum FingerSpellingService {
    static func normalizedObjectLabel(from raw: String) -> String {
        let first = raw.split(separator: ",").first.map(String.init) ?? raw
        return first.replacingOccurrences(of: "_", with: " ").trimmingCharacters(in: .whitespacesAndNewlines)
    }

    static func tokens(for text: String) -> [FingerSpellingToken] {
        let letters = Array(text.uppercased()).filter { $0.isLetter || $0.isNumber || $0 == " " }
        return letters.enumerated().compactMap { index, character in
            if character == " " {
                return FingerSpellingToken(id: "\(index)-space", value: "/", assetName: nil)
            }

            let value = String(character)
            let asset = "fingerspell-\(value.lowercased())"
            return FingerSpellingToken(id: "\(index)-\(value)", value: value, assetName: asset)
        }
    }

    static func displayText(from tokens: [FingerSpellingToken]) -> String {
        tokens.map(\.value).joined(separator: " ")
    }
}
