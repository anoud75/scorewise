import SwiftUI
import UIKit

struct AppLoadingView: View {
    @ObservedObject var viewModel: AppLoadingViewModel

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            VStack(spacing: 24) {
                LoadingIconView()
                    .frame(width: 340, height: 340)

                Text("Loading...")
                    .font(.system(size: 22, weight: .regular, design: .monospaced))
                    .foregroundStyle(.white)

                PixelLoadingBar(
                    filledSegments: viewModel.filledSegments,
                    totalSegments: viewModel.totalSegments
                )
            }
            .padding(.horizontal, 20)
        }
        .onAppear {
            viewModel.startLoadingAnimation()
        }
    }
}

private struct LoadingIconView: View {
    var body: some View {
        if let image = AssetImageLoader.image(named: "loading-monitor") {
            Image(uiImage: image)
                .resizable()
                .scaledToFit()
        } else {
            RoundedRectangle(cornerRadius: 18)
                .fill(Color.gray.opacity(0.2))
                .overlay {
                    Image(systemName: "display")
                        .font(.system(size: 110, weight: .regular))
                        .foregroundStyle(.white.opacity(0.8))
                }
        }
    }
}

private struct PixelLoadingBar: View {
    let filledSegments: Int
    let totalSegments: Int

    var body: some View {
        HStack(spacing: 5) {
            ForEach(0..<totalSegments, id: \.self) { index in
                RoundedRectangle(cornerRadius: 3)
                    .fill(index < filledSegments ? Color(red: 0.12, green: 0.07, blue: 0.86) : Color.black)
                    .frame(width: 22, height: 42)
                    .overlay(
                        RoundedRectangle(cornerRadius: 3)
                            .stroke(Color(red: 0.12, green: 0.07, blue: 0.86), lineWidth: 2)
                    )
            }
        }
        .padding(8)
        .background(Color.black)
        .overlay(
            RoundedRectangle(cornerRadius: 4)
                .stroke(Color(red: 0.12, green: 0.07, blue: 0.86), lineWidth: 4)
        )
    }
}

#Preview {
    AppLoadingView(viewModel: AppLoadingViewModel())
}
