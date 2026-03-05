import Foundation

struct SituationParser {
    func parse(draft: RankingDraft, extractedEvidence: [String]) -> ParsedSituation {
        let narrative = draft.contextNarrative.trimmingCharacters(in: .whitespacesAndNewlines)
        let contextParts = [
            narrative,
            draft.conversationSummary,
            draft.alternativePathAnswer ?? "",
            draft.vendors.map { "\($0.name) \($0.notes)" }.joined(separator: "\n"),
            extractedEvidence.joined(separator: "\n")
        ]
        let combined = contextParts.joined(separator: "\n")
        let lower = combined.lowercased()
        let recruiterTerms = ["candidate", "recruit", "recruiter", "hiring", "interview", "fit for role", "shortlist", "cv", "resume"]
        let isRecruiter = recruiterTerms.contains(where: lower.contains)

        let inferredCategory: DecisionCategory
        if isRecruiter || lower.contains("job offer") || lower.contains("salary") || lower.contains("role") {
            inferredCategory = .career
        } else if lower.contains("vendor") || lower.contains("provider") || lower.contains("proposal") {
            inferredCategory = .business
        } else if lower.contains("tuition") || lower.contains("course") || lower.contains("degree") {
            inferredCategory = .education
        } else if lower.contains("investment") || lower.contains("mortgage") || lower.contains("loan") {
            inferredCategory = .finance
        } else {
            inferredCategory = draft.category
        }

        return ParsedSituation(
            narrative: narrative,
            combinedContext: combined,
            inferredCategory: inferredCategory,
            usageContext: draft.usageContext,
            isRecruiterMode: isRecruiter,
            explicitOptions: [],
            comparableOptionCheck: ComparableOptionCheck(comparable: true, detectedType: nil, violations: [])
        )
    }
}
