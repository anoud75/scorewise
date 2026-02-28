import CoreGraphics

enum DesktopIconID: String, CaseIterable, Identifiable {
    case myComputer
    case letters
    case translator
    case about
    case explorer
    case journaling
    case flashcards
    case messages
    case trash

    var id: String { rawValue }
}

struct DesktopIconItem: Identifiable {
    let id: DesktopIconID
    let label: String
    let assetName: String
    let normalizedFrame: CGRect
    let isInteractive: Bool
}

extension DesktopIconItem {
    static let desktopIcons: [DesktopIconItem] = [
        DesktopIconItem(
            id: .myComputer,
            label: "My Computer",
            assetName: "desktop-icon-my-computer",
            normalizedFrame: CGRect(x: 0.84, y: 0.07, width: 0.13, height: 0.11),
            isInteractive: false
        ),
        DesktopIconItem(
            id: .letters,
            label: "Dictionary",
            assetName: "desktop-icon-letters",
            normalizedFrame: CGRect(x: 0.73, y: 0.20, width: 0.10, height: 0.10),
            isInteractive: true
        ),
        DesktopIconItem(
            id: .translator,
            label: "Translator",
            assetName: "desktop-icon-translator",
            normalizedFrame: CGRect(x: 0.86, y: 0.20, width: 0.12, height: 0.10),
            isInteractive: true
        ),
        DesktopIconItem(
            id: .about,
            label: "About",
            assetName: "desktop-icon-about",
            normalizedFrame: CGRect(x: 0.73, y: 0.31, width: 0.10, height: 0.12),
            isInteractive: true
        ),
        DesktopIconItem(
            id: .explorer,
            label: "Explorer",
            assetName: "desktop-icon-explorer",
            normalizedFrame: CGRect(x: 0.86, y: 0.31, width: 0.12, height: 0.10),
            isInteractive: true
        ),
        DesktopIconItem(
            id: .journaling,
            label: "Journaling",
            assetName: "desktop-icon-journaling",
            normalizedFrame: CGRect(x: 0.86, y: 0.43, width: 0.11, height: 0.13),
            isInteractive: true
        ),
        DesktopIconItem(
            id: .flashcards,
            label: "FlashCards",
            assetName: "desktop-icon-flashcards",
            normalizedFrame: CGRect(x: 0.86, y: 0.55, width: 0.12, height: 0.10),
            isInteractive: true
        ),
        DesktopIconItem(
            id: .messages,
            label: "messages",
            assetName: "desktop-icon-messages",
            normalizedFrame: CGRect(x: 0.86, y: 0.65, width: 0.12, height: 0.08),
            isInteractive: false
        ),
        DesktopIconItem(
            id: .trash,
            label: "Trash",
            assetName: "desktop-icon-trash",
            normalizedFrame: CGRect(x: 0.86, y: 0.76, width: 0.12, height: 0.13),
            isInteractive: false
        )
    ]
}
