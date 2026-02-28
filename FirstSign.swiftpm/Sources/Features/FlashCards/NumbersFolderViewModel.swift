import Foundation

struct NumberCardItem: Identifiable, Equatable {
    let id: String
    let title: String
    let assetName: String
}

@MainActor
final class NumbersFolderViewModel: ObservableObject {
    @Published var selectedCard: NumberCardItem?
    @Published var scrollTargetIndex = 0

    let columns = 3
    let items: [NumberCardItem] = [
        NumberCardItem(id: "one", title: "one", assetName: "numbers-card-one"),
        NumberCardItem(id: "two", title: "two", assetName: "numbers-card-two"),
        NumberCardItem(id: "three", title: "three", assetName: "numbers-card-three"),
        NumberCardItem(id: "four", title: "four", assetName: "numbers-card-four"),
        NumberCardItem(id: "five", title: "five", assetName: "numbers-card-five"),
        NumberCardItem(id: "six", title: "six", assetName: "numbers-card-six"),
        NumberCardItem(id: "seven", title: "seven", assetName: "numbers-card-seven"),
        NumberCardItem(id: "eight", title: "eight", assetName: "numbers-card-eight"),
        NumberCardItem(id: "nine", title: "nine", assetName: "numbers-card-nine"),
        NumberCardItem(id: "ten", title: "ten", assetName: "numbers-card-ten"),
        NumberCardItem(id: "eleven", title: "eleven", assetName: "numbers-card-eleven"),
        NumberCardItem(id: "twelve", title: "twelve", assetName: "numbers-card-twelve"),
        NumberCardItem(id: "thirteen", title: "thirteen", assetName: "numbers-card-thirteen"),
        NumberCardItem(id: "fourteen", title: "fourteen", assetName: "numbers-card-fourteen"),
        NumberCardItem(id: "fifteen", title: "fifteen", assetName: "numbers-card-fifteen"),
        NumberCardItem(id: "sixteen", title: "sixteen", assetName: "numbers-card-sixteen"),
        NumberCardItem(id: "seventeen", title: "seventeen", assetName: "numbers-card-seventeen"),
        NumberCardItem(id: "eighteen", title: "eighteen", assetName: "numbers-card-eighteen"),
        NumberCardItem(id: "nineteen", title: "nineteen", assetName: "numbers-card-nineteen"),
        NumberCardItem(id: "twenty", title: "twenty", assetName: "numbers-card-twenty")
    ]

    private var lastRowStartIndex: Int {
        max(0, ((items.count - 1) / columns) * columns)
    }

    func openCard(_ card: NumberCardItem) {
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
