import SwiftUI
import UIKit

struct JournalingView: View {
    @ObservedObject var viewModel: JournalingViewModel
    let onClose: () -> Void

    var body: some View {
        GeometryReader { proxy in
            let rightInset = max(18, proxy.size.width * 0.02)
            let leftInset = max(90, proxy.size.width * 0.07)
            let topInset = max(14, proxy.size.height * 0.02)
            let editorHeight = min(max(180, proxy.size.height * 0.28), 280)
            let tokenHeight = min(max(70, proxy.size.height * 0.11), 104)
            let hasBakedCloseIcon = AssetImageLoader.image(named: "journaling-window-base") != nil

            ZStack(alignment: .topLeading) {
                backgroundView

                VStack(spacing: 0) {
                    HStack {
                        Spacer()
                        Button(action: onClose) {
                            if hasBakedCloseIcon {
                                Rectangle()
                                    .fill(Color.black.opacity(0.001))
                                    .frame(width: 56, height: 56)
                                    .contentShape(Rectangle())
                            } else {
                                closeButton
                            }
                        }
                        .buttonStyle(.plain)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.top, 24)
                    .padding(.trailing, 22)

                    VStack(alignment: .leading, spacing: 8) {
                        englishInputView
                            .frame(maxWidth: .infinity)
                            .frame(height: editorHeight)

                        Rectangle()
                            .fill(Color.black.opacity(0.7))
                            .frame(height: 1)

                        fingerspellLineView
                            .frame(maxWidth: .infinity)
                            .frame(height: tokenHeight)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.top, topInset)
                    .padding(.leading, leftInset)
                    .padding(.trailing, rightInset)

                    Spacer(minLength: 0)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            }
        }
    }

    private var backgroundView: some View {
        Group {
            if let image = AssetImageLoader.image(named: "journaling-window-base") {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
            } else {
                Rectangle()
                    .fill(Color(red: 0.91, green: 0.91, blue: 0.89))
                    .overlay(alignment: .leading) {
                        Rectangle()
                            .fill(Color.white)
                            .frame(width: 52)
                    }
            }
        }
        .clipped()
        .overlay(
            Rectangle()
                .stroke(Color.black.opacity(0.15), lineWidth: 1)
        )
    }

    private var closeButton: some View {
        Group {
            if let image = AssetImageLoader.image(named: "journaling-close-button") {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFit()
                    .frame(width: 44, height: 44)
            } else if let image = AssetImageLoader.image(named: "common-close-button") {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFit()
                    .frame(width: 44, height: 44)
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
    }

    private var englishInputView: some View {
        ZStack(alignment: .topLeading) {
            TextEditor(text: $viewModel.englishText)
                .scrollContentBackground(.hidden)
                .font(.system(size: 24, weight: .regular, design: .monospaced))
                .foregroundStyle(.black)
                .background(Color.clear)
                .padding(.horizontal, 10)
                .padding(.vertical, 10)

            if viewModel.englishText.isEmpty {
                Text("Write in English...")
                    .font(.system(size: 24, weight: .regular, design: .monospaced))
                    .foregroundStyle(.black.opacity(0.35))
                    .padding(.top, 10)
                    .padding(.leading, 8)
                    .allowsHitTesting(false)
            }
        }
    }

    private var fingerspellLineView: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                if viewModel.fingerspellingTokens.isEmpty {
                    Text("Fingerspelling appears here...")
                        .font(.system(size: 22, weight: .regular, design: .monospaced))
                        .foregroundStyle(.black.opacity(0.35))
                } else {
                    ForEach(viewModel.fingerspellingTokens) { token in
                        tokenCell(token)
                    }
                }
            }
            .padding(.vertical, 4)
        }
    }

    private func tokenCell(_ token: FingerSpellingToken) -> some View {
        ZStack {
            Rectangle()
                .fill(Color.white.opacity(0.8))
                .overlay(
                    Rectangle()
                        .stroke(Color.black.opacity(0.4), lineWidth: 1)
                )

            if token.value == "/" {
                Text("SPACE")
                    .font(.system(size: 10, weight: .bold, design: .monospaced))
                    .foregroundStyle(.black.opacity(0.75))
            } else if let image = imageForToken(token) {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFit()
                    .padding(3)
            } else {
                Text(token.value)
                    .font(.system(size: 18, weight: .bold, design: .monospaced))
                    .foregroundStyle(.black)
            }
        }
        .frame(width: 54, height: 54)
    }

    private func imageForToken(_ token: FingerSpellingToken) -> UIImage? {
        guard token.value != "/" else { return nil }
        let lower = token.value.lowercased()
        let candidates: [String] = [
            token.assetName ?? "",
            "translator-fingerspell-\(lower)",
            "translator-letter-\(lower)",
            "fingerspell-\(lower)",
            "asl-\(lower)",
            "sign-\(lower)",
            lower
        ].filter { !$0.isEmpty }

        for name in candidates {
            if let image = AssetImageLoader.image(named: name) {
                return image
            }
        }
        return nil
    }
}

#Preview {
    JournalingView(viewModel: JournalingViewModel(), onClose: {})
}
