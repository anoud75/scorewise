import Foundation

struct MonthCardItem: Identifiable, Equatable {
    let id: String
    let title: String
    let assetName: String
}

@MainActor
final class MonthsFolderViewModel: ObservableObject {
    @Published var selectedCard: MonthCardItem?
    @Published var scrollTargetIndex = 0

    let columns = 2
    let items: [MonthCardItem] = [
        MonthCardItem(id: "january", title: "January", assetName: "months-card-january"),
        MonthCardItem(id: "february", title: "February", assetName: "months-card-february"),
        MonthCardItem(id: "march", title: "March", assetName: "months-card-march"),
        MonthCardItem(id: "april", title: "April", assetName: "months-card-april"),
        MonthCardItem(id: "may", title: "May", assetName: "months-card-may"),
        MonthCardItem(id: "june", title: "June", assetName: "months-card-june"),
        MonthCardItem(id: "july", title: "July", assetName: "months-card-july"),
        MonthCardItem(id: "august", title: "August", assetName: "months-card-august"),
        MonthCardItem(id: "september", title: "September", assetName: "months-card-september"),
        MonthCardItem(id: "october", title: "October", assetName: "months-card-october"),
        MonthCardItem(id: "november", title: "November", assetName: "months-card-november"),
        MonthCardItem(id: "december", title: "December", assetName: "months-card-december")
    ]

    private var lastRowStartIndex: Int {
        max(0, ((items.count - 1) / columns) * columns)
    }

    func openCard(_ card: MonthCardItem) {
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
