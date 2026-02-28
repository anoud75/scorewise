import SwiftUI

@main
struct FirstSignApp: App {
    @StateObject private var viewModel = AppFlowViewModel()

    var body: some Scene {
        WindowGroup {
            AppFlowRootView(viewModel: viewModel)
        }
    }
}

private struct AppFlowRootView: View {
    @ObservedObject var viewModel: AppFlowViewModel

    var body: some View {
        switch viewModel.currentScreen {
        case .intro:
            FirstSignIntroView(
                viewModel: viewModel.introViewModel,
                onInstall: viewModel.showLoadingScreen
            )
        case .loading:
            AppLoadingView(viewModel: viewModel.loadingViewModel)
        case .desktop:
            MainDesktopView(viewModel: viewModel.desktopViewModel)
        }
    }
}
