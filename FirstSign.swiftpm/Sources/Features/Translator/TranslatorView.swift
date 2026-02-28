import SwiftUI
import UIKit

struct TranslatorView: View {
    @ObservedObject var viewModel: TranslatorViewModel
    let onClose: () -> Void

    var body: some View {
        ZStack {
            baseWindow

            VStack(spacing: 0) {
                titleBar
                    .frame(height: 56)

                VStack(spacing: 10) {
                    outputPanel

                    modeToggleButton
                        .frame(width: 96, height: 96)

                    inputPanel

                    bottomBar
                        .frame(height: 20)
                }
                .padding(.horizontal, 18)
                .padding(.top, 12)
                .padding(.bottom, 8)
            }
        }
    }

    @ViewBuilder
    private var baseWindow: some View {
        Group {
            if let image = AssetImageLoader.image(named: "translator-window-base") {
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
            if let image = AssetImageLoader.image(named: "translator-title-bar") {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
            } else {
                Rectangle().fill(Color(red: 0.09, green: 0.04, blue: 0.83))
            }

            HStack(spacing: 10) {
                if let icon = AssetImageLoader.image(named: "translator-title-icon") {
                    Image(uiImage: icon)
                        .resizable()
                        .scaledToFit()
                        .frame(width: 36, height: 36)
                } else if let icon = AssetImageLoader.image(named: "desktop-icon-translator") {
                    Image(uiImage: icon)
                        .resizable()
                        .scaledToFit()
                        .frame(width: 36, height: 36)
                }

                Text("Translator")
                    .font(.system(size: 18, weight: .regular, design: .monospaced))
                    .foregroundStyle(.white)

                Spacer()

                Button(action: onClose) {
                    if let closeImage = AssetImageLoader.image(named: "translator-close-button") {
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

    private var outputPanel: some View {
        ZStack {
            if let image = AssetImageLoader.image(named: "translator-output-panel") {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
            } else {
                Rectangle()
                    .fill(Color(red: 0.93, green: 0.93, blue: 0.93))
                    .overlay(
                        Rectangle()
                            .stroke(Color.black, lineWidth: 6)
                    )
            }
        }
        .overlay(alignment: .topLeading) {
            VStack(alignment: .leading, spacing: 8) {
                Text(viewModel.mode.title)
                    .font(.system(size: 12, weight: .semibold, design: .monospaced))
                    .foregroundStyle(.black.opacity(0.75))

                if viewModel.mode == .englishToFingerspell {
                    if viewModel.englishToFingerspellTokens.isEmpty {
                        Text("Type English text below to see fingerspelling.")
                            .font(.system(size: 14, weight: .medium, design: .monospaced))
                            .foregroundStyle(.black.opacity(0.55))
                    } else {
                        tokenPreviewRow(viewModel.englishToFingerspellTokens)
                    }
                } else {
                    let output = viewModel.fingerspellToEnglishText
                    if output.isEmpty {
                        Text("Tap fingerspell keys below to build English text.")
                            .font(.system(size: 14, weight: .medium, design: .monospaced))
                            .foregroundStyle(.black.opacity(0.55))
                    } else {
                        Text(output)
                            .font(.system(size: 34, weight: .semibold, design: .monospaced))
                            .foregroundStyle(.black)
                            .lineLimit(2)
                            .minimumScaleFactor(0.6)
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
        }
        .frame(maxWidth: .infinity)
        .aspectRatio(1.95, contentMode: .fit)
    }

    private var modeToggleButton: some View {
        Button(action: viewModel.toggleMode) {
            Group {
                if let image = AssetImageLoader.image(named: "translator-mode-switch") {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFit()
                } else {
                    RoundedRectangle(cornerRadius: 14)
                        .fill(Color.yellow)
                        .overlay(
                            Image(systemName: "arrow.triangle.2.circlepath")
                                .font(.system(size: 30, weight: .bold))
                                .foregroundStyle(.black)
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 14)
                                .stroke(Color.black, lineWidth: 2)
                        )
                }
            }
        }
        .buttonStyle(.plain)
    }

    private var inputPanel: some View {
        ZStack {
            if let image = AssetImageLoader.image(named: "translator-input-panel") {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
            } else {
                Rectangle()
                    .fill(Color(red: 0.68, green: 0.89, blue: 0.9))
                    .overlay(
                        Rectangle()
                            .stroke(Color.black, lineWidth: 6)
                    )
            }
        }
        .overlay {
            if viewModel.mode == .englishToFingerspell {
                englishInputView
            } else {
                fingerspellKeyboardView
            }
        }
        .frame(maxWidth: .infinity)
        .aspectRatio(1.95, contentMode: .fit)
    }

    private var englishInputView: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Enter English text")
                .font(.system(size: 12, weight: .semibold, design: .monospaced))
                .foregroundStyle(.black.opacity(0.75))

            ZStack(alignment: .topLeading) {
                TextEditor(
                    text: Binding(
                        get: { viewModel.englishInput },
                        set: { viewModel.updateEnglishInput($0) }
                    )
                )
                .scrollContentBackground(.hidden)
                .foregroundStyle(.black)
                .font(.system(size: 18, weight: .medium, design: .monospaced))
                .padding(.horizontal, 4)
                .padding(.vertical, 2)

                if viewModel.englishInput.isEmpty {
                    Text("Example: hello")
                        .font(.system(size: 16, weight: .medium, design: .monospaced))
                        .foregroundStyle(.black.opacity(0.45))
                        .padding(.top, 10)
                        .padding(.leading, 10)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color.white.opacity(0.7))
            .overlay(
                Rectangle()
                    .stroke(Color.black.opacity(0.4), lineWidth: 1)
            )

            Text("Letters and spaces are supported.")
                .font(.system(size: 11, weight: .medium, design: .monospaced))
                .foregroundStyle(.black.opacity(0.65))
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
    }

    private var fingerspellKeyboardView: some View {
        GeometryReader { geometry in
            let verticalPadding: CGFloat = 8
            let fixedContentHeight: CGFloat = 28 + 28 + 8 + 8 + (verticalPadding * 2)
            let keyboardGridHeight = min(208, max(120, geometry.size.height - fixedContentHeight))

            VStack(spacing: 8) {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 6) {
                        ForEach(viewModel.fingerspellLetters.indices, id: \.self) { index in
                            let value = viewModel.fingerspellLetters[index]
                            ZStack {
                                Rectangle()
                                    .fill(Color.white.opacity(0.8))
                                    .overlay(
                                        Rectangle()
                                            .stroke(Color.black, lineWidth: 2)
                                    )

                                Text(value == " " ? "␠" : value)
                                    .font(.system(size: 12, weight: .bold, design: .monospaced))
                                    .foregroundStyle(.black)
                            }
                            .frame(width: 24, height: 24)
                        }
                    }
                }
                .frame(height: 28)

                ScrollView {
                    LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 6), count: 7), spacing: 6) {
                        ForEach(viewModel.keys) { key in
                            Button {
                                viewModel.appendFingerLetter(key.letter)
                            } label: {
                                fingerKey(key.letter)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.bottom, 4)
                }
                .frame(maxWidth: .infinity)
                .frame(height: keyboardGridHeight)

                HStack(spacing: 8) {
                    actionButton("Space", action: viewModel.appendSpace)
                    actionButton("Back", action: viewModel.backspace)
                    actionButton("Clear", action: viewModel.clearFingerspellInput)
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, verticalPadding)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        }
    }

    private func actionButton(_ title: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 12, weight: .bold, design: .monospaced))
                .foregroundStyle(.black)
                .frame(maxWidth: .infinity)
                .frame(height: 28)
                .background(Color.white.opacity(0.8))
                .overlay(
                    Rectangle()
                        .stroke(Color.black, lineWidth: 2)
                )
        }
        .buttonStyle(.plain)
    }

    private func fingerKey(_ letter: String) -> some View {
        ZStack {
            Rectangle()
                .fill(Color.white.opacity(0.85))
                .overlay(
                    Rectangle()
                        .stroke(Color.black, lineWidth: 2)
                )

            VStack(spacing: 2) {
                if let image = fingerspellImage(for: letter) {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFit()
                        .frame(width: 24, height: 24)
                } else {
                    Text(letter)
                        .font(.system(size: 18, weight: .bold, design: .monospaced))
                        .foregroundStyle(.black)
                }

                Text(letter)
                    .font(.system(size: 9, weight: .bold, design: .monospaced))
                    .foregroundStyle(.black.opacity(0.7))
            }
            .padding(.top, 2)
        }
        .frame(height: 44)
    }

    private func tokenPreviewRow(_ tokens: [FingerSpellingToken]) -> some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(tokens) { token in
                    ZStack {
                        Rectangle()
                            .fill(Color.white)
                            .overlay(
                                Rectangle()
                                    .stroke(Color.black, lineWidth: 2)
                            )

                        if token.value == "/" {
                            Text("SPACE")
                                .font(.system(size: 10, weight: .bold, design: .monospaced))
                                .foregroundStyle(.black.opacity(0.7))
                        } else if let image = imageForToken(token) {
                            Image(uiImage: image)
                                .resizable()
                                .scaledToFit()
                                .padding(4)
                        } else {
                            Text(token.value)
                                .font(.system(size: 16, weight: .bold, design: .monospaced))
                                .foregroundStyle(.black)
                        }
                    }
                    .frame(width: 48, height: 48)
                }
            }
        }
        .frame(height: 56)
    }

    @ViewBuilder
    private var bottomBar: some View {
        if let image = AssetImageLoader.image(named: "translator-scroll-bar") {
            Image(uiImage: image)
                .resizable()
                .scaledToFill()
        } else {
            HStack(spacing: 2) {
                Rectangle().fill(Color.gray).frame(width: 20)
                Rectangle().fill(Color(red: 0.7, green: 0.7, blue: 0.7))
                Rectangle().fill(Color(red: 0.7, green: 0.7, blue: 0.7))
                Rectangle().fill(Color.gray).frame(width: 20)
            }
            .overlay(
                Rectangle()
                    .stroke(Color.black, lineWidth: 2)
            )
        }
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

    private func fingerspellImage(for letter: String) -> UIImage? {
        let candidates: [String] = [
            "translator-fingerspell-\(letter.lowercased())",
            "translator-letter-\(letter.lowercased())",
            "fingerspell-\(letter.lowercased())",
            "asl-\(letter.lowercased())",
            "sign-\(letter.lowercased())",
            letter.lowercased()
        ]

        for name in candidates {
            if let image = AssetImageLoader.image(named: name) {
                return image
            }
        }
        return nil
    }
}

#Preview {
    TranslatorView(viewModel: TranslatorViewModel(), onClose: {})
}
