import Foundation

struct EmotionCardItem: Identifiable, Equatable {
    let id: String
    let title: String
    let assetName: String
}

@MainActor
final class EmotionsFolderViewModel: ObservableObject {
    @Published var selectedCard: EmotionCardItem?
    @Published var scrollTargetIndex = 0

    let columns = 2
    let items: [EmotionCardItem] = [
        EmotionCardItem(id: "happy", title: "happy", assetName: "emotions-card-happy"),
        EmotionCardItem(id: "shy", title: "shy", assetName: "emotions-card-shy"),
        EmotionCardItem(id: "surprised", title: "surprised", assetName: "emotions-card-surprised"),
        EmotionCardItem(id: "sad", title: "sad", assetName: "emotions-card-sad"),
        EmotionCardItem(id: "mad", title: "mad", assetName: "emotions-card-mad"),
        EmotionCardItem(id: "upset", title: "upset", assetName: "emotions-card-upset"),
        EmotionCardItem(id: "confused", title: "confused", assetName: "emotions-card-confused"),
        EmotionCardItem(id: "hurt", title: "hurt", assetName: "emotions-card-hurt"),
        EmotionCardItem(id: "excited", title: "excited", assetName: "emotions-card-excited"),
        EmotionCardItem(id: "laughter", title: "laughter", assetName: "emotions-card-laughter"),
        EmotionCardItem(id: "love", title: "love", assetName: "emotions-card-love"),
        EmotionCardItem(id: "scared", title: "scared", assetName: "emotions-card-scared"),
        EmotionCardItem(id: "embarrassed", title: "embarrassed", assetName: "emotions-card-embarrassed"),
        EmotionCardItem(id: "nervous", title: "nervous", assetName: "emotions-card-nervous"),
        EmotionCardItem(id: "bored", title: "bored", assetName: "emotions-card-bored")
    ]

    private var lastRowStartIndex: Int {
        max(0, ((items.count - 1) / columns) * columns)
    }

    func openCard(_ card: EmotionCardItem) {
        selectedCard = card
    }

    func closeCardPreview() {
        selectedCard = nil
    }

    func scrollBackward() {
        scrollTargetIndex = max(0, scrollTargetIndex - columns)
    }

    func scrollForward() {
        scrollTargetIndex = min(lastRowStartIndex, scrollTargetIndex + columns)
    }

    func updateScrollFromRatio(_ ratio: Double) {
        let clamped = min(max(ratio, 0), 1)
        let rowCount = max(1, (items.count + columns - 1) / columns)
        let row = Int((Double(rowCount - 1) * clamped).rounded())
        scrollTargetIndex = min(lastRowStartIndex, max(0, row * columns))
    }
}
