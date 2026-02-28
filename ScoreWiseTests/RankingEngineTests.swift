import XCTest
@testable import ScoreWise

final class RankingEngineTests: XCTestCase {
    func testNormalizedWeightsAlwaysSumToOneHundred() {
        let criteria = [
            CriterionDraft(name: "A", detail: "", category: "", weightPercent: 10),
            CriterionDraft(name: "B", detail: "", category: "", weightPercent: 30),
            CriterionDraft(name: "C", detail: "", category: "", weightPercent: 80)
        ]

        let normalized = RankingEngine.normalizedCriteria(criteria)
        let total = normalized.reduce(0.0) { $0 + $1.weightPercent }
        XCTAssertEqual(total, 100.0, accuracy: 0.001)
    }

    func testComputeResultDetectsTightTie() {
        var draft = RankingDraft.empty
        draft.vendors = [
            VendorDraft(name: "One", notes: "", attachments: []),
            VendorDraft(name: "Two", notes: "", attachments: [])
        ]
        draft.criteria = [
            CriterionDraft(name: "Cost", detail: "", category: "", weightPercent: 50),
            CriterionDraft(name: "Quality", detail: "", category: "", weightPercent: 50)
        ]

        draft.scores = [
            ScoreDraft(vendorID: draft.vendors[0].id, criterionID: draft.criteria[0].id, score: 8.0, source: .manual, confidence: 1.0, evidenceSnippet: ""),
            ScoreDraft(vendorID: draft.vendors[0].id, criterionID: draft.criteria[1].id, score: 8.0, source: .manual, confidence: 1.0, evidenceSnippet: ""),
            ScoreDraft(vendorID: draft.vendors[1].id, criterionID: draft.criteria[0].id, score: 8.02, source: .manual, confidence: 1.0, evidenceSnippet: ""),
            ScoreDraft(vendorID: draft.vendors[1].id, criterionID: draft.criteria[1].id, score: 8.0, source: .manual, confidence: 1.0, evidenceSnippet: "")
        ]

        let result = RankingEngine.computeResult(for: draft)
        XCTAssertTrue(result.tieDetected)
    }
}
