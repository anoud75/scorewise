import SwiftUI
import UIKit

struct WeatherFolderView: View {
    @ObservedObject var viewModel: WeatherFolderViewModel
    let onClose: () -> Void

    var body: some View {
        ZStack {
            baseWindow

            VStack(spacing: 0) {
                titleBar
                    .frame(height: 56)

                contentArea

                scrollBar
                    .frame(height: 20)
            }
        }
        .overlay {
            if let selectedCard = viewModel.selectedCard {
                cardPreviewOverlay(selectedCard)
            }
        }
    }

    private var baseWindow: some View {
        Group {
            if let image = AssetImageLoader.image(named: "weather-window-base") {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
            } else {
                Rectangle()
                    .fill(Color(red: 0.72, green: 0.72, blue: 0.72))
                    .overlay(
                        Rectangle()
                            .stroke(Color.black, lineWidth: 4)
                    )
                    .overlay(alignment: .top) {
                        Rectangle()
                            .fill(Color.white.opacity(0.85))
                            .frame(height: 7)
                    }
            }
        }
        .clipped()
    }

    private var titleBar: some View {
        ZStack {
            if let image = AssetImageLoader.image(named: "weather-title-bar") {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
            } else {
                Rectangle().fill(Color(red: 0.09, green: 0.04, blue: 0.83))
            }

            HStack(spacing: 10) {
                if let icon = AssetImageLoader.image(named: "weather-title-icon") {
                    Image(uiImage: icon)
                        .resizable()
                        .scaledToFit()
                        .frame(width: 36, height: 36)
                }

                Text("Weather")
                    .font(.system(size: 18, weight: .regular, design: .monospaced))
                    .foregroundStyle(.white)

                Spacer()

                Button(action: onClose) {
                    if let closeImage = AssetImageLoader.image(named: "weather-close-button") {
                        Image(uiImage: closeImage)
                            .resizable()
                            .scaledToFit()
                            .frame(width: 46, height: 46)
                    } else {
                        Rectangle()
                            .fill(Color(red: 0.82, green: 0.84, blue: 0.86))
                            .frame(width: 40, height: 40)
                            .overlay(
                                Image(systemName: "xmark")
                                    .font(.system(size: 24, weight: .regular))
                                    .foregroundStyle(.black)
                            )
                            .overlay(
                                Rectangle()
                                    .stroke(Color.black, lineWidth: 2)
                            )
                    }
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 14)
        }
    }

    private var contentArea: some View {
        ScrollViewReader { proxy in
            ScrollView(.vertical, showsIndicators: true) {
                LazyVStack(spacing: 14) {
                    ForEach(viewModel.items.indices, id: \.self) { index in
                        let item = viewModel.items[index]
                        Button {
                            viewModel.openCard(item)
                        } label: {
                            weatherCard(item)
                                .id(index)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 14)
            }
            .background(Color(red: 0.72, green: 0.72, blue: 0.72))
            .onChange(of: viewModel.scrollTargetIndex) { _, newValue in
                withAnimation(.easeInOut(duration: 0.2)) {
                    proxy.scrollTo(newValue, anchor: .top)
                }
            }
        }
    }

    private var scrollBar: some View {
        ZStack {
            if let image = AssetImageLoader.image(named: "weather-scroll-bar") {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
            } else {
                HStack(spacing: 2) {
                    Rectangle().fill(Color.gray).frame(width: 24)
                    Rectangle().fill(Color(red: 0.7, green: 0.7, blue: 0.7))
                    Rectangle().fill(Color(red: 0.7, green: 0.7, blue: 0.7))
                    Rectangle().fill(Color.gray).frame(width: 24)
                }
                .overlay(
                    Rectangle()
                        .stroke(Color.black, lineWidth: 2)
                )
            }
        }
        .overlay {
            GeometryReader { geo in
                let arrowWidth: CGFloat = 32

                HStack(spacing: 0) {
                    Button(action: viewModel.scrollBackward) {
                        Color.clear
                    }
                    .buttonStyle(.plain)
                    .frame(width: arrowWidth)

                    Color.clear
                        .contentShape(Rectangle())
                        .gesture(
                            DragGesture(minimumDistance: 0)
                                .onChanged { value in
                                    let usableWidth = max(1, geo.size.width - (arrowWidth * 2))
                                    let x = min(max(0, value.location.x - arrowWidth), usableWidth)
                                    viewModel.updateScrollFromRatio(x / usableWidth)
                                }
                        )

                    Button(action: viewModel.scrollForward) {
                        Color.clear
                    }
                    .buttonStyle(.plain)
                    .frame(width: arrowWidth)
                }
            }
        }
    }

    private func weatherCard(_ item: WeatherCardItem) -> some View {
        Group {
            if let image = AssetImageLoader.image(named: item.assetName) {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFit()
            } else {
                RoundedRectangle(cornerRadius: 16)
                    .fill(Color.white)
                    .overlay(
                        Text(item.title)
                            .font(.system(size: 18, weight: .bold, design: .monospaced))
                            .foregroundStyle(.black)
                    )
            }
        }
        .frame(maxWidth: .infinity)
        .aspectRatio(3.23, contentMode: .fit)
    }

    private func cardPreviewOverlay(_ item: WeatherCardItem) -> some View {
        ZStack(alignment: .topTrailing) {
            Color.black.opacity(0.75)
                .ignoresSafeArea()
                .onTapGesture {
                    viewModel.closeCardPreview()
                }

            VStack(spacing: 0) {
                HStack {
                    Spacer()
                    Button(action: viewModel.closeCardPreview) {
                        if let closeImage = AssetImageLoader.image(named: "weather-close-button") {
                            Image(uiImage: closeImage)
                                .resizable()
                                .scaledToFit()
                                .frame(width: 52, height: 52)
                        } else {
                            Image(systemName: "xmark.circle.fill")
                                .font(.system(size: 40, weight: .regular))
                                .foregroundStyle(.white)
                        }
                    }
                    .buttonStyle(.plain)
                }
                .padding(.top, 18)
                .padding(.horizontal, 18)

                Spacer()

                Group {
                    if let image = AssetImageLoader.image(named: item.assetName) {
                        Image(uiImage: image)
                            .resizable()
                            .scaledToFit()
                    } else {
                        RoundedRectangle(cornerRadius: 20)
                            .fill(Color.white)
                            .overlay(
                                Text(item.title)
                                    .font(.system(size: 44, weight: .bold, design: .monospaced))
                                    .foregroundStyle(.black)
                            )
                    }
                }
                .frame(maxWidth: 900, maxHeight: 560)
                .padding(.horizontal, 24)

                Spacer()
            }
        }
        .transition(.opacity)
    }
}

#Preview {
    WeatherFolderView(viewModel: WeatherFolderViewModel(), onClose: {})
}
