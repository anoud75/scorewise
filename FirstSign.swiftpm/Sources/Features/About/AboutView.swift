import SwiftUI
import UIKit

struct AboutView: View {
    @ObservedObject var viewModel: AboutViewModel
    let onClose: () -> Void

    var body: some View {
        ZStack {
            Rectangle()
                .fill(Color(red: 0.93, green: 0.93, blue: 0.93))
                .overlay(
                    Rectangle()
                        .stroke(Color.black, lineWidth: 3)
                )

            VStack(alignment: .leading, spacing: 0) {
                HStack(alignment: .top) {
                    AboutHeaderInfoIcon()
                        .frame(width: 80, height: 80)

                    Spacer()

                    Button(action: onClose) {
                        if let closeImage = AssetImageLoader.image(named: "common-close-button") ??
                            AssetImageLoader.image(named: "about-close-button") {
                            Image(uiImage: closeImage)
                                .resizable()
                                .scaledToFit()
                                .frame(width: 48, height: 48)
                        } else {
                            Rectangle()
                                .fill(Color(red: 0.82, green: 0.84, blue: 0.86))
                                .frame(width: 48, height: 48)
                                .overlay(
                                    Image(systemName: "xmark")
                                        .font(.system(size: 28, weight: .regular))
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
                .padding(.top, 20)
                .padding(.horizontal, 24)

                ScrollView {
                    VStack(alignment: .leading, spacing: 22) {
                        styledLine(viewModel.titleLine)
                            .font(.system(size: 16, weight: .regular, design: .monospaced))

                        styledLine(viewModel.paragraphOne)
                        styledLine(viewModel.paragraphTwo)

                        styledLine(viewModel.heading)

                        bulletLine(viewModel.bulletOne)
                        bulletLine(viewModel.bulletTwo)
                        bulletLine(viewModel.bulletThree)
                        bulletLine(viewModel.bulletFour)

                        styledLine(viewModel.closingLine)
                            .frame(maxWidth: .infinity, alignment: .center)
                            .padding(.top, 8)
                    }
                    .font(.system(size: 14, weight: .medium, design: .monospaced))
                    .lineSpacing(8)
                    .padding(.horizontal, 24)
                    .padding(.bottom, 30)
                }
            }
        }
    }

    private func bulletLine(_ segments: [AboutTextSegment]) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Text("•")
                .foregroundStyle(.black)
            styledLine(segments)
        }
    }

    private func styledLine(_ segments: [AboutTextSegment]) -> Text {
        guard let first = segments.first else {
            return Text("")
        }

        return segments.dropFirst().reduce(styledText(first)) { partial, segment in
            partial + styledText(segment)
        }
    }

    private func styledText(_ segment: AboutTextSegment) -> Text {
        switch segment.tone {
        case .normal:
            return Text(segment.text).foregroundColor(.black)
        case .red:
            return Text(segment.text).foregroundColor(Color(red: 0.95, green: 0.22, blue: 0.2))
        case .green:
            return Text(segment.text).foregroundColor(Color(red: 0.15, green: 0.75, blue: 0.2))
        }
    }
}

private struct AboutHeaderInfoIcon: View {
    var body: some View {
        ZStack(alignment: .bottomLeading) {
            Ellipse()
                .fill(.white)
                .overlay(
                    Ellipse()
                        .stroke(Color.black, lineWidth: 2)
                )

            AboutInfoTail()
                .fill(.white)
                .overlay(
                    AboutInfoTail()
                        .stroke(Color.black, lineWidth: 2)
                )
                .frame(width: 22, height: 14)
                .offset(x: 24, y: 6)

            Text("i")
                .font(.system(size: 56, weight: .bold, design: .serif))
                .foregroundStyle(Color(red: 0.16, green: 0.16, blue: 0.88))
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .offset(y: -4)
        }
    }
}

private struct AboutInfoTail: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.midX, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.minX, y: rect.minY))
        path.closeSubpath()
        return path
    }
}

#Preview {
    AboutView(viewModel: AboutViewModel(), onClose: {})
}
