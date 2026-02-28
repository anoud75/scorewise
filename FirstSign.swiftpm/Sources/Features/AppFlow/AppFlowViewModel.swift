import Foundation
import SwiftUI

@MainActor
final class AppFlowViewModel: ObservableObject {
    enum Screen {
        case intro
        case loading
        case desktop
    }

    @Published var currentScreen: Screen = .intro

    let introViewModel: FirstSignIntroViewModel
    let loadingViewModel: AppLoadingViewModel
    let desktopViewModel: MainDesktopViewModel

    init() {
        introViewModel = FirstSignIntroViewModel()
        loadingViewModel = AppLoadingViewModel()
        desktopViewModel = MainDesktopViewModel()

        loadingViewModel.onLoadingFinished = { [weak self] in
            self?.showDesktopScreen()
        }
    }

    func showLoadingScreen() {
        withAnimation(.easeInOut(duration: 0.2)) {
            currentScreen = .loading
        }
        loadingViewModel.startLoadingAnimation()
    }

    private func showDesktopScreen() {
        withAnimation(.easeInOut(duration: 0.2)) {
            currentScreen = .desktop
        }
    }
}
