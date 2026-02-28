import Foundation

struct WeatherCardItem: Identifiable, Equatable {
    let id: String
    let title: String
    let assetName: String
}

@MainActor
final class WeatherFolderViewModel: ObservableObject {
    @Published var selectedCard: WeatherCardItem?
    @Published var scrollTargetIndex = 0

    let items: [WeatherCardItem] = [
        WeatherCardItem(id: "sunny", title: "sunny", assetName: "weather-card-sunny"),
        WeatherCardItem(id: "rainy", title: "rainy", assetName: "weather-card-rainy"),
        WeatherCardItem(id: "snowy", title: "snowy", assetName: "weather-card-snowy"),
        WeatherCardItem(id: "windy", title: "windy", assetName: "weather-card-windy"),
        WeatherCardItem(id: "cloudy", title: "cloudy", assetName: "weather-card-cloudy")
    ]

    private var lastIndex: Int {
        max(0, items.count - 1)
    }

    func openCard(_ card: WeatherCardItem) {
        selectedCard = card
    }

    func closeCardPreview() {
        selectedCard = nil
    }

    func scrollBackward() {
        scrollTargetIndex = max(0, scrollTargetIndex - 1)
    }

    func scrollForward() {
        scrollTargetIndex = min(lastIndex, scrollTargetIndex + 1)
    }

    func updateScrollFromRatio(_ ratio: Double) {
        let clamped = min(max(ratio, 0), 1)
        scrollTargetIndex = Int((Double(lastIndex) * clamped).rounded())
    }
}
