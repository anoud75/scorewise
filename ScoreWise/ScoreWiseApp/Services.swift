import Foundation
import SwiftData
#if canImport(PDFKit)
import PDFKit
#endif
#if canImport(AuthenticationServices)
import AuthenticationServices
#endif
#if canImport(FirebaseCore)
import FirebaseCore
#endif
#if canImport(FirebaseAuth)
import FirebaseAuth
#endif
#if canImport(FirebaseFirestore)
import FirebaseFirestore
#endif
#if canImport(FirebaseFunctions)
import FirebaseFunctions
#endif
#if canImport(FirebaseStorage)
import FirebaseStorage
#endif

struct AuthSession: Equatable {
    var userID: String
    var email: String
    var displayName: String
    var providers: [String]
}

struct AISuggestedInputs {
    var criteria: [CriterionDraft]
    var draftScores: [ScoreDraft]
}

struct AIChatResponse: Codable {
    var content: String
    var recommendedActions: [String]
}

struct AIUserProfile: Codable, Hashable {
    var primaryUsage: String
    var decisionStyle: String
    var biggestChallenge: String
    var speedPreference: String
    var valuesRanking: [String]
    var interests: [String]
}

protocol AuthServicing {
    func restoreSession() async -> AuthSession?
    func signInWithEmail(email: String, password: String) async throws -> AuthSession
    func createAccount(email: String, password: String, fullName: String) async throws -> AuthSession
    func signInWithApple() async throws -> AuthSession
    func signInWithGoogle() async throws -> AuthSession
    func signOut() async throws
}

protocol AIservicing {
    func suggestRankingInputs(for draft: RankingDraft, context: UsageContext, extractedEvidence: [String], userProfile: AIUserProfile?) async throws -> AISuggestedInputs
    func generateClarifyingQuestions(for draft: RankingDraft, userProfile: AIUserProfile?) async throws -> [ClarifyingQuestionAnswer]
    func suggestDecisionOptions(for draft: RankingDraft, userProfile: AIUserProfile?) async throws -> [DecisionOptionSnapshot]
    func generateBiasChallenges(for draft: RankingDraft, preferredOption: String, userProfile: AIUserProfile?) async throws -> [BiasChallengeResponse]
    func decisionChat(projectID: String, phase: String, message: String, draft: RankingDraft?, userProfile: AIUserProfile?) async throws -> AIChatResponse
    func generateInsights(draft: RankingDraft, result: RankingResult, userProfile: AIUserProfile?) async throws -> InsightReportDraft
}

protocol PersistenceServicing {
    func saveProjectDraft(_ draft: RankingDraft, result: RankingResult?, insight: InsightReportDraft?, context: ModelContext) throws
    func loadProjects(for ownerUserID: String, context: ModelContext) throws -> [RankingProjectEntity]
    func saveProfile(_ profile: UserProfileEntity, context: ModelContext) throws
}

struct ExtractedAttachmentEvidence: Hashable {
    var attachmentID: String
    var extractedText: String
    var status: AttachmentValidationStatus
    var trustLevel: AttachmentTrustLevel
    var sourceHost: String
    var titleHint: String
    var validationMessage: String
}

protocol FileExtractionServicing {
    func extractEvidence(for attachments: [VendorAttachment]) async throws -> [ExtractedAttachmentEvidence]
}

protocol PDFExportServicing {
    func makePDF(project: RankingDraft, result: RankingResult, insight: InsightReportDraft?) throws -> URL
}

enum ScoreWiseServiceError: LocalizedError {
    case featureUnavailable(String)

    var errorDescription: String? {
        switch self {
        case let .featureUnavailable(message):
            return message
        }
    }
}

struct SurveyTagger {
    static let questions: [SurveyQuestion] = [
        SurveyQuestion(id: "purpose", title: "What is your primary usage?", options: ["Work", "Personal", "Education", "Other"]),
        SurveyQuestion(id: "pace", title: "How fast do you decide?", options: ["Very fast", "Balanced", "Very careful"]),
        SurveyQuestion(id: "risk", title: "Risk posture", options: ["Risk-averse", "Neutral", "Risk-taking"]),
        SurveyQuestion(id: "evidence", title: "How much evidence do you require?", options: ["Low", "Medium", "High"]),
        SurveyQuestion(id: "collaboration", title: "Decision style", options: ["Solo", "Team", "Executive"]),
        SurveyQuestion(id: "focus", title: "What matters most?", options: ["Cost", "Quality", "Speed", "Trust"]),
        SurveyQuestion(id: "planning", title: "Time horizon", options: ["Short-term", "Mid-term", "Long-term"]),
        SurveyQuestion(id: "review", title: "Do you revisit decisions?", options: ["Rarely", "Sometimes", "Often"])
    ]

    static func deriveTags(from answers: [SurveyAnswer]) -> [String] {
        var tags: Set<String> = []
        let map = Dictionary(uniqueKeysWithValues: answers.map { ($0.questionID, $0.value.lowercased()) })

        if map["risk"]?.contains("averse") == true { tags.insert("risk_averse") }
        if map["pace"]?.contains("fast") == true { tags.insert("speed_first") }
        if map["evidence"] == "high" { tags.insert("evidence_heavy") }
        if map["collaboration"] == "team" { tags.insert("collaborative") }
        if map["focus"] == "cost" { tags.insert("cost_sensitivity") }
        if map["planning"] == "long-term" { tags.insert("long_horizon") }
        if map["review"] == "often" { tags.insert("iterative_reviewer") }

        return tags.sorted()
    }
}

private enum AnthropicPromptBuilder {
    static func systemPrompt(profile: AIUserProfile?) -> String {
        let profileBlock: String
        if let profile {
            profileBlock = """
            User profile:
            - primary_usage: \(profile.primaryUsage)
            - decision_style: \(profile.decisionStyle)
            - biggest_challenge: \(profile.biggestChallenge)
            - speed_preference: \(profile.speedPreference)
            - values_ranking: \(profile.valuesRanking.joined(separator: ", "))
            - interests: \(profile.interests.joined(separator: ", "))
            """
        } else {
            profileBlock = "User profile: unavailable. Infer conservatively from the provided context."
        }

        return """
        You are Clarity, a strategic decision-support AI.
        Your job is to reduce bias, surface trade-offs, and turn ambiguous situations into structured decisions.
        Always prefer precise, evidence-seeking reasoning over generic advice.
        Never fabricate facts, sources, scores, or evidence.
        If uploaded files or links do not provide enough support, say what is unknown and lower confidence.
        Clearly separate direct evidence from inference.
        Prefer verifiable, source-grounded reasoning over persuasive language.
        Return valid JSON only when the user asks for JSON.
        Keep language concise, specific, and professional.

        \(profileBlock)
        """
    }

    static func rankingInputsPrompt(draft: RankingDraft, context: UsageContext, extractedEvidence: [String], profile: AIUserProfile?) -> String {
        """
        Given this decision context:
        - situation_text: \(draft.contextNarrative)
        - category: \(draft.category.rawValue)
        - usage_context: \(context.rawValue)
        - user_profile: \(profile.map { "\($0.decisionStyle), \($0.biggestChallenge), \($0.valuesRanking.joined(separator: ", "))" } ?? "unknown")
        - options: \(draft.vendors.map(\.name).joined(separator: " | "))
        - extracted_evidence: \(extractedEvidence.joined(separator: "\n"))

        Suggest 3-8 decision criteria with normalized weights summing to 100.
        Then draft a 1-10 score for each option against each criterion when evidence supports it.
        Use confidence from 0.0 to 1.0 and include a brief evidenceSnippet.

        Return JSON in this exact shape:
        {
          "criteria": [{"id":"...", "name":"...", "detail":"...", "category":"...", "weightPercent": 0}],
          "draftScores": [{"vendorID":"...", "criterionID":"...", "score": 0, "confidence": 0, "evidenceSnippet":"..."}]
        }
        Use the provided vendor ids and criterion ids you generate.
        """
    }

    static func clarifyingPrompt(draft: RankingDraft, profile: AIUserProfile?) -> String {
        """
        Given this situation: \(draft.contextNarrative)
        User profile: \(profile?.decisionStyle ?? "unknown"), \(profile?.biggestChallenge ?? "unknown"), \(profile?.valuesRanking.joined(separator: ", ") ?? "")
        Generate exactly 3 clarifying questions.
        Return as JSON array.
        """
    }

    static func optionsPrompt(draft: RankingDraft, profile: AIUserProfile?) -> String {
        let context = draft.clarifyingQuestions.map { "\($0.question): \($0.answer)" }.joined(separator: "\n")
        return """
        Given this situation: \(draft.contextNarrative)
        Clarifying answers: \(context)
        User profile: \(profile?.decisionStyle ?? "unknown"), \(profile?.biggestChallenge ?? "unknown")
        Suggest 2-3 realistic options. Include one creative or unexpected option.
        Return as JSON array with objects: {"label":"...", "description":"...", "aiSuggested":true}
        """
    }

    static func biasPrompt(draft: RankingDraft, preferredOption: String, profile: AIUserProfile?) -> String {
        """
        Given this decision context and the user's apparent preference for \(preferredOption):
        Situation: \(draft.contextNarrative)
        Clarifying answers: \(draft.clarifyingQuestions.map { "\($0.question): \($0.answer)" }.joined(separator: "\n"))
        User profile: \(profile?.decisionStyle ?? "unknown"), \(profile?.biggestChallenge ?? "unknown"), \(profile?.valuesRanking.joined(separator: ", ") ?? "")

        Select the 3 most relevant debiasing exercises from:
        [friend_test, ten_ten_ten, pre_mortem, worst_case, inversion, inaction_cost, values_check]

        Return as JSON array with:
        {"type":"...", "question":"...", "response":""}
        """
    }

    static func finalAnalysisPrompt(draft: RankingDraft, result: RankingResult, profile: AIUserProfile?) -> String {
        let qaPairs = draft.clarifyingQuestions.map { "\($0.question): \($0.answer)" }.joined(separator: "\n")
        let options = draft.vendors.map { "\($0.id): \($0.name) - \($0.notes)" }.joined(separator: "\n")
        let scorecard = draft.criteria.map { criterion in
            let scores = draft.scores.filter { $0.criterionID == criterion.id }.map { "\($0.vendorID)=\($0.score)" }.joined(separator: ", ")
            return "\(criterion.name) [\(criterion.weightPercent)%] -> \(scores)"
        }.joined(separator: "\n")
        let challengeResponses = draft.biasChallenges.map { "\($0.type.rawValue): \($0.response)" }.joined(separator: "\n")

        return """
        FULL CONTEXT:
        - Situation: \(draft.contextNarrative)
        - Clarifying answers: \(qaPairs)
        - Options: \(options)
        - Scorecard results: \(scorecard)
        - Bias challenge responses: \(challengeResponses)
        - User values (ranked): \(profile?.valuesRanking.joined(separator: ", ") ?? "")
        - User decision style: \(profile?.decisionStyle ?? "unknown")
        - Ranked totals: \(result.rankedVendors.map { "\($0.vendorName)=\($0.totalScore)" }.joined(separator: ", "))

        Generate:
        1. recommendation (1-2 sentences)
        2. trade_offs (3 bullet points comparing top 2 options)
        3. blind_spots (2-3 things user may not have considered)
        4. gut_check (1 sentence connecting to user's top value)
        5. next_step (1 concrete actionable suggestion)
        6. confidence as {"level":"low|medium|high","reasoning":"..."}

        Return as JSON in this exact shape:
        {
          "recommendation":"...",
          "trade_offs":["...","...","..."],
          "blind_spots":["...","..."],
          "gut_check":"...",
          "next_step":"...",
          "confidence":{"level":"medium","reasoning":"..."}
        }
        """
    }
}

final class LocalMockAuthService: AuthServicing {
    private var cached: AuthSession?

    func restoreSession() async -> AuthSession? { cached }

    func signInWithEmail(email: String, password: String) async throws -> AuthSession {
        let session = AuthSession(userID: UUID().uuidString, email: email, displayName: email.components(separatedBy: "@").first ?? "User", providers: ["password"])
        cached = session
        return session
    }

    func createAccount(email: String, password: String, fullName: String) async throws -> AuthSession {
        let session = AuthSession(userID: UUID().uuidString, email: email, displayName: fullName, providers: ["password"])
        cached = session
        return session
    }

    func signInWithApple() async throws -> AuthSession {
        let session = AuthSession(userID: UUID().uuidString, email: "apple-user@scorewise.app", displayName: "Apple User", providers: ["apple.com"])
        cached = session
        return session
    }

    func signInWithGoogle() async throws -> AuthSession {
        let session = AuthSession(userID: UUID().uuidString, email: "google-user@scorewise.app", displayName: "Google User", providers: ["google.com"])
        cached = session
        return session
    }

    func signOut() async throws {
        cached = nil
    }
}

struct LocalMockAIService: AIservicing {
    func suggestRankingInputs(for draft: RankingDraft, context: UsageContext, extractedEvidence: [String], userProfile: AIUserProfile?) async throws -> AISuggestedInputs {
        let contextBlob = [draft.contextNarrative] + extractedEvidence
        let seedText = contextBlob.joined(separator: " ").lowercased()
        var criteria = PromptEngineering.recommendedCriteria(from: seedText, context: context)
        if !draft.criteria.isEmpty {
            criteria = draft.criteria
        }

        let normalized = RankingEngine.normalizedCriteria(criteria)
        var scores: [ScoreDraft] = []
        for vendor in draft.vendors {
            for criterion in normalized {
                let score = Double(Int.random(in: 5 ... 9))
                let confidence = Double.random(in: 0.58 ... 0.92)
                scores.append(
                    ScoreDraft(
                        vendorID: vendor.id,
                        criterionID: criterion.id,
                        score: score,
                        source: .aiDraft,
                        confidence: confidence,
                        evidenceSnippet: PromptEngineering.evidenceSnippet(for: criterion.name, evidence: extractedEvidence)
                    )
                )
            }
        }
        return AISuggestedInputs(criteria: normalized, draftScores: scores)
    }

    func generateClarifyingQuestions(for draft: RankingDraft, userProfile: AIUserProfile?) async throws -> [ClarifyingQuestionAnswer] {
        [
            ClarifyingQuestionAnswer(question: "What is most at risk if this decision goes badly?", answer: ""),
            ClarifyingQuestionAnswer(question: "What constraint matters most right now?", answer: ""),
            ClarifyingQuestionAnswer(question: "What have you already ruled out or tested?", answer: "")
        ]
    }

    func suggestDecisionOptions(for draft: RankingDraft, userProfile: AIUserProfile?) async throws -> [DecisionOptionSnapshot] {
        draft.vendors.prefix(3).map {
            DecisionOptionSnapshot(id: $0.id, label: $0.name, description: $0.notes.isEmpty ? nil : $0.notes, aiSuggested: true)
        }
    }

    func generateBiasChallenges(for draft: RankingDraft, preferredOption: String, userProfile: AIUserProfile?) async throws -> [BiasChallengeResponse] {
        [
            BiasChallengeResponse(type: .friendTest, question: "If a close friend had this exact situation, what would you tell them?", response: ""),
            BiasChallengeResponse(type: .tenTenTen, question: "How will you feel about choosing \(preferredOption) in 10 minutes, 10 months, and 10 years?", response: ""),
            BiasChallengeResponse(type: .valuesCheck, question: "Which option best protects your top value under pressure?", response: "")
        ]
    }

    func decisionChat(projectID: String, phase: String, message: String, draft: RankingDraft?, userProfile: AIUserProfile?) async throws -> AIChatResponse {
        AIChatResponse(
            content: "Before finalizing, validate assumptions with measurable evidence. What would make this decision wrong in 6 months?",
            recommendedActions: [
                "Add one risk criterion for vendor lock-in.",
                "Stress-test top two weights with +/-10% sensitivity.",
                "Document one disqualifier per vendor."
            ]
        )
    }

    func generateInsights(draft: RankingDraft, result: RankingResult, userProfile: AIUserProfile?) async throws -> InsightReportDraft {
        let winnerName = result.rankedVendors.first?.vendorName ?? "No winner"
        let risk = result.tieDetected ? "Top candidates are statistically close. Add tie-break criteria." : "No immediate scoring tie; still validate strategic constraints."
        return InsightReportDraft(
            summary: "\(winnerName) leads based on weighted evidence across the selected criteria.",
            winnerReasoning: "The winner maintains stronger weighted consistency on high-impact criteria.",
            riskFlags: [risk, "Potential optimism bias in manually adjusted scores."],
            overlookedStrategicPoints: ["Contract exit terms", "Integration complexity", "Change-management impact"],
            sensitivityFindings: result.sensitivityFindings.map { finding in
                finding.winnerFlipped ? "Winner can flip if \(finding.criterionName) weight shifts." : "\(finding.criterionName) is stable under moderate weight change."
            }
        )
    }
}

final class AnthropicAIService: AIservicing {
    private let apiKey: String
    private let model: String
    private let session: URLSession
    private let fallback: AIservicing

    init(
        apiKey: String,
        model: String = ProcessInfo.processInfo.environment["ANTHROPIC_MODEL"] ?? "claude-opus-4-6",
        session: URLSession = .shared,
        fallback: AIservicing = LocalMockAIService()
    ) {
        self.apiKey = apiKey
        self.model = model
        self.session = session
        self.fallback = fallback
    }

    func suggestRankingInputs(for draft: RankingDraft, context: UsageContext, extractedEvidence: [String], userProfile: AIUserProfile?) async throws -> AISuggestedInputs {
        do {
            let text = try await sendMessage(
                system: AnthropicPromptBuilder.systemPrompt(profile: userProfile),
                user: AnthropicPromptBuilder.rankingInputsPrompt(draft: draft, context: context, extractedEvidence: extractedEvidence, profile: userProfile)
            )
            let payload = try parseJSONObject(text)
            return parseSuggestedInputs(payload, draft: draft)
        } catch {
            return try await fallback.suggestRankingInputs(for: draft, context: context, extractedEvidence: extractedEvidence, userProfile: userProfile)
        }
    }

    func generateClarifyingQuestions(for draft: RankingDraft, userProfile: AIUserProfile?) async throws -> [ClarifyingQuestionAnswer] {
        do {
            let text = try await sendMessage(
                system: AnthropicPromptBuilder.systemPrompt(profile: userProfile),
                user: AnthropicPromptBuilder.clarifyingPrompt(draft: draft, profile: userProfile)
            )
            let data = try parseJSONArray(text)
            let decoded = try JSONDecoder().decode([StringOrQuestion].self, from: data)
            return decoded.map { item in
                switch item {
                case let .string(question):
                    return ClarifyingQuestionAnswer(question: question, answer: "")
                case let .object(obj):
                    return ClarifyingQuestionAnswer(question: obj.question, answer: obj.answer ?? "")
                }
            }
        } catch {
            return try await fallback.generateClarifyingQuestions(for: draft, userProfile: userProfile)
        }
    }

    func suggestDecisionOptions(for draft: RankingDraft, userProfile: AIUserProfile?) async throws -> [DecisionOptionSnapshot] {
        do {
            let text = try await sendMessage(
                system: AnthropicPromptBuilder.systemPrompt(profile: userProfile),
                user: AnthropicPromptBuilder.optionsPrompt(draft: draft, profile: userProfile)
            )
            let data = try parseJSONArray(text)
            return try JSONDecoder().decode([DecisionOptionSnapshot].self, from: data)
        } catch {
            return try await fallback.suggestDecisionOptions(for: draft, userProfile: userProfile)
        }
    }

    func generateBiasChallenges(for draft: RankingDraft, preferredOption: String, userProfile: AIUserProfile?) async throws -> [BiasChallengeResponse] {
        do {
            let text = try await sendMessage(
                system: AnthropicPromptBuilder.systemPrompt(profile: userProfile),
                user: AnthropicPromptBuilder.biasPrompt(draft: draft, preferredOption: preferredOption, profile: userProfile)
            )
            let data = try parseJSONArray(text)
            return try JSONDecoder().decode([BiasChallengeResponse].self, from: data)
        } catch {
            return try await fallback.generateBiasChallenges(for: draft, preferredOption: preferredOption, userProfile: userProfile)
        }
    }

    func decisionChat(projectID: String, phase: String, message: String, draft: RankingDraft?, userProfile: AIUserProfile?) async throws -> AIChatResponse {
        do {
            let userMessage = """
            Decision chat phase: \(phase)
            Project ID: \(projectID)
            Current draft context: \(draft?.contextNarrative ?? "")
            User message: \(message)

            Respond with evidence-seeking guidance first. End with 0-3 recommended actions.
            Return JSON:
            {"content":"...", "recommendedActions":["..."]}
            """
            let text = try await sendMessage(
                system: AnthropicPromptBuilder.systemPrompt(profile: userProfile),
                user: userMessage
            )
            let data = try parseJSONObjectData(text)
            return try JSONDecoder().decode(AIChatResponse.self, from: data)
        } catch {
            return try await fallback.decisionChat(projectID: projectID, phase: phase, message: message, draft: draft, userProfile: userProfile)
        }
    }

    func generateInsights(draft: RankingDraft, result: RankingResult, userProfile: AIUserProfile?) async throws -> InsightReportDraft {
        do {
            let text = try await sendMessage(
                system: AnthropicPromptBuilder.systemPrompt(profile: userProfile),
                user: AnthropicPromptBuilder.finalAnalysisPrompt(draft: draft, result: result, profile: userProfile)
            )
            let data = try parseJSONObjectData(text)
            let raw = try JSONDecoder().decode(InsightPayload.self, from: data)
            let blindSpots = splitLinesOrArray(raw.blindSpots)
            let tradeoffs = splitLinesOrArray(raw.tradeOffs)
            let confidenceLine = "\(raw.confidence.level.uppercased()): \(raw.confidence.reasoning)"
            return InsightReportDraft(
                summary: tradeoffs.joined(separator: "\n"),
                winnerReasoning: raw.recommendation,
                riskFlags: blindSpots,
                overlookedStrategicPoints: [raw.nextStep],
                sensitivityFindings: [raw.gutCheck, confidenceLine]
            )
        } catch {
            return try await fallback.generateInsights(draft: draft, result: result, userProfile: userProfile)
        }
    }

    private func sendMessage(system: String, user: String) async throws -> String {
        guard let url = URL(string: "https://api.anthropic.com/v1/messages") else {
            throw ScoreWiseServiceError.featureUnavailable("Anthropic API URL is invalid.")
        }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(apiKey, forHTTPHeaderField: "x-api-key")
        request.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")

        let payload = AnthropicMessageRequest(
            model: model,
            maxTokens: 1000,
            system: system,
            messages: [AnthropicMessageRequest.Message(role: "user", content: user)]
        )
        request.httpBody = try JSONEncoder().encode(payload)

        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse, (200 ..< 300).contains(http.statusCode) else {
            let body = String(data: data, encoding: .utf8) ?? "Unknown response"
            throw ScoreWiseServiceError.featureUnavailable("Anthropic request failed: \(body)")
        }
        let decoded = try JSONDecoder().decode(AnthropicMessageResponse.self, from: data)
        return decoded.content.map(\.text).joined(separator: "\n")
    }

    private func parseJSONObject(_ text: String) throws -> [String: Any] {
        let data = try parseJSONObjectData(text)
        let object = try JSONSerialization.jsonObject(with: data)
        return object as? [String: Any] ?? [:]
    }

    private func parseJSONObjectData(_ text: String) throws -> Data {
        if let range = text.range(of: "\\{[\\s\\S]*\\}", options: .regularExpression) {
            return Data(text[range].utf8)
        }
        throw ScoreWiseServiceError.featureUnavailable("Claude did not return valid JSON object content.")
    }

    private func parseJSONArray(_ text: String) throws -> Data {
        if let range = text.range(of: "\\[[\\s\\S]*\\]", options: .regularExpression) {
            return Data(text[range].utf8)
        }
        throw ScoreWiseServiceError.featureUnavailable("Claude did not return valid JSON array content.")
    }

    private func parseSuggestedInputs(_ payload: [String: Any], draft: RankingDraft) -> AISuggestedInputs {
        let criteriaArray = payload["criteria"] as? [[String: Any]] ?? []
        let criteria = criteriaArray.map { item in
            CriterionDraft(
                id: item["id"] as? String ?? UUID().uuidString,
                name: item["name"] as? String ?? "Criterion",
                detail: item["detail"] as? String ?? "",
                category: item["category"] as? String ?? "General",
                weightPercent: item["weightPercent"] as? Double ?? 0
            )
        }

        let scoresArray = payload["draftScores"] as? [[String: Any]] ?? []
        let scores = scoresArray.map { item in
            ScoreDraft(
                vendorID: item["vendorID"] as? String ?? draft.vendors.first?.id ?? "",
                criterionID: item["criterionID"] as? String ?? criteria.first?.id ?? "",
                score: item["score"] as? Double ?? 0,
                source: .aiDraft,
                confidence: item["confidence"] as? Double ?? 0.5,
                evidenceSnippet: item["evidenceSnippet"] as? String ?? ""
            )
        }
        return AISuggestedInputs(criteria: criteria, draftScores: scores)
    }

    private func splitLinesOrArray(_ value: OneOrManyStrings) -> [String] {
        switch value {
        case let .one(text):
            return text
                .split(separator: "\n")
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines).replacingOccurrences(of: "- ", with: "") }
                .filter { !$0.isEmpty }
        case let .many(values):
            return values
        }
    }
}

private struct AnthropicMessageRequest: Codable {
    struct Message: Codable {
        var role: String
        var content: String
    }

    var model: String
    var maxTokens: Int
    var system: String
    var messages: [Message]

    enum CodingKeys: String, CodingKey {
        case model
        case maxTokens = "max_tokens"
        case system
        case messages
    }
}

private struct AnthropicMessageResponse: Codable {
    struct ContentBlock: Codable {
        var type: String
        var text: String
    }

    var content: [ContentBlock]
}

private enum StringOrQuestion: Decodable {
    case string(String)
    case object(QuestionObject)

    struct QuestionObject: Decodable {
        var question: String
        var answer: String?
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let string = try? container.decode(String.self) {
            self = .string(string)
        } else {
            self = .object(try container.decode(QuestionObject.self))
        }
    }
}

private struct InsightPayload: Decodable {
    struct ConfidencePayload: Decodable {
        var level: String
        var reasoning: String
    }

    var recommendation: String
    var tradeOffs: OneOrManyStrings
    var blindSpots: OneOrManyStrings
    var gutCheck: String
    var nextStep: String
    var confidence: ConfidencePayload

    enum CodingKeys: String, CodingKey {
        case recommendation
        case tradeOffs = "trade_offs"
        case blindSpots = "blind_spots"
        case gutCheck = "gut_check"
        case nextStep = "next_step"
        case confidence
    }
}

private enum OneOrManyStrings: Decodable {
    case one(String)
    case many([String])

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let string = try? container.decode(String.self) {
            self = .one(string)
        } else {
            self = .many(try container.decode([String].self))
        }
    }
}

#if canImport(FirebaseFunctions)
final class FirebaseFunctionsAIService: AIservicing {
    private let functions: Functions
    private let fallback: AIservicing

    init(functions: Functions = Functions.functions(), fallback: AIservicing = LocalMockAIService()) {
        self.functions = functions
        self.fallback = fallback
    }

    func suggestRankingInputs(for draft: RankingDraft, context: UsageContext, extractedEvidence: [String], userProfile: AIUserProfile?) async throws -> AISuggestedInputs {
        do {
            let payload: [String: Any] = [
                "projectId": draft.id,
                "usageContext": context.rawValue,
                "contextNarrative": draft.contextNarrative,
                "vendors": draft.vendors.map { ["id": $0.id, "name": $0.name, "notes": $0.notes] },
                "extractedText": extractedEvidence,
                "userProfile": userProfile.map(Self.userProfileDictionary)
            ]
            let result = try await functions.httpsCallable("suggestRankingInputs").call(payload)
            return parseSuggestedInputs(result.data, draft: draft)
        } catch {
            return try await fallback.suggestRankingInputs(for: draft, context: context, extractedEvidence: extractedEvidence, userProfile: userProfile)
        }
    }

    func generateClarifyingQuestions(for draft: RankingDraft, userProfile: AIUserProfile?) async throws -> [ClarifyingQuestionAnswer] {
        do {
            let payload: [String: Any] = [
                "projectId": draft.id,
                "situationText": draft.contextNarrative,
                "userProfile": userProfile.map(Self.userProfileDictionary)
            ]
            let result = try await functions.httpsCallable("generateClarifyingQuestions").call(payload)
            return Self.parseClarifyingQuestions(result.data)
        } catch {
            return try await fallback.generateClarifyingQuestions(for: draft, userProfile: userProfile)
        }
    }

    func suggestDecisionOptions(for draft: RankingDraft, userProfile: AIUserProfile?) async throws -> [DecisionOptionSnapshot] {
        do {
            let payload: [String: Any] = [
                "projectId": draft.id,
                "situationText": draft.contextNarrative,
                "clarifyingQuestions": draft.clarifyingQuestions.map { ["question": $0.question, "answer": $0.answer] },
                "userProfile": userProfile.map(Self.userProfileDictionary)
            ]
            let result = try await functions.httpsCallable("suggestDecisionOptions").call(payload)
            return Self.parseOptions(result.data)
        } catch {
            return try await fallback.suggestDecisionOptions(for: draft, userProfile: userProfile)
        }
    }

    func generateBiasChallenges(for draft: RankingDraft, preferredOption: String, userProfile: AIUserProfile?) async throws -> [BiasChallengeResponse] {
        do {
            let payload: [String: Any] = [
                "projectId": draft.id,
                "preferredOption": preferredOption,
                "situationText": draft.contextNarrative,
                "clarifyingQuestions": draft.clarifyingQuestions.map { ["question": $0.question, "answer": $0.answer] },
                "userProfile": userProfile.map(Self.userProfileDictionary)
            ]
            let result = try await functions.httpsCallable("generateBiasChallenges").call(payload)
            return Self.parseBiasChallenges(result.data)
        } catch {
            return try await fallback.generateBiasChallenges(for: draft, preferredOption: preferredOption, userProfile: userProfile)
        }
    }

    func decisionChat(projectID: String, phase: String, message: String, draft: RankingDraft?, userProfile: AIUserProfile?) async throws -> AIChatResponse {
        do {
            let payload: [String: Any] = [
                "projectId": projectID,
                "phase": phase,
                "message": message,
                "draft": draft.map { ["title": $0.title, "contextNarrative": $0.contextNarrative] },
                "userProfile": userProfile.map(Self.userProfileDictionary)
            ]
            let result = try await functions.httpsCallable("decisionChat").call(payload)
            guard let dictionary = result.data as? [String: Any] else {
                return try await fallback.decisionChat(projectID: projectID, phase: phase, message: message, draft: draft, userProfile: userProfile)
            }
            let content = dictionary["content"] as? String ?? "I need more context to provide a grounded recommendation."
            let actions = dictionary["recommendedActions"] as? [String] ?? []
            return AIChatResponse(content: content, recommendedActions: actions)
        } catch {
            return try await fallback.decisionChat(projectID: projectID, phase: phase, message: message, draft: draft, userProfile: userProfile)
        }
    }

    func generateInsights(draft: RankingDraft, result: RankingResult, userProfile: AIUserProfile?) async throws -> InsightReportDraft {
        do {
            let payload: [String: Any] = [
                "projectId": draft.id,
                "draft": [
                    "title": draft.title,
                    "usageContext": draft.usageContext.rawValue,
                    "contextNarrative": draft.contextNarrative,
                    "vendors": draft.vendors.map { ["id": $0.id, "name": $0.name] },
                    "criteria": draft.criteria.map { ["id": $0.id, "name": $0.name, "weightPercent": $0.weightPercent] }
                ],
                "result": [
                    "winnerID": result.winnerID ?? "",
                    "confidenceScore": result.confidenceScore,
                    "tieDetected": result.tieDetected,
                    "rankedVendors": result.rankedVendors.map { ["vendorID": $0.vendorID, "vendorName": $0.vendorName, "totalScore": $0.totalScore] }
                ],
                "userProfile": userProfile.map(Self.userProfileDictionary)
            ]
            let raw = try await functions.httpsCallable("generateInsights").call(payload)
            guard let dictionary = raw.data as? [String: Any] else {
                return try await fallback.generateInsights(draft: draft, result: result, userProfile: userProfile)
            }
            return InsightReportDraft(
                summary: dictionary["summary"] as? String ?? "",
                winnerReasoning: dictionary["winnerReasoning"] as? String ?? "",
                riskFlags: dictionary["riskFlags"] as? [String] ?? [],
                overlookedStrategicPoints: dictionary["overlookedStrategicPoints"] as? [String] ?? [],
                sensitivityFindings: dictionary["sensitivityFindings"] as? [String] ?? []
            )
        } catch {
            return try await fallback.generateInsights(draft: draft, result: result, userProfile: userProfile)
        }
    }

    private static func userProfileDictionary(_ profile: AIUserProfile) -> [String: Any] {
        [
            "primaryUsage": profile.primaryUsage,
            "decisionStyle": profile.decisionStyle,
            "biggestChallenge": profile.biggestChallenge,
            "speedPreference": profile.speedPreference,
            "valuesRanking": profile.valuesRanking,
            "interests": profile.interests
        ]
    }

    private static func parseClarifyingQuestions(_ raw: Any) -> [ClarifyingQuestionAnswer] {
        guard let array = raw as? [Any] else { return [] }
        return array.compactMap {
            if let text = $0 as? String {
                return ClarifyingQuestionAnswer(question: text, answer: "")
            }
            if let dict = $0 as? [String: Any] {
                return ClarifyingQuestionAnswer(
                    question: dict["question"] as? String ?? "",
                    answer: dict["answer"] as? String ?? ""
                )
            }
            return nil
        }
    }

    private static func parseOptions(_ raw: Any) -> [DecisionOptionSnapshot] {
        guard let array = raw as? [[String: Any]] else { return [] }
        return array.map {
            DecisionOptionSnapshot(
                id: $0["id"] as? String ?? UUID().uuidString,
                label: $0["label"] as? String ?? "Option",
                description: $0["description"] as? String,
                aiSuggested: $0["aiSuggested"] as? Bool ?? true
            )
        }
    }

    private static func parseBiasChallenges(_ raw: Any) -> [BiasChallengeResponse] {
        guard let array = raw as? [[String: Any]] else { return [] }
        return array.compactMap {
            guard let rawType = $0["type"] as? String, let type = BiasChallengeType(rawValue: rawType) else {
                return nil
            }
            return BiasChallengeResponse(
                type: type,
                question: $0["question"] as? String ?? "",
                response: $0["response"] as? String ?? ""
            )
        }
    }

    private func parseSuggestedInputs(_ raw: Any, draft: RankingDraft) -> AISuggestedInputs {
        guard let dictionary = raw as? [String: Any] else {
            return AISuggestedInputs(criteria: draft.criteria, draftScores: [])
        }
        let criteriaArray = dictionary["criteria"] as? [[String: Any]] ?? []
        let criteria = criteriaArray.map { item in
            CriterionDraft(
                id: item["id"] as? String ?? UUID().uuidString,
                name: item["name"] as? String ?? "Criterion",
                detail: item["detail"] as? String ?? "",
                category: item["category"] as? String ?? "General",
                weightPercent: item["weightPercent"] as? Double ?? 0
            )
        }

        let scoresArray = dictionary["draftScores"] as? [[String: Any]] ?? []
        let scores = scoresArray.map { item in
            ScoreDraft(
                vendorID: item["vendorID"] as? String ?? "",
                criterionID: item["criterionID"] as? String ?? "",
                score: item["score"] as? Double ?? 0,
                source: .aiDraft,
                confidence: item["confidence"] as? Double ?? 0.5,
                evidenceSnippet: item["evidenceSnippet"] as? String ?? ""
            )
        }
        return AISuggestedInputs(criteria: criteria, draftScores: scores)
    }
}
#endif

struct SwiftDataPersistenceService: PersistenceServicing {
    func saveProjectDraft(_ draft: RankingDraft, result: RankingResult?, insight: InsightReportDraft?, context: ModelContext) throws {
        let encoder = JSONEncoder()
        let clarifyingQuestionsJSON = String(data: (try? encoder.encode(draft.clarifyingQuestions)) ?? Data("[]".utf8), encoding: .utf8) ?? "[]"
        let options = draft.vendors.map {
            DecisionOptionSnapshot(
                id: $0.id,
                label: $0.name,
                description: $0.notes.isEmpty ? nil : $0.notes,
                aiSuggested: false
            )
        }
        let optionsJSON = String(data: (try? encoder.encode(options)) ?? Data("[]".utf8), encoding: .utf8) ?? "[]"
        let biasChallengesJSON = String(data: (try? encoder.encode(draft.biasChallenges)) ?? Data("[]".utf8), encoding: .utf8) ?? "[]"
        let aiRecommendation = result?.rankedVendors.first?.vendorName ?? insight?.winnerReasoning ?? ""

        let entity = RankingProjectEntity(
            id: draft.id,
            ownerUserID: "local",
            title: draft.title,
            statusRaw: draft.decisionStatus.rawValue,
            usageContextRaw: draft.usageContext.rawValue,
            situationText: draft.contextNarrative,
            categoryRaw: draft.category.rawValue,
            voiceInputURL: draft.voiceInputURL ?? "",
            clarifyingQuestionsJSON: clarifyingQuestionsJSON,
            optionsJSON: optionsJSON,
            biasChallengesJSON: biasChallengesJSON,
            vendorCount: draft.vendors.count,
            criteriaCount: draft.criteria.count,
            winningVendorID: result?.winnerID ?? "",
            confidenceScore: result?.confidenceScore ?? 0,
            aiRecommendation: aiRecommendation,
            aiTradeOffs: insight?.summary ?? "",
            aiBlindSpots: insight?.riskFlags.joined(separator: "\n") ?? "",
            aiGutCheck: insight?.winnerReasoning ?? "",
            aiNextStep: insight?.overlookedStrategicPoints.first ?? "",
            aiConfidenceRaw: confidenceBucket(for: result?.confidenceScore ?? 0).rawValue,
            chosenOptionID: draft.chosenOptionID ?? "",
            followUpDate: draft.followUpDate,
            outcomeRating: draft.outcomeRating,
            outcomeNotes: draft.outcomeNotes,
            createdAt: .now,
            updatedAt: .now,
            lastComputedAt: .now
        )
        context.insert(entity)

        for vendor in draft.vendors {
            let attachmentsData = try? JSONEncoder().encode(vendor.attachments)
            context.insert(
                VendorEntity(
                    id: vendor.id,
                    projectID: draft.id,
                    name: vendor.name,
                    notes: vendor.notes,
                    attachmentsJSON: String(data: attachmentsData ?? Data(), encoding: .utf8) ?? "[]"
                )
            )
        }

        for criterion in draft.criteria {
            context.insert(
                CriterionEntity(
                    id: criterion.id,
                    projectID: draft.id,
                    name: criterion.name,
                    detail: criterion.detail,
                    category: criterion.category,
                    weightPercent: criterion.weightPercent
                )
            )
        }

        for score in draft.scores {
            context.insert(
                ScoreEntryEntity(
                    id: score.id,
                    projectID: draft.id,
                    vendorID: score.vendorID,
                    criterionID: score.criterionID,
                    score: score.score,
                    sourceRaw: score.source.rawValue,
                    confidence: score.confidence,
                    evidenceSnippet: score.evidenceSnippet
                )
            )
        }

        let snapshot = try? encoder.encode(draft)
        context.insert(
            ProjectVersionEntity(
                id: UUID().uuidString,
                projectID: draft.id,
                versionNumber: 1,
                snapshotJSON: String(data: snapshot ?? Data(), encoding: .utf8) ?? "{}"
            )
        )

        try context.save()
    }

    func loadProjects(for ownerUserID: String, context: ModelContext) throws -> [RankingProjectEntity] {
        let descriptor = FetchDescriptor<RankingProjectEntity>(
            sortBy: [SortDescriptor(\RankingProjectEntity.updatedAt, order: .reverse)]
        )
        return try context.fetch(descriptor)
    }

    func saveProfile(_ profile: UserProfileEntity, context: ModelContext) throws {
        context.insert(profile)
        try context.save()
    }

    private func confidenceBucket(for score: Double) -> AIConfidence {
        switch score {
        case ..<0.45:
            return .low
        case ..<0.75:
            return .medium
        default:
            return .high
        }
    }
}

struct LocalFileExtractionService: FileExtractionServicing {
    private let session: URLSession = .shared

    func extractEvidence(for attachments: [VendorAttachment]) async throws -> [ExtractedAttachmentEvidence] {
        var extracted: [ExtractedAttachmentEvidence] = []

        for attachment in attachments {
            extracted.append(try await extractSingleAttachment(attachment))
        }

        return extracted
    }

    private func extractSingleAttachment(_ attachment: VendorAttachment) async throws -> ExtractedAttachmentEvidence {
        if let remoteURL = remoteURL(from: attachment.cloudPath) {
            return try await extractRemotePage(from: remoteURL, attachment: attachment)
        }

        let fileURL = URL(fileURLWithPath: attachment.cloudPath)
        guard FileManager.default.fileExists(atPath: fileURL.path) else {
            return ExtractedAttachmentEvidence(
                attachmentID: attachment.id,
                extractedText: "",
                status: .unreadable,
                trustLevel: .uploaded,
                sourceHost: "",
                titleHint: attachment.fileName,
                validationMessage: "Content could not be opened locally."
            )
        }

        let ext = fileURL.pathExtension.lowercased()
        if ext == "pdf" {
            return extractPDF(from: fileURL, fileName: attachment.fileName, attachmentID: attachment.id)
        }
        if ["txt", "md", "csv", "json", "xml", "html", "htm"].contains(ext) {
            let raw = (try? String(contentsOf: fileURL, encoding: .utf8))
                ?? (try? String(contentsOf: fileURL, encoding: .unicode))
                ?? (try? String(contentsOf: fileURL, encoding: .ascii))
            guard let raw else {
                return ExtractedAttachmentEvidence(
                    attachmentID: attachment.id,
                    extractedText: "",
                    status: .unreadable,
                    trustLevel: .uploaded,
                    sourceHost: "",
                    titleHint: attachment.fileName,
                    validationMessage: "Text extraction failed."
                )
            }
            return ExtractedAttachmentEvidence(
                attachmentID: attachment.id,
                extractedText: formattedEvidence(title: attachment.fileName, body: sanitizedText(raw)),
                status: .ready,
                trustLevel: .uploaded,
                sourceHost: "",
                titleHint: attachment.fileName,
                validationMessage: "Attached file parsed."
            )
        }

        return ExtractedAttachmentEvidence(
            attachmentID: attachment.id,
            extractedText: "",
            status: .needsReview,
            trustLevel: .uploaded,
            sourceHost: "",
            titleHint: attachment.fileName,
            validationMessage: "This file type is not directly parsed yet."
        )
    }

    private func remoteURL(from raw: String) -> URL? {
        guard let url = URL(string: raw), let scheme = url.scheme?.lowercased(), scheme == "http" || scheme == "https" else {
            return nil
        }
        return url
    }

    private func extractRemotePage(from url: URL, attachment: VendorAttachment) async throws -> ExtractedAttachmentEvidence {
        let (data, response) = try await session.data(from: url)
        let mimeType = (response as? HTTPURLResponse)?.value(forHTTPHeaderField: "Content-Type") ?? ""
        let body = String(data: data.prefix(150_000), encoding: .utf8)
            ?? String(data: data.prefix(150_000), encoding: .unicode)
            ?? ""
        let host = url.host?.lowercased() ?? ""
        let title = titleFromHTML(body) ?? attachment.titleHint.nonEmpty ?? attachment.fileName
        let trust = trustLevel(for: url)

        if mimeType.contains("text/html") || body.lowercased().contains("<html") {
            let cleaned = sanitizeHTML(body)
            return ExtractedAttachmentEvidence(
                attachmentID: attachment.id,
                extractedText: formattedEvidence(title: url.absoluteString, body: cleaned),
                status: cleaned.isEmpty ? .needsReview : .ready,
                trustLevel: trust,
                sourceHost: host,
                titleHint: title,
                validationMessage: cleaned.isEmpty ? "Page loaded, but no readable text was extracted." : "Link validated and readable."
            )
        }

        if mimeType.contains("text") || mimeType.contains("json") || mimeType.contains("xml") {
            let cleaned = sanitizedText(body)
            return ExtractedAttachmentEvidence(
                attachmentID: attachment.id,
                extractedText: formattedEvidence(title: title, body: cleaned),
                status: cleaned.isEmpty ? .needsReview : .ready,
                trustLevel: trust,
                sourceHost: host,
                titleHint: title,
                validationMessage: cleaned.isEmpty ? "Link loaded, but the content needs manual review." : "Link validated and readable."
            )
        }

        return ExtractedAttachmentEvidence(
            attachmentID: attachment.id,
            extractedText: "",
            status: .needsReview,
            trustLevel: trust,
            sourceHost: host,
            titleHint: title,
            validationMessage: "The link resolved, but its content type could not be read as text."
        )
    }

    private func extractPDF(from url: URL, fileName: String, attachmentID: String) -> ExtractedAttachmentEvidence {
        #if canImport(PDFKit)
        guard let document = PDFDocument(url: url) else {
            return ExtractedAttachmentEvidence(
                attachmentID: attachmentID,
                extractedText: "",
                status: .unreadable,
                trustLevel: .uploaded,
                sourceHost: "",
                titleHint: fileName,
                validationMessage: "The PDF could not be read."
            )
        }
        let text = (0 ..< document.pageCount)
            .compactMap { document.page(at: $0)?.string }
            .joined(separator: "\n")
        let cleaned = sanitizedText(text)
        return ExtractedAttachmentEvidence(
            attachmentID: attachmentID,
            extractedText: formattedEvidence(title: fileName, body: cleaned),
            status: cleaned.isEmpty ? .needsReview : .ready,
            trustLevel: .uploaded,
            sourceHost: "",
            titleHint: fileName,
            validationMessage: cleaned.isEmpty ? "The PDF loaded, but readable text was not extracted." : "PDF parsed."
        )
        #else
        return ExtractedAttachmentEvidence(
            attachmentID: attachmentID,
            extractedText: "",
            status: .needsReview,
            trustLevel: .uploaded,
            sourceHost: "",
            titleHint: fileName,
            validationMessage: "PDF extraction is unavailable in this build."
        )
        #endif
    }

    private func formattedEvidence(title: String, body: String) -> String {
        let trimmedBody = String(body.prefix(4_000))
        return "Source: \(title)\n\(trimmedBody)"
    }

    private func sanitizedText(_ raw: String) -> String {
        raw
            .replacingOccurrences(of: "\r", with: "\n")
            .components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .joined(separator: "\n")
    }

    private func sanitizeHTML(_ html: String) -> String {
        var cleaned = html.replacingOccurrences(of: "<script[\\s\\S]*?</script>", with: " ", options: .regularExpression)
        cleaned = cleaned.replacingOccurrences(of: "<style[\\s\\S]*?</style>", with: " ", options: .regularExpression)
        cleaned = cleaned.replacingOccurrences(of: "<[^>]+>", with: " ", options: .regularExpression)
        cleaned = cleaned.replacingOccurrences(of: "&nbsp;", with: " ")
        cleaned = cleaned.replacingOccurrences(of: "&amp;", with: "&")
        cleaned = cleaned.replacingOccurrences(of: "&quot;", with: "\"")
        return sanitizedText(cleaned)
    }

    private func titleFromHTML(_ html: String) -> String? {
        guard let match = html.range(of: "<title[^>]*>(.*?)</title>", options: [.regularExpression, .caseInsensitive]) else {
            return nil
        }
        let title = String(html[match])
            .replacingOccurrences(of: "<title[^>]*>", with: "", options: [.regularExpression, .caseInsensitive])
            .replacingOccurrences(of: "</title>", with: "", options: [.regularExpression, .caseInsensitive])
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return title.isEmpty ? nil : title
    }

    private func trustLevel(for url: URL) -> AttachmentTrustLevel {
        let host = url.host?.lowercased() ?? ""
        if host.hasSuffix(".gov") || host.hasSuffix(".edu") || host.contains("developer.apple.com") || host.contains("docs.") {
            return .official
        }
        if host.contains("github.com") || host.contains("medium.com") || host.contains("notion.site") {
            return .known
        }
        if url.scheme?.lowercased() == "https" {
            return .external
        }
        return .unknown
    }
}

enum PromptEngineering {
    static func recommendedCriteria(from contextBlob: String, context: UsageContext) -> [CriterionDraft] {
        var candidates: [CriterionDraft] = [
            CriterionDraft(name: "Total Cost", detail: "All-in cost over the decision horizon", category: "Financial", weightPercent: 24),
            CriterionDraft(name: "Implementation Risk", detail: "Execution and rollout risk", category: "Risk", weightPercent: 18),
            CriterionDraft(name: "Outcome Quality", detail: "Expected reliability and performance", category: "Performance", weightPercent: 22),
            CriterionDraft(name: "Support & Responsiveness", detail: "Vendor support quality and speed", category: "Operations", weightPercent: 16),
            CriterionDraft(name: "Scalability", detail: "Ability to support future growth", category: "Strategy", weightPercent: 20)
        ]

        if contextBlob.contains("security") || contextBlob.contains("compliance") {
            candidates.append(
                CriterionDraft(name: "Security & Compliance", detail: "Regulatory and security posture", category: "Risk", weightPercent: 18)
            )
        }
        if contextBlob.contains("integration") || contextBlob.contains("api") {
            candidates.append(
                CriterionDraft(name: "Integration Fit", detail: "Compatibility with existing stack", category: "Technical", weightPercent: 16)
            )
        }
        if contextBlob.contains("timeline") || contextBlob.contains("deadline") {
            candidates.append(
                CriterionDraft(name: "Time-to-Value", detail: "Speed to measurable impact", category: "Execution", weightPercent: 18)
            )
        }
        if context == .education {
            candidates.append(
                CriterionDraft(name: "Learning Curve", detail: "Ease of adoption and training burden", category: "Adoption", weightPercent: 14)
            )
        }

        return Array(candidates.prefix(8))
    }

    static func evidenceSnippet(for criterion: String, evidence: [String]) -> String {
        guard let first = evidence.first else {
            return "Drafted using context narrative and decision-science defaults."
        }
        return "Grounded on extracted evidence: \(first.prefix(110))"
    }
}

final class FirebaseBootstrap {
    static func configureIfPossible() {
        #if canImport(FirebaseCore)
        if FirebaseApp.app() == nil {
            FirebaseApp.configure()
        }
        #endif
    }
}

struct AppServices {
    let auth: AuthServicing
    let ai: AIservicing
    let persistence: PersistenceServicing
    let extractor: FileExtractionServicing
    let pdf: PDFExportServicing

    static var live: AppServices {
        FirebaseBootstrap.configureIfPossible()
        let aiService: AIservicing = {
            let allowDirect = ProcessInfo.processInfo.environment["SCOREWISE_ALLOW_DIRECT_AI_DEBUG"] == "1"
            if allowDirect, let apiKey = ProcessInfo.processInfo.environment["ANTHROPIC_API_KEY"], !apiKey.isEmpty {
                return AnthropicAIService(apiKey: apiKey)
            }
            #if canImport(FirebaseFunctions)
            return FirebaseFunctionsAIService(fallback: LocalMockAIService())
            #else
            return LocalMockAIService()
            #endif
        }()
        return AppServices(
            auth: LocalMockAuthService(),
            ai: aiService,
            persistence: SwiftDataPersistenceService(),
            extractor: LocalFileExtractionService(),
            pdf: PDFExportService()
        )
    }
}

private extension String {
    var nonEmpty: String? {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
