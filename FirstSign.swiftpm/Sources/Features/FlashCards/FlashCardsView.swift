import SwiftUI
import UIKit

struct FlashCardsView: View {
    @ObservedObject var viewModel: FlashCardsViewModel
    let onClose: () -> Void
    let onOpenFolder: (String) -> Void

    var body: some View {
        ZStack(alignment: .topLeading) {
            if let image = AssetImageLoader.image(named: "flashcards-window-base") {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
            } else {
                Rectangle()
                    .fill(Color(red: 0.93, green: 0.9, blue: 0.68))
                    .overlay(
                        Rectangle()
                            .stroke(Color.black, lineWidth: 4)
                    )
                    .overlay(alignment: .top) {
                        Rectangle()
                            .fill(Color(red: 0.09, green: 0.04, blue: 0.83))
                            .frame(height: 42)
                    }
            }

            VStack(spacing: 0) {
                titleBar
                    .frame(height: 42)

                foldersRow
                    .padding(.top, 18)
                    .padding(.horizontal, 16)

                Spacer()
            }
        }
    }

    private var titleBar: some View {
        HStack(spacing: 8) {
            if let icon = AssetImageLoader.image(named: "flashcards-title-icon") {
                Image(uiImage: icon)
                    .resizable()
                    .scaledToFit()
                    .frame(width: 30, height: 24)
            }

            Text("FlashCards..Files")
                .font(.system(size: 17, weight: .regular, design: .monospaced))
                .foregroundStyle(.white)

            Spacer()

            Button(action: onClose) {
                if let closeImage = AssetImageLoader.image(named: "flashcards-close-button") {
                    Image(uiImage: closeImage)
                        .resizable()
                        .scaledToFit()
                        .frame(width: 28, height: 28)
                } else {
                    Rectangle()
                        .fill(Color(red: 0.82, green: 0.84, blue: 0.86))
                        .frame(width: 24, height: 24)
                        .overlay(
                            Image(systemName: "xmark")
                                .font(.system(size: 14, weight: .regular))
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
        .padding(.horizontal, 12)
    }

    private var foldersRow: some View {
        HStack(spacing: 10) {
            ForEach(viewModel.folders) { folder in
                Button {
                    viewModel.didTapFolder(folder)
                    onOpenFolder(folder.id)
                } label: {
                    VStack(spacing: 5) {
                        if let image = AssetImageLoader.image(named: folder.assetName) {
                            Image(uiImage: image)
                                .resizable()
                                .scaledToFit()
                                .frame(width: 72, height: 58)
                        } else {
                            Rectangle()
                                .fill(Color.yellow.opacity(0.7))
                                .overlay(
                                    Rectangle()
                                        .stroke(Color.black, lineWidth: 2)
                                )
                                .frame(width: 72, height: 58)
                        }

                        Text(folder.title)
                            .font(.system(size: 12, weight: .regular, design: .monospaced))
                            .foregroundStyle(.black)
                            .lineLimit(1)
                            .minimumScaleFactor(0.75)
                    }
                    .padding(.horizontal, 4)
                    .padding(.vertical, 2)
                    .background(
                        viewModel.selectedFolderID == folder.id
                        ? Color(red: 0.2, green: 0.35, blue: 0.9).opacity(0.25)
                        : Color.clear
                    )
                    .overlay(
                        Rectangle()
                            .stroke(
                                viewModel.selectedFolderID == folder.id ? Color.blue : Color.clear,
                                lineWidth: 1
                            )
                    )
                }
                .buttonStyle(.plain)
            }
            Spacer(minLength: 0)
        }
    }
}

#Preview {
    FlashCardsView(viewModel: FlashCardsViewModel(), onClose: {}, onOpenFolder: { _ in })
}
