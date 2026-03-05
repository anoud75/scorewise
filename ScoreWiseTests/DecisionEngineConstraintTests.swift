import XCTest
@testable import ScoreWise

final class DecisionEngineConstraintTests: XCTestCase {
    func testMinimumSalaryConstraintFlagsViolatingOption() {
        var draft = RankingDraft.empty
        draft.contextNarrative = """
        I am comparing Offer A and Offer B.
        My minimum salary is 17000 SAR per month.
        Offer A salary: 16000 SAR/month.
        Offer B salary: 19000 SAR/month.
        """
        draft.vendors = [
            VendorDraft(name: "Offer A", notes: "Salary 16000 SAR/month", attachments: []),
            VendorDraft(name: "Offer B", notes: "Salary 19000 SAR/month", attachments: [])
        ]

        let findings = DecisionEngine.shared.detectConstraints(draft: draft)
        let salaryFinding = findings.first(where: { $0.type == .minimumSalary })

        XCTAssertNotNil(salaryFinding)
        XCTAssertTrue(salaryFinding?.violatedOptionLabels.contains(where: { $0.lowercased().contains("offer a") }) == true)
    }
}
