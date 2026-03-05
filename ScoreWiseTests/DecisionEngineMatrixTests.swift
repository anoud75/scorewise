import XCTest
@testable import ScoreWise

final class DecisionEngineMatrixTests: XCTestCase {
    func testSuggestedInputsProduceNormalizedCriteriaAndFullScoreCoverage() {
        var draft = RankingDraft.empty
        draft.contextNarrative = "I am deciding between Offer A and Offer B for my next role."
        draft.vendors = [
            VendorDraft(name: "Offer A", notes: "Higher salary, strong brand, onsite", attachments: []),
            VendorDraft(name: "Offer B", notes: "Lower salary, strong role fit, remote", attachments: [])
        ]

        let inputs = DecisionEngine.shared.buildSuggestedInputs(
            draft: draft,
            context: .work,
            extractedEvidence: [],
            userProfile: nil
        )

        let totalWeight = inputs.criteria.reduce(0) { $0 + $1.weightPercent }
        XCTAssertEqual(totalWeight, 100.0, accuracy: 0.01)

        let expectedPairs = draft.vendors.count * inputs.criteria.count
        XCTAssertEqual(inputs.draftScores.count, expectedPairs)
    }
}
