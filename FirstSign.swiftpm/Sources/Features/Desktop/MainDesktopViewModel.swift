import Foundation
import SwiftUI

@MainActor
final class MainDesktopViewModel: ObservableObject {
    @Published var isMyComputerWindowVisible = true
    @Published var isA1UlaWindowVisible = true
    @Published var isAboutWindowVisible = false
    @Published var isFlashCardsWindowVisible = false
    @Published var isColorsFolderWindowVisible = false
    @Published var isEmotionsFolderWindowVisible = false
    @Published var isWeatherFolderWindowVisible = false
    @Published var isMonthsFolderWindowVisible = false
    @Published var isNumbersFolderWindowVisible = false
    @Published var isExplorerWindowVisible = false
    @Published var isTranslatorWindowVisible = false
    @Published var isLettersWindowVisible = false
    @Published var isJournalingWindowVisible = false
    @Published var selectedIcon: DesktopIconID?

    let icons: [DesktopIconItem]
    let aboutViewModel: AboutViewModel
    let flashCardsViewModel: FlashCardsViewModel
    let colorsFolderViewModel: ColorsFolderViewModel
    let emotionsFolderViewModel: EmotionsFolderViewModel
    let weatherFolderViewModel: WeatherFolderViewModel
    let monthsFolderViewModel: MonthsFolderViewModel
    let numbersFolderViewModel: NumbersFolderViewModel
    let explorerViewModel: ExplorerViewModel
    let translatorViewModel: TranslatorViewModel
    let lettersViewModel: LettersViewModel
    let journalingViewModel: JournalingViewModel

    init(
        icons: [DesktopIconItem] = DesktopIconItem.desktopIcons,
        aboutViewModel: AboutViewModel? = nil,
        flashCardsViewModel: FlashCardsViewModel? = nil,
        colorsFolderViewModel: ColorsFolderViewModel? = nil,
        emotionsFolderViewModel: EmotionsFolderViewModel? = nil,
        weatherFolderViewModel: WeatherFolderViewModel? = nil,
        monthsFolderViewModel: MonthsFolderViewModel? = nil,
        numbersFolderViewModel: NumbersFolderViewModel? = nil,
        explorerViewModel: ExplorerViewModel? = nil,
        translatorViewModel: TranslatorViewModel? = nil,
        lettersViewModel: LettersViewModel? = nil,
        journalingViewModel: JournalingViewModel? = nil
    ) {
        self.icons = icons
        self.aboutViewModel = aboutViewModel ?? AboutViewModel()
        self.flashCardsViewModel = flashCardsViewModel ?? FlashCardsViewModel()
        self.colorsFolderViewModel = colorsFolderViewModel ?? ColorsFolderViewModel()
        self.emotionsFolderViewModel = emotionsFolderViewModel ?? EmotionsFolderViewModel()
        self.weatherFolderViewModel = weatherFolderViewModel ?? WeatherFolderViewModel()
        self.monthsFolderViewModel = monthsFolderViewModel ?? MonthsFolderViewModel()
        self.numbersFolderViewModel = numbersFolderViewModel ?? NumbersFolderViewModel()
        self.explorerViewModel = explorerViewModel ?? ExplorerViewModel()
        self.translatorViewModel = translatorViewModel ?? TranslatorViewModel()
        self.lettersViewModel = lettersViewModel ?? LettersViewModel()
        self.journalingViewModel = journalingViewModel ?? JournalingViewModel()
    }

    func handleIconTap(_ iconID: DesktopIconID) {
        guard icons.first(where: { $0.id == iconID })?.isInteractive == true else { return }
        selectedIcon = selectedIcon == iconID ? nil : iconID
        if iconID == .about {
            isAboutWindowVisible = true
        } else if iconID == .letters {
            isLettersWindowVisible = true
        } else if iconID == .flashcards {
            isFlashCardsWindowVisible = true
        } else if iconID == .explorer {
            isExplorerWindowVisible = true
        } else if iconID == .translator {
            isTranslatorWindowVisible = true
        } else if iconID == .journaling {
            isJournalingWindowVisible = true
        }
    }

    func closeMyComputerWindow() {
        withAnimation(.easeInOut(duration: 0.12)) {
            isMyComputerWindowVisible = false
        }
    }

    func closeA1UlaWindow() {
        withAnimation(.easeInOut(duration: 0.12)) {
            isA1UlaWindowVisible = false
        }
    }

    func closeExplorerWindow() {
        withAnimation(.easeInOut(duration: 0.12)) {
            isExplorerWindowVisible = false
            if selectedIcon == .explorer {
                selectedIcon = nil
            }
        }
    }

    func closeTranslatorWindow() {
        withAnimation(.easeInOut(duration: 0.12)) {
            isTranslatorWindowVisible = false
            if selectedIcon == .translator {
                selectedIcon = nil
            }
        }
    }

    func closeAboutWindow() {
        withAnimation(.easeInOut(duration: 0.12)) {
            isAboutWindowVisible = false
            if selectedIcon == .about {
                selectedIcon = nil
            }
        }
    }

    func closeLettersWindow() {
        withAnimation(.easeInOut(duration: 0.12)) {
            isLettersWindowVisible = false
            if selectedIcon == .letters {
                selectedIcon = nil
            }
        }
    }

    func closeJournalingWindow() {
        withAnimation(.easeInOut(duration: 0.12)) {
            isJournalingWindowVisible = false
            if selectedIcon == .journaling {
                selectedIcon = nil
            }
        }
    }

    func closeFlashCardsWindow() {
        withAnimation(.easeInOut(duration: 0.12)) {
            isFlashCardsWindowVisible = false
            if selectedIcon == .flashcards {
                selectedIcon = nil
            }
        }
    }

    func openColorsFolderWindow() {
        withAnimation(.easeInOut(duration: 0.12)) {
            isColorsFolderWindowVisible = true
        }
    }

    func closeColorsFolderWindow() {
        withAnimation(.easeInOut(duration: 0.12)) {
            isColorsFolderWindowVisible = false
        }
    }

    func openEmotionsFolderWindow() {
        withAnimation(.easeInOut(duration: 0.12)) {
            isEmotionsFolderWindowVisible = true
        }
    }

    func closeEmotionsFolderWindow() {
        withAnimation(.easeInOut(duration: 0.12)) {
            isEmotionsFolderWindowVisible = false
        }
    }

    func openWeatherFolderWindow() {
        withAnimation(.easeInOut(duration: 0.12)) {
            isWeatherFolderWindowVisible = true
        }
    }

    func closeWeatherFolderWindow() {
        withAnimation(.easeInOut(duration: 0.12)) {
            isWeatherFolderWindowVisible = false
        }
    }

    func openMonthsFolderWindow() {
        withAnimation(.easeInOut(duration: 0.12)) {
            isMonthsFolderWindowVisible = true
        }
    }

    func closeMonthsFolderWindow() {
        withAnimation(.easeInOut(duration: 0.12)) {
            isMonthsFolderWindowVisible = false
        }
    }

    func openNumbersFolderWindow() {
        withAnimation(.easeInOut(duration: 0.12)) {
            isNumbersFolderWindowVisible = true
        }
    }

    func closeNumbersFolderWindow() {
        withAnimation(.easeInOut(duration: 0.12)) {
            isNumbersFolderWindowVisible = false
        }
    }

    func openFlashCardsSubfolder(_ folderID: String) {
        switch folderID {
        case "colors":
            openColorsFolderWindow()
        case "emotions":
            openEmotionsFolderWindow()
        case "weather":
            openWeatherFolderWindow()
        case "months":
            openMonthsFolderWindow()
        case "numbers":
            openNumbersFolderWindow()
        default:
            break
        }
    }
}
