import XCTest
@testable import ScoreWise

final class SurveyTaggerTests: XCTestCase {
    func testSurveyTagDerivation() {
        let answers: [SurveyAnswer] = [
            SurveyAnswer(questionID: "risk", value: "Risk-averse"),
            SurveyAnswer(questionID: "pace", value: "Very fast"),
            SurveyAnswer(questionID: "evidence", value: "High"),
            SurveyAnswer(questionID: "collaboration", value: "Team"),
            SurveyAnswer(questionID: "focus", value: "Cost"),
            SurveyAnswer(questionID: "planning", value: "Long-term"),
            SurveyAnswer(questionID: "review", value: "Often")
        ]

        let tags = SurveyTagger.deriveTags(from: answers)
        XCTAssertTrue(tags.contains("risk_averse"))
        XCTAssertTrue(tags.contains("speed_first"))
        XCTAssertTrue(tags.contains("evidence_heavy"))
        XCTAssertTrue(tags.contains("iterative_reviewer"))
    }
}
