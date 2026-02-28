import Foundation

struct FirstSignIntroModel {
    let windowTitle: String
    let introText: String
    let leftTitleLeading: String
    let leftTitleTrailing: String

    static let sample = FirstSignIntroModel(
        windowTitle: "First Sign",
        introText: """
Welcome to the First Sign System.
Here, we provide an excellent
opportunity for you to learn sign
language. This resource is also
designed for deaf people who have
never been exposed to or were unable
to learn a language.
""",
        leftTitleLeading: "First.",
        leftTitleTrailing: "sign"
    )
}
