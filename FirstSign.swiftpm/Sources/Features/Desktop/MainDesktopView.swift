import SwiftUI
import UIKit

struct MainDesktopView: View {
    @ObservedObject var viewModel: MainDesktopViewModel

    private let myComputerWindowFrame = CGRect(x: 0.175, y: 0.145, width: 0.40, height: 0.15)
    private let a1UlaWindowFrame = CGRect(x: 0.175, y: 0.45, width: 0.33, height: 0.31)
    private let aboutWindowFrame = CGRect(x: 0.05, y: 0.02, width: 0.90, height: 0.94)
    private let lettersWindowFrame = CGRect(x: 0.05, y: 0.02, width: 0.90, height: 0.94)
    private let flashCardsWindowFrame = CGRect(x: 0.18, y: 0.30, width: 0.44, height: 0.39)
    private let colorsFolderWindowFrame = CGRect(x: 0.03, y: 0.02, width: 0.94, height: 0.95)
    private let emotionsFolderWindowFrame = CGRect(x: 0.03, y: 0.02, width: 0.94, height: 0.95)
    private let weatherFolderWindowFrame = CGRect(x: 0.03, y: 0.02, width: 0.94, height: 0.95)
    private let monthsFolderWindowFrame = CGRect(x: 0.03, y: 0.02, width: 0.94, height: 0.95)
    private let numbersFolderWindowFrame = CGRect(x: 0.03, y: 0.02, width: 0.94, height: 0.95)
    private let journalingWindowFrame = CGRect(x: 0.03, y: 0.02, width: 0.94, height: 0.95)
    private let translatorWindowFrame = CGRect(x: 0.17, y: 0.11, width: 0.82, height: 0.79)
    private let explorerWindowFrame = CGRect(x: 0.17, y: 0.11, width: 0.82, height: 0.79)
    private let myComputerCloseRect = CGRect(x: 0.90, y: 0.07, width: 0.07, height: 0.14)
    private let a1UlaCloseRect = CGRect(x: 0.90, y: 0.02, width: 0.08, height: 0.08)

    var body: some View {
        GeometryReader { proxy in
            let taskbarHeight = min(48, max(36, proxy.size.height * 0.028))
            let desktopSize = CGSize(width: proxy.size.width, height: proxy.size.height - taskbarHeight)

            VStack(spacing: 0) {
                ZStack(alignment: .topLeading) {
                    DesktopBackgroundView()

                    if viewModel.isMyComputerWindowVisible {
                        let frame = myComputerWindowFrame.scaled(to: desktopSize)
                        DesktopWindowAssetView(
                            assetName: "desktop-window-my-computer",
                            closeRect: myComputerCloseRect,
                            onClose: viewModel.closeMyComputerWindow
                        )
                        .frame(width: frame.width, height: frame.height)
                        .position(x: frame.midX, y: frame.midY)
                        .transition(.opacity)
                    }

                    if viewModel.isA1UlaWindowVisible {
                        let frame = a1UlaWindowFrame.scaled(to: desktopSize)
                        DesktopWindowAssetView(
                            assetName: "desktop-window-a1ula",
                            closeRect: a1UlaCloseRect,
                            onClose: viewModel.closeA1UlaWindow
                        )
                        .frame(width: frame.width, height: frame.height)
                        .position(x: frame.midX, y: frame.midY)
                        .transition(.opacity)
                    }

                    ForEach(viewModel.icons) { icon in
                        let frame = icon.normalizedFrame.scaled(to: desktopSize)
                        Group {
                            if icon.isInteractive {
                                DesktopIconView(
                                    item: icon,
                                    isSelected: viewModel.selectedIcon == icon.id
                                )
                                .contentShape(Rectangle())
                                .onTapGesture {
                                    viewModel.handleIconTap(icon.id)
                                }
                            } else {
                                DesktopIconView(
                                    item: icon,
                                    isSelected: false
                                )
                            }
                        }
                        .frame(width: frame.width, height: frame.height)
                        .position(x: frame.midX, y: frame.midY)
                    }

                    if viewModel.isExplorerWindowVisible {
                        let frame = explorerWindowFrame.scaled(to: desktopSize)
                        ExplorerView(
                            viewModel: viewModel.explorerViewModel,
                            onClose: viewModel.closeExplorerWindow
                        )
                        .frame(width: frame.width, height: frame.height)
                        .position(x: frame.midX, y: frame.midY)
                        .transition(.opacity)
                    }

                    if viewModel.isTranslatorWindowVisible {
                        let frame = translatorWindowFrame.scaled(to: desktopSize)
                        TranslatorView(
                            viewModel: viewModel.translatorViewModel,
                            onClose: viewModel.closeTranslatorWindow
                        )
                        .frame(width: frame.width, height: frame.height)
                        .position(x: frame.midX, y: frame.midY)
                        .transition(.opacity)
                    }

                    if viewModel.isJournalingWindowVisible {
                        let frame = journalingWindowFrame.scaled(to: desktopSize)
                        JournalingView(
                            viewModel: viewModel.journalingViewModel,
                            onClose: viewModel.closeJournalingWindow
                        )
                        .frame(width: frame.width, height: frame.height)
                        .position(x: frame.midX, y: frame.midY)
                        .transition(.opacity)
                    }

                    if viewModel.isLettersWindowVisible {
                        let frame = lettersWindowFrame.scaled(to: desktopSize)
                        LettersView(
                            viewModel: viewModel.lettersViewModel,
                            onClose: viewModel.closeLettersWindow
                        )
                        .frame(width: frame.width, height: frame.height)
                        .position(x: frame.midX, y: frame.midY)
                        .transition(.opacity)
                    }

                    if viewModel.isFlashCardsWindowVisible {
                        let frame = flashCardsWindowFrame.scaled(to: desktopSize)
                        FlashCardsView(
                            viewModel: viewModel.flashCardsViewModel,
                            onClose: viewModel.closeFlashCardsWindow,
                            onOpenFolder: viewModel.openFlashCardsSubfolder
                        )
                        .frame(width: frame.width, height: frame.height)
                        .position(x: frame.midX, y: frame.midY)
                        .transition(.opacity)
                    }

                    if viewModel.isColorsFolderWindowVisible {
                        let frame = colorsFolderWindowFrame.scaled(to: desktopSize)
                        ColorsFolderView(
                            viewModel: viewModel.colorsFolderViewModel,
                            onClose: viewModel.closeColorsFolderWindow
                        )
                        .frame(width: frame.width, height: frame.height)
                        .position(x: frame.midX, y: frame.midY)
                        .transition(.opacity)
                    }

                    if viewModel.isEmotionsFolderWindowVisible {
                        let frame = emotionsFolderWindowFrame.scaled(to: desktopSize)
                        EmotionsFolderView(
                            viewModel: viewModel.emotionsFolderViewModel,
                            onClose: viewModel.closeEmotionsFolderWindow
                        )
                        .frame(width: frame.width, height: frame.height)
                        .position(x: frame.midX, y: frame.midY)
                        .transition(.opacity)
                    }

                    if viewModel.isWeatherFolderWindowVisible {
                        let frame = weatherFolderWindowFrame.scaled(to: desktopSize)
                        WeatherFolderView(
                            viewModel: viewModel.weatherFolderViewModel,
                            onClose: viewModel.closeWeatherFolderWindow
                        )
                        .frame(width: frame.width, height: frame.height)
                        .position(x: frame.midX, y: frame.midY)
                        .transition(.opacity)
                    }

                    if viewModel.isMonthsFolderWindowVisible {
                        let frame = monthsFolderWindowFrame.scaled(to: desktopSize)
                        MonthsFolderView(
                            viewModel: viewModel.monthsFolderViewModel,
                            onClose: viewModel.closeMonthsFolderWindow
                        )
                        .frame(width: frame.width, height: frame.height)
                        .position(x: frame.midX, y: frame.midY)
                        .transition(.opacity)
                    }

                    if viewModel.isNumbersFolderWindowVisible {
                        let frame = numbersFolderWindowFrame.scaled(to: desktopSize)
                        NumbersFolderView(
                            viewModel: viewModel.numbersFolderViewModel,
                            onClose: viewModel.closeNumbersFolderWindow
                        )
                        .frame(width: frame.width, height: frame.height)
                        .position(x: frame.midX, y: frame.midY)
                        .transition(.opacity)
                    }

                    if viewModel.isAboutWindowVisible {
                        let frame = aboutWindowFrame.scaled(to: desktopSize)
                        AboutView(
                            viewModel: viewModel.aboutViewModel,
                            onClose: viewModel.closeAboutWindow
                        )
                        .frame(width: frame.width, height: frame.height)
                        .position(x: frame.midX, y: frame.midY)
                        .transition(.opacity)
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .clipped()

                DesktopTaskbarView()
                    .frame(height: taskbarHeight)
            }
            .ignoresSafeArea()
        }
    }
}

private struct DesktopBackgroundView: View {
    var body: some View {
        if let image = AssetImageLoader.image(named: "desktop-main-bg") {
            Image(uiImage: image)
                .resizable()
                .scaledToFill()
                .ignoresSafeArea()
        } else {
            LinearGradient(
                colors: [Color(red: 0.32, green: 0.62, blue: 0.98), Color(red: 0.42, green: 0.72, blue: 0.2)],
                startPoint: .top,
                endPoint: .bottom
            )
        }
    }
}

private struct DesktopWindowAssetView: View {
    let assetName: String
    let closeRect: CGRect
    let onClose: () -> Void

    var body: some View {
        ZStack {
            if let image = AssetImageLoader.image(named: assetName) {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .clipped()
            } else {
                Rectangle()
                    .fill(Color(red: 0.72, green: 0.72, blue: 0.72))
                    .overlay(
                        Rectangle()
                            .stroke(Color.black, lineWidth: 3)
                    )
            }
        }
        .overlay {
            GeometryReader { geo in
                Button(action: onClose) {
                    Color.clear
                }
                .buttonStyle(.plain)
                .frame(
                    width: closeRect.width * geo.size.width,
                    height: closeRect.height * geo.size.height
                )
                .position(
                    x: (closeRect.minX + closeRect.width / 2) * geo.size.width,
                    y: (closeRect.minY + closeRect.height / 2) * geo.size.height
                )
            }
        }
    }
}

private struct DesktopIconView: View {
    let item: DesktopIconItem
    let isSelected: Bool

    var body: some View {
        VStack(spacing: 4) {
            Group {
                if item.id == .about {
                    AboutDesktopIconGraphic()
                } else if let image = AssetImageLoader.image(named: item.assetName) {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFit()
                } else {
                    Rectangle()
                        .fill(Color.gray.opacity(0.4))
                        .overlay(
                            Rectangle()
                                .stroke(Color.black, lineWidth: 2)
                        )
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            Text(item.label)
                .font(.system(size: 10, weight: .medium, design: .monospaced))
                .foregroundStyle(.black)
                .lineLimit(1)
                .minimumScaleFactor(0.75)
        }
        .padding(.horizontal, 2)
        .padding(.vertical, 2)
        .background(
            isSelected
            ? Color(red: 0.16, green: 0.3, blue: 0.85).opacity(0.4)
            : Color.clear
        )
        .overlay(
            Rectangle()
                .stroke(
                    isSelected ? Color(red: 0.13, green: 0.23, blue: 0.75) : Color.clear,
                    lineWidth: 1
                )
        )
    }
}

private struct AboutDesktopIconGraphic: View {
    var body: some View {
        ZStack(alignment: .topLeading) {
            if let image = AssetImageLoader.image(named: "desktop-icon-about") {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFit()
                    .padding(.top, 4)
                    .padding(.trailing, 4)
            } else {
                ZStack(alignment: .bottomLeading) {
                    Ellipse()
                        .fill(.white)
                        .overlay(
                            Ellipse()
                                .stroke(Color.black, lineWidth: 2)
                        )

                    TriangleTail()
                        .fill(.white)
                        .overlay(
                            TriangleTail()
                                .stroke(Color.black, lineWidth: 2)
                        )
                        .frame(width: 18, height: 12)
                        .offset(x: 18, y: 5)

                    Text("i")
                        .font(.system(size: 42, weight: .bold, design: .serif))
                        .foregroundStyle(Color(red: 0.16, green: 0.16, blue: 0.88))
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .offset(y: -3)
                }
                .padding(.top, 4)
                .padding(.trailing, 4)
            }

            Circle()
                .fill(Color(red: 0.92, green: 0.13, blue: 0.15))
                .frame(width: 28, height: 28)
                .overlay(
                    Text("1")
                        .font(.system(size: 14, weight: .bold, design: .monospaced))
                        .foregroundStyle(.white)
                )
                .offset(x: -2, y: -2)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

private struct TriangleTail: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.midX, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.minX, y: rect.minY))
        path.closeSubpath()
        return path
    }
}

private struct DesktopTaskbarView: View {
    var body: some View {
        HStack(spacing: 4) {
            TaskbarButton(title: "Start", icon: "sparkles")
                .frame(width: 84)

            TaskbarTab(title: "Minesweeper")
                .frame(width: 148)

            TaskbarTab(title: "Internet Explorer")
                .frame(maxWidth: 270)

            TaskbarTab(title: "CD Player")
                .frame(maxWidth: 150)

            Spacer(minLength: 4)

            TaskbarClock()
                .frame(width: 94)
        }
        .padding(.horizontal, 4)
        .padding(.vertical, 3)
        .background(Color(red: 0.82, green: 0.82, blue: 0.82))
        .overlay(alignment: .top) {
            Rectangle()
                .fill(Color.white.opacity(0.9))
                .frame(height: 2)
        }
    }
}

private struct TaskbarButton: View {
    let title: String
    let icon: String

    var body: some View {
        HStack(spacing: 5) {
            Image(systemName: icon)
                .font(.system(size: 9, weight: .black))
            Text(title)
                .font(.system(size: 11, weight: .bold, design: .monospaced))
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(.horizontal, 6)
        .background(Color(red: 0.85, green: 0.85, blue: 0.85))
        .overlay(
            Rectangle()
                .stroke(Color.black, lineWidth: 1)
        )
    }
}

private struct TaskbarTab: View {
    let title: String

    var body: some View {
        Text(title)
            .font(.system(size: 10, weight: .medium, design: .monospaced))
            .lineLimit(1)
            .minimumScaleFactor(0.7)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
            .padding(.horizontal, 8)
            .background(Color(red: 0.86, green: 0.86, blue: 0.86))
            .overlay(
                Rectangle()
                    .stroke(Color.gray.opacity(0.9), lineWidth: 1)
            )
    }
}

private struct TaskbarClock: View {
    @State private var currentDate = Date()
    private let timer = Timer.publish(every: 30, on: .main, in: .common).autoconnect()

    private static let formatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "h:mm a"
        return formatter
    }()

    var body: some View {
        Text(Self.formatter.string(from: currentDate))
            .font(.system(size: 11, weight: .medium, design: .monospaced))
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color(red: 0.86, green: 0.86, blue: 0.86))
            .overlay(
                Rectangle()
                    .stroke(Color.gray.opacity(0.9), lineWidth: 1)
            )
            .onReceive(timer) { date in
                currentDate = date
            }
    }
}

private extension CGRect {
    func scaled(to size: CGSize) -> CGRect {
        CGRect(
            x: origin.x * size.width,
            y: origin.y * size.height,
            width: width * size.width,
            height: height * size.height
        )
    }
}

#Preview {
    MainDesktopView(viewModel: MainDesktopViewModel())
}
