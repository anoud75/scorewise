import SwiftUI

struct PixelWindowCard<Content: View>: View {
    let title: String
    let onClose: () -> Void
    @ViewBuilder let content: Content

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text(title)
                    .font(.system(size: 16, weight: .regular, design: .monospaced))
                    .foregroundStyle(.white)

                Spacer()

                PixelCloseButton(action: onClose)
            }
            .padding(.horizontal, 14)
            .frame(height: 56)
            .background(Color(red: 0.09, green: 0.04, blue: 0.83))

            content
                .background(Color(red: 0.93, green: 0.93, blue: 0.93))
        }
        .background(Color(red: 0.96, green: 0.96, blue: 0.96))
        .overlay(
            Rectangle()
                .stroke(Color.black, lineWidth: 4)
        )
        .shadow(color: .black, radius: 0, x: 6, y: 6)
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(Color.gray.opacity(0.45))
                .frame(height: 5)
                .offset(y: 2)
        }
    }
}

struct PixelCloseButton: View {
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            ZStack {
                Rectangle()
                    .fill(Color(red: 0.82, green: 0.84, blue: 0.86))
                    .frame(width: 40, height: 40)

                Image(systemName: "xmark")
                    .font(.system(size: 22, weight: .regular))
                    .foregroundStyle(Color.black)
            }
            .overlay(
                Rectangle()
                    .stroke(Color.black, lineWidth: 2)
            )
        }
        .buttonStyle(.plain)
    }
}

struct PixelInstallButton: View {
    let title: String
    let onTap: () -> Void
    @GestureState private var isPressed = false

    var body: some View {
        Button(action: onTap) {
            Text(title)
                .font(.system(size: 15, weight: .regular, design: .monospaced))
                .foregroundStyle(.white.opacity(0.9))
                .frame(width: 170, height: 48)
                .background(
                    ZStack {
                        Rectangle().fill(Color.white)
                        Rectangle()
                            .fill(
                                LinearGradient(
                                    colors: [
                                        Color(red: 0.82, green: 0.82, blue: 0.82),
                                        Color(red: 0.74, green: 0.74, blue: 0.74)
                                    ],
                                    startPoint: .top,
                                    endPoint: .bottom
                                )
                            )
                            .padding(7)
                    }
                )
                .overlay(
                    Rectangle()
                        .stroke(Color.black, lineWidth: 3)
                )
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

struct WarpedPressEffect: ViewModifier {
    let pressed: Bool

    func body(content: Content) -> some View {
        content
            .scaleEffect(x: pressed ? 0.97 : 1, y: pressed ? 0.9 : 1, anchor: .center)
            .rotation3DEffect(
                .degrees(pressed ? -9 : 0),
                axis: (x: 1, y: 0, z: 0),
                anchor: .center,
                perspective: 0.45
            )
            .offset(y: pressed ? 4 : 0)
    }
}
