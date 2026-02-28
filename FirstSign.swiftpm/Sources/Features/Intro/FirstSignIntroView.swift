import SwiftUI
import UIKit

struct FirstSignIntroView: View {
    @ObservedObject var viewModel: FirstSignIntroViewModel
    let onInstall: () -> Void

    var body: some View {
        GeometryReader { proxy in
            let windowSize = introWindowSize(for: proxy.size)

            ZStack {
                BackgroundImageView()
                    .ignoresSafeArea()

                if viewModel.isWindowVisible {
                    ZStack {
                        if let image = AssetImageLoader.image(named: "intro-window-base")
                            ?? AssetImageLoader.image(named: "First sign 1") {
                            Image(uiImage: image)
                                .resizable()
                                .interpolation(.none)
                                .antialiased(false)
                                .scaledToFit()
                        } else {
                            PixelWindowCard(title: viewModel.model.windowTitle) {
                                viewModel.didTapClose()
                            } content: {
                                Color(red: 0.94, green: 0.94, blue: 0.94)
                            }
                        }
                    }
                    .frame(width: windowSize.width, height: windowSize.height)
                    .overlay {
                        introInteractiveLayer
                    }
                    .transition(.opacity.combined(with: .scale(scale: 0.95)))
                }
            }
        }
    }

    private func introWindowSize(for screen: CGSize) -> CGSize {
        let designRatio: CGFloat = 777.0 / 779.0
        let maxWidth = min(screen.width - 20, 777)
        var width = maxWidth
        var height = width / designRatio
        let maxHeight = screen.height - 20

        if height > maxHeight {
            height = maxHeight
            width = height * designRatio
        }

        return CGSize(width: width, height: height)
    }

    private var introInteractiveLayer: some View {
        GeometryReader { geo in
            let width = geo.size.width
            let height = geo.size.height

            ZStack {
                Button(action: viewModel.didTapClose) {
                    Color.clear
                }
                .buttonStyle(.plain)
                .frame(width: width * 0.08, height: height * 0.08)
                .contentShape(Rectangle())
                .position(x: width * 0.948, y: height * 0.057)

                IntroInstallOverlayButton(onTap: {
                    viewModel.didTapInstall()
                    onInstall()
                })
                .frame(width: width * 0.234, height: height * 0.065)
                .position(x: width * 0.835, y: height * 0.906)
            }
        }
    }
}

private struct IntroInstallOverlayButton: View {
    let onTap: () -> Void
    @GestureState private var isPressed = false

    var body: some View {
        Button(action: onTap) {
            Group {
                if let image = AssetImageLoader.image(named: "intro-install-button")
                    ?? AssetImageLoader.image(named: "install button") {
                    Image(uiImage: image)
                        .resizable()
                        .interpolation(.none)
                        .antialiased(false)
                        .scaledToFit()
                } else {
                    Rectangle()
                        .fill(Color.gray.opacity(0.35))
                        .overlay(
                            Rectangle()
                                .stroke(Color.black, lineWidth: 3)
                        )
                }
            }
            .modifier(WarpedPressEffect(pressed: isPressed))
            .animation(.easeOut(duration: 0.12), value: isPressed)
        }
        .buttonStyle(.plain)
        .simultaneousGesture(
            DragGesture(minimumDistance: 0)
                .updating($isPressed) { _, state, _ in
                    state = true
                }
        )
    }
}

private struct BackgroundImageView: View {
    var body: some View {
        if let image = AssetImageLoader.image(named: "background-meadow")
            ?? AssetImageLoader.image(named: "background") {
            Image(uiImage: image)
                .resizable()
                .scaledToFill()
        } else {
            LinearGradient(
                colors: [
                    Color(red: 0.82, green: 0.9, blue: 0.78),
                    Color(red: 0.47, green: 0.65, blue: 0.42)
                ],
                startPoint: .top,
                endPoint: .bottom
            )
        }
    }
}

#Preview {
    FirstSignIntroView(viewModel: FirstSignIntroViewModel(), onInstall: {})
}
