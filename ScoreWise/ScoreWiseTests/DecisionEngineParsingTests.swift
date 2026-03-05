import XCTest
@testable import ScoreWise

final class DecisionEngineParsingTests: XCTestCase {
    func testExplicitOptionsExcludeStrategyWhenComparableEntitiesExist() {
        var draft = RankingDraft.empty
        draft.contextNarrative = """
        I am deciding between Offer A — Nebula Health Analytics and Offer B — PalmEdge Digital.
        Minimum salary is 17000 SAR. I may negotiate, but the decision is between those two offers.
        """

        let parsed = DecisionEngine.shared.parse(draft: draft, extractedEvidence: [], userProfile: nil)
        let labels = parsed.explicitOptions.map { $0.label.lowercased() }

        XCTAssertTrue(labels.contains(where: { $0.contains("offer a") }))
        XCTAssertTrue(labels.contains(where: { $0.contains("offer b") }))
        XCTAssertFalse(labels.contains(where: { $0.contains("negotiate") || $0.contains("pilot") }))
    }
}
