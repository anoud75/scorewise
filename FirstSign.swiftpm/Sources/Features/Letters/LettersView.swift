import SwiftUI
import UIKit

struct LettersView: View {
    @ObservedObject var viewModel: LettersViewModel
    let onClose: () -> Void

    var body: some View {
        ZStack(alignment: .topLeading) {
            backgroundView

            VStack(alignment: .leading, spacing: 0) {
                topBar
                    .padding(.horizontal, 24)
                    .padding(.top, 22)

                ScrollView(.vertical, showsIndicators: true) {
                    LazyVGrid(
                        columns: [GridItem(.adaptive(minimum: 86, maximum: 96), spacing: 16, alignment: .top)],
                        spacing: 16
                    ) {
                        ForEach(viewModel.items) { item in
                            letterCard(item)
                        }
                    }
                    .padding(.top, 18)
                    .padding(.horizontal, 24)
                    .padding(.bottom, 24)
                }
            }
        }
        .overlay(
            Rectangle()
                .stroke(Color.black, lineWidth: 3)
        )
    }

    @ViewBuilder
    private var backgroundView: some View {
        if let image = AssetImageLoader.image(named: "letters-window-base") {
            Image(uiImage: image)
                .resizable()
                .scaledToFill()
        } else {
            LinearGradient(
                colors: [
                    Color(red: 0.95, green: 0.91, blue: 0.68),
                    Color(red: 0.93, green: 0.8, blue: 0.76),
                    Color(red: 0.88, green: 0.62, blue: 0.86)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        }
    }

    private var topBar: some View {
        HStack(alignment: .top) {
            if let icon = AssetImageLoader.image(named: "letters-header-icon") {
                Image(uiImage: icon)
                    .resizable()
                    .scaledToFit()
                    .frame(width: 54, height: 54)
            } else if let icon = AssetImageLoader.image(named: "desktop-icon-letters") {
                Image(uiImage: icon)
                    .resizable()
                    .scaledToFit()
                    .frame(width: 54, height: 54)
            }

            Spacer()

            Button(action: onClose) {
                if let closeImage = AssetImageLoader.image(named: "letters-close-button") {
                    Image(uiImage: closeImage)
                        .resizable()
                        .scaledToFit()
                        .frame(width: 50, height: 50)
                } else {
                    Circle()
                        .fill(Color(red: 0.96, green: 0.2, blue: 0.22))
                        .frame(width: 42, height: 42)
                        .overlay(
                            Image(systemName: "xmark")
                                .font(.system(size: 24, weight: .bold))
                                .foregroundStyle(.white)
                        )
                        .overlay(
                            Circle().stroke(Color.black, lineWidth: 2)
                        )
                }
            }
            .buttonStyle(.plain)
        }
    }

    private func letterCard(_ item: LetterCardItem) -> some View {
        let cardImage = resolveLetterImage(for: item)
        return Group {
            if let image = cardImage {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFit()
            } else {
                Rectangle()
                    .fill(Color(red: 0.93, green: 0.93, blue: 0.93))
                    .overlay(
                        Rectangle()
                            .stroke(Color.black, lineWidth: 3)
                    )
                    .overlay(
                        Text(item.letter)
                            .font(.system(size: 34, weight: .black, design: .monospaced))
                            .foregroundStyle(.black)
                    )
            }
        }
        .frame(maxWidth: .infinity)
        .aspectRatio(0.63, contentMode: .fit)
    }

    private func resolveLetterImage(for item: LetterCardItem) -> UIImage? {
        let lower = item.letter.lowercased()
        let candidates = [
            item.assetName,
            item.letter,
            lower,
            "letter-\(lower)",
            "alphabet-\(lower)",
            "asl-\(lower)"
        ]

        for name in candidates where !name.isEmpty {
            if let image = AssetImageLoader.image(named: name) {
                return image
            }
        }
        return nil
    }
}

#Preview {
    LettersView(viewModel: LettersViewModel(), onClose: {})
}
