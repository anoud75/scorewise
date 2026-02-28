import Foundation

enum AboutTextTone {
    case normal
    case red
    case green
}

struct AboutTextSegment: Identifiable {
    let id = UUID()
    let text: String
    let tone: AboutTextTone
}

@MainActor
final class AboutViewModel: ObservableObject {
    let titleLine: [AboutTextSegment] = [
        AboutTextSegment(text: "First Sign: A New Dawn for Language", tone: .normal)
    ]

    let paragraphOne: [AboutTextSegment] = [
        AboutTextSegment(text: "Silence is not empty-it is filled with possibility. First Sign is an AI-powered gateway designed for the ", tone: .normal),
        AboutTextSegment(text: "98%", tone: .red),
        AboutTextSegment(text: " of Deaf individuals worldwide who have been denied access to sign language education. While the risk of language deprivation begins early in life, we believe it is never too late to discover, reclaim, and express your voice.", tone: .normal)
    ]

    let paragraphTwo: [AboutTextSegment] = [
        AboutTextSegment(text: "Whether you are among the ", tone: .normal),
        AboutTextSegment(text: "92%", tone: .red),
        AboutTextSegment(text: " of Deaf children born to hearing parents, or an adult ready to begin your journey, our intuitive and vibrant interface bridges the communication gap-especially where ", tone: .normal),
        AboutTextSegment(text: "3 out of 4", tone: .red),
        AboutTextSegment(text: " families do not yet sign. First Sign transforms how people connect, ensuring that language delays no longer shape futures or limit potential.", tone: .normal)
    ]

    let heading: [AboutTextSegment] = [
        AboutTextSegment(text: "Why This Matters", tone: .green)
    ]

    let bulletOne: [AboutTextSegment] = [
        AboutTextSegment(text: "A Global Challenge: ", tone: .normal),
        AboutTextSegment(text: "98%", tone: .red),
        AboutTextSegment(text: " of Deaf individuals lack access to formal sign language education.", tone: .normal)
    ]

    let bulletTwo: [AboutTextSegment] = [
        AboutTextSegment(text: "The Family Barrier: Because ", tone: .normal),
        AboutTextSegment(text: "92%", tone: .red),
        AboutTextSegment(text: " of Deaf children are born to hearing parents, communication gaps often begin at home.", tone: .normal)
    ]

    let bulletThree: [AboutTextSegment] = [
        AboutTextSegment(text: "A Turning Point: With ", tone: .normal),
        AboutTextSegment(text: "75%", tone: .red),
        AboutTextSegment(text: " of parents not currently signing, First Sign provides tools that empower families and learners of all ages.", tone: .normal)
    ]

    let bulletFour: [AboutTextSegment] = [
        AboutTextSegment(text: "Language Is a Right: Sign language is a complete, expressive language-and everyone deserves the chance to see their words come alive.", tone: .normal)
    ]

    let closingLine: [AboutTextSegment] = [
        AboutTextSegment(text: "Give life to your hands. Give wings to your words. Start your First Sign.", tone: .normal)
    ]
}
