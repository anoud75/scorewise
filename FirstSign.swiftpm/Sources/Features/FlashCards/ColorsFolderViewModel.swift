import Foundation

struct ColorCardItem: Identifiable, Equatable {
    let id: String
    let title: String
    let assetName: String
}

@MainActor
final class ColorsFolderViewModel: ObservableObject {
    @Published var selectedCard: ColorCardItem?
    @Published var scrollTargetIndex = 0

    let columns = 2
    let items: [ColorCardItem] = [
        ColorCardItem(id: "pink", title: "pink", assetName: "colors-card-pink"),
        ColorCardItem(id: "green", title: "green", assetName: "colors-card-green"),
        ColorCardItem(id: "orange", title: "orange", assetName: "colors-card-orange"),
        ColorCardItem(id: "yellow", title: "yellow", assetName: "colors-card-yellow"),
        ColorCardItem(id: "tan", title: "tan", assetName: "colors-card-tan"),
        ColorCardItem(id: "gray", title: "gray", assetName: "colors-card-gray"),
        ColorCardItem(id: "red", title: "red", assetName: "colors-card-red"),
        ColorCardItem(id: "blue", title: "blue", assetName: "colors-card-blue"),
        ColorCardItem(id: "brown", title: "brown", assetName: "colors-card-brown"),
        ColorCardItem(id: "black", title: "black", assetName: "colors-card-black"),
        ColorCardItem(id: "white", title: "white", assetName: "colors-card-white"),
        ColorCardItem(id: "purple", title: "purple", assetName: "colors-card-purple")
    ]

    private var lastRowStartIndex: Int {
        max(0, ((items.count - 1) / columns) * columns)
    }

    func openCard(_ card: ColorCardItem) {
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
