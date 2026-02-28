import SwiftUI

enum ScoreWiseTheme {
    static let accent = Color.black
    static let accentSoft = Color(red: 0.88, green: 0.90, blue: 0.98)
    static let backgroundTop = Color(red: 0.97, green: 0.97, blue: 0.98)
    static let backgroundBottom = Color(red: 0.94, green: 0.95, blue: 0.98)
    static let surface = Color.white
    static let surfaceSoft = Color(red: 0.97, green: 0.97, blue: 0.98)
    static let ink = Color(red: 0.08, green: 0.09, blue: 0.11)
    static let secondaryInk = Color(red: 0.40, green: 0.42, blue: 0.47)
    static let success = Color(red: 0.10, green: 0.55, blue: 0.32)
    static let warning = Color(red: 0.74, green: 0.36, blue: 0.14)
}

struct PrimaryActionButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.headline)
            .padding(.vertical, 12)
            .frame(maxWidth: .infinity)
            .background(ScoreWiseTheme.accent.opacity(configuration.isPressed ? 0.82 : 1))
            .foregroundStyle(.white)
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .stroke(Color.white.opacity(0.08), lineWidth: 1)
            )
            .shadow(color: .black.opacity(0.12), radius: 12, y: 6)
    }
}

struct SurfaceCard<Content: View>: View {
    var emphasize: Bool = false
    @ViewBuilder let content: Content

    var body: some View {
        content
            .padding(18)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(emphasize ? ScoreWiseTheme.surface : ScoreWiseTheme.surfaceSoft)
            .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 24, style: .continuous)
                    .stroke(Color.black.opacity(0.05), lineWidth: 1)
            )
            .shadow(color: .black.opacity(0.05), radius: 16, y: 6)
    }
}

struct RadioDot: View {
    let selected: Bool

    var body: some View {
        ZStack {
            Circle()
                .stroke(selected ? ScoreWiseTheme.ink : Color.gray.opacity(0.45), lineWidth: 2)
                .frame(width: 26, height: 26)
            if selected {
                Circle()
                    .fill(ScoreWiseTheme.ink)
                    .frame(width: 14, height: 14)
            }
        }
    }
}
