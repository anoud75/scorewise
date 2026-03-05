import Foundation

struct ParsedSituation: Hashable {
    var narrative: String
    var combinedContext: String
    var inferredCategory: DecisionCategory
    var usageContext: UsageContext
    var isRecruiterMode: Bool
    var explicitOptions: [DecisionOptionSnapshot]
    var comparableOptionCheck: ComparableOptionCheck
}

struct OptionScopeValidation: Hashable {
    var isValid: Bool
    var message: String
    var missingCount: Int
    var invalidReasons: [String]

    static let empty = OptionScopeValidation(
        isValid: true,
        message: "",
        missingCount: 0,
        invalidReasons: []
    )
}

struct ComparableOptionCheck: Hashable {
    var comparable: Bool
    var detectedType: DecisionOptionType?
    var violations: [String]
}

struct KnowledgeRule: Hashable, Identifiable {
    var id: String = UUID().uuidString
    var scope: String
    var triggerTerms: [String]
    var outputHint: String
}

struct ChallengeQuestion: Hashable, Identifiable {
    var id: String
    var text: String
    var maxLen: Int = 120
}

struct AnalysisSummary: Codable, Hashable {
    var recommendation: String
    var drivers: [String]
    var risks: [String]
    var confidence: String
    var nextStep: String
}

struct InterpretedResult: Hashable {
    var drivers: [String]
    var risks: [String]
    var confidence: String
}

struct RecommendationSummary: Hashable {
    var text: String
    var nextStep: String
}
