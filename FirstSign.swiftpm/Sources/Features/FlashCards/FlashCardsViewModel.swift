import Foundation

struct FlashCardFolderItem: Identifiable, Equatable {
    let id: String
    let title: String
    let assetName: String
}

@MainActor
final class FlashCardsViewModel: ObservableObject {
    @Published var selectedFolderID: String?

    let folders: [FlashCardFolderItem] = [
        FlashCardFolderItem(id: "colors", title: "Colors", assetName: "flashcards-folder-colors"),
        FlashCardFolderItem(id: "emotions", title: "Emotions", assetName: "flashcards-folder-emotions"),
        FlashCardFolderItem(id: "weather", title: "Weather", assetName: "flashcards-folder-weather"),
        FlashCardFolderItem(id: "numbers", title: "Numbers", assetName: "flashcards-folder-numbers"),
        FlashCardFolderItem(id: "months", title: "Months", assetName: "flashcards-folder-months")
    ]

    func didTapFolder(_ folder: FlashCardFolderItem) {
        selectedFolderID = folder.id
    }
}
