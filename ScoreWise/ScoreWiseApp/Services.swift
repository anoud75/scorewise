import Foundation
import SwiftData
#if canImport(PDFKit)
import PDFKit
#endif
#if canImport(UserNotifications)
import UserNotifications
#endif
#if canImport(Vision)
import Vision
#endif
#if canImport(UIKit)
import UIKit
#endif
#if canImport(ImageIO)
import ImageIO
#endif
#if canImport(CryptoKit)
import CryptoKit
#endif
#if canImport(AuthenticationServices)
import AuthenticationServices
#endif
#if canImport(GoogleSignIn)
import GoogleSignIn
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
    var citations: [EvidenceCitation] = []
}

struct AIChatResponse: Codable {
    var content: String
    var recommendedActions: [String]
    var citations: [EvidenceCitation]

    enum CodingKeys: String, CodingKey {
        case content
        case recommendedActions
        case citations
    }

    init(content: String, recommendedActions: [String], citations: [EvidenceCitation] = []) {
        self.content = content
        self.recommendedActions = recommendedActions
        self.citations = citations
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        content = try container.decodeIfPresent(String.self, forKey: .content) ?? ""
        recommendedActions = try container.decodeIfPresent([String].self, forKey: .recommendedActions) ?? []
        citations = try container.decodeIfPresent([EvidenceCitation].self, forKey: .citations) ?? []
    }
}

private func parseEvidenceCitations(_ raw: Any) -> [EvidenceCitation] {
    guard let array = raw as? [[String: Any]] else { return [] }
    return array.compactMap { item in
        let cardID = (item["cardId"] as? String ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let sourceLabel = (item["sourceLabel"] as? String ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let usageRaw = (item["usedFor"] as? String ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cardID.isEmpty, !sourceLabel.isEmpty else { return nil }
        let usedFor = EvidenceCitationUsage(rawValue: usageRaw) ?? .recommendation
        return EvidenceCitation(cardId: cardID, sourceLabel: sourceLabel, usedFor: usedFor)
    }
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
    func generateDecisionBrief(for draft: RankingDraft, extractedEvidence: [String], userProfile: AIUserProfile?) async throws -> DecisionBrief
    func suggestRankingInputs(for draft: RankingDraft, context: UsageContext, extractedEvidence: [String], userProfile: AIUserProfile?) async throws -> AISuggestedInputs
    func generateClarifyingQuestions(for draft: RankingDraft, userProfile: AIUserProfile?) async throws -> [ClarifyingQuestionAnswer]
    func suggestDecisionOptions(for draft: RankingDraft, userProfile: AIUserProfile?) async throws -> [DecisionOptionSnapshot]
    func generateBiasChallenges(for draft: RankingDraft, preferredOption: String, userProfile: AIUserProfile?) async throws -> [BiasChallengeResponse]
    func startDecisionConversation(projectID: String, contextNarrative: String, usageContext: UsageContext, userProfile: AIUserProfile?) async throws -> DecisionConversationResponse
    func continueDecisionConversation(projectID: String, transcript: [DecisionChatMessage], latestUserResponse: String, selectedOptionIndex: Int?, draft: RankingDraft, userProfile: AIUserProfile?) async throws -> DecisionConversationResponse
    func finalizeConversationForMatrix(projectID: String, transcript: [DecisionChatMessage], draft: RankingDraft, userProfile: AIUserProfile?) async throws -> DecisionMatrixSetup
    func decisionChat(projectID: String, phase: String, message: String, draft: RankingDraft?, userProfile: AIUserProfile?) async throws -> AIChatResponse
    func generateInsights(draft: RankingDraft, result: RankingResult, userProfile: AIUserProfile?) async throws -> InsightReportDraft
}

protocol PersistenceServicing {
    func saveProjectDraft(_ draft: RankingDraft, ownerUserID: String, result: RankingResult?, insight: InsightReportDraft?, context: ModelContext) throws
    func loadProjects(for ownerUserID: String, context: ModelContext) throws -> [RankingProjectEntity]
    func loadProjectDraft(for projectID: String, context: ModelContext) throws -> RankingDraft?
    func saveProfile(_ profile: UserProfileEntity, context: ModelContext) throws
    func loadProfile(for userID: String, context: ModelContext) throws -> UserProfileEntity?
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

protocol NotificationServicing {
    func requestAuthorizationIfNeeded() async -> Bool
    func scheduleFollowUp(for draft: RankingDraft, result: RankingResult?) async throws
    func cancelFollowUp(for projectID: String) async
    func cancelAllFollowUps() async
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
            USER PROFILE:
            - primary_usage: \(profile.primaryUsage)
            - decision_style: \(profile.decisionStyle)
            - biggest_challenge: \(profile.biggestChallenge)
            - speed_preference: \(profile.speedPreference)
            - values_ranking: \(profile.valuesRanking.joined(separator: ", "))
            - interests: \(profile.interests.joined(separator: ", "))
            """
        } else {
            profileBlock = "USER PROFILE: unavailable. Infer conservatively from context."
        }

        return """
        You are Clarity, ScoreWise's decision-science AI. You are NOT a general-purpose assistant. You exist to help users make better decisions by reducing cognitive bias, surfacing hidden trade-offs, and structuring ambiguous situations into evaluable frameworks.

        CORE PRINCIPLES:
        - You are a decision strategist, not an advisor. Never tell users what to choose; help them see what they're missing.
        - EVIDENCE OVER OPINION: Ground claims in evidence. When absent, say so and lower confidence.
        - SEPARATE FACT FROM INFERENCE: Use "This suggests..." for inferences.
        - CRITERIA MUST BE ORTHOGONAL: MECE principle. No overlapping criteria.
        - WEIGHTS REFLECT VALUES: Frame as "how much does this matter to YOUR situation."
        - ACTIVE DEBIASING: Counter bias, don't just identify it.
        - UNCERTAINTY IS INFORMATION: A 0.4 confidence is better than fabricated certainty.

        STRICT RULES:
        - Preserve user-provided names exactly.
        - Never replace known names with placeholders (Vendor A/B, Option A/B, Candidate 1/2).
        - Do not introduce strategy options (pilot/negotiate/hybrid) unless explicitly listed as primary options.
        - If 2+ explicit options exist, keep scope strictly to those options.

        RESPONSE STYLE:
        - Direct, concise, concrete language.
        - Challenge respectfully.
        - Return valid JSON only when JSON is requested.

        \(profileBlock)
        """
    }

    static func rankingInputsPrompt(draft: RankingDraft, context: UsageContext, extractedEvidence: [String], profile: AIUserProfile?) -> String {
        """
        DECISION CONTEXT:
        - Situation: \(draft.contextNarrative)
        - Category: \(draft.category.rawValue)
        - Usage context: \(context.rawValue)
        - Options: \(draft.vendors.map(\.name).joined(separator: " | "))
        - User profile: style=\(profile?.decisionStyle ?? "unknown"), challenge=\(profile?.biggestChallenge ?? "unknown"), values=\(profile?.valuesRanking.joined(separator: ", ") ?? "unknown")
        - Evidence: \(extractedEvidence.joined(separator: "\n"))

        STEP 1 — CRITERIA (3-8, MECE):
        - ONE distinct dimension each.
        - Specific to THIS decision.
        - Include at least one RISK/DOWNSIDE criterion.
        - Include at least one REVERSIBILITY/EXIT COST criterion.
        - Weights reflect user values.

        STEP 2 — SCORES (1-10):
        - Score only when evidence supports it. No evidence -> confidence < 0.3.
        - Differentiate meaningfully across options.
        - evidenceSnippet cites evidence or states "No direct evidence — estimated from [reasoning]."

        Return ONLY valid JSON:
        {
          "criteria": [{"id":"c1", "name":"...", "detail":"...", "category":"...", "weightPercent": 0}],
          "draftScores": [{"vendorID":"...", "criterionID":"...", "score": 0, "confidence": 0.0, "evidenceSnippet":"..."}],
          "methodNotes": ["assumptions and what changes if wrong"]
        }
        Weights sum to exactly 100. Vendor IDs: \(draft.vendors.map(\.id).joined(separator: ", "))
        """
    }

    static func clarifyingPrompt(draft: RankingDraft, profile: AIUserProfile?) -> String {
        """
        You are helping a user structure a decision.

        SITUATION: \(draft.contextNarrative)
        CATEGORY: \(draft.category.rawValue)
        USER PROFILE: style=\(profile?.decisionStyle ?? "unknown"), challenge=\(profile?.biggestChallenge ?? "unknown"), values=\(profile?.valuesRanking.joined(separator: ", ") ?? "unknown")

        Generate 6-12 short closed-ended questions tailored to THIS case.

        RULES:
        - Questions must be answerable with Yes/No, A/B, scale, or fixed-choice.
        - Include questions that probe constraints, risk tolerance, hidden stakeholders, and second-order effects.
        - Avoid generic prompts like "Tell me more."
        - Use one sentence per question.

        Return ONLY a JSON array:
        [{"question":"...", "answer":""}]
        """
    }

    static func decisionBriefPrompt(draft: RankingDraft, extractedEvidence: [String], profile: AIUserProfile?) -> String {
        """
        Build a structured decision brief from this case.

        Situation:
        \(draft.contextNarrative)

        Current options already captured:
        \(draft.vendors.map { "- \($0.name): \($0.notes)" }.joined(separator: "\n"))

        Clarifying answers:
        \(draft.clarifyingQuestions.map { "- \($0.question): \($0.answer)" }.joined(separator: "\n"))

        Alternative path answer:
        \(draft.alternativePathAnswer ?? "")

        Extracted evidence:
        \(extractedEvidence.joined(separator: "\n"))

        User profile:
        \(profile.map { "\($0.primaryUsage), \($0.decisionStyle), \($0.biggestChallenge), \($0.valuesRanking.joined(separator: ", "))" } ?? "unknown")

        Return JSON with this exact shape:
        {
          "summary":"...",
          "inferredCategory":"career|finance|health|relationships|business|education|lifestyle|creativity",
          "detectedOptions":[{"label":"...","description":"...","aiSuggested":true}],
          "goals":["..."],
          "constraints":["..."],
          "risks":["..."],
          "tensions":["..."],
          "suggestedCriteria":[{"name":"...","detail":"...","category":"...","weightPercent":0}]
        }

        Requirements:
        - Extract the real options from the situation, not generic placeholders.
        - If the user describes a current role vs a new offer, name both explicitly.
        - Suggested criteria must reflect the actual decision, not category defaults.
        """
    }

    static func optionsPrompt(draft: RankingDraft, profile: AIUserProfile?) -> String {
        let context = draft.clarifyingQuestions.map { "\($0.question): \($0.answer)" }.joined(separator: "\n")
        return """
        SITUATION: \(draft.contextNarrative)
        CLARIFYING ANSWERS: \(context)
        USER PROFILE: style=\(profile?.decisionStyle ?? "unknown"), challenge=\(profile?.biggestChallenge ?? "unknown")

        Extract explicit primary options from the situation.

        STRICT RULES:
        - If 2 or more explicit options are present, return only those options.
        - Do not add strategy options (pilot/negotiate/hybrid/wait) unless explicitly listed as primary options.
        - Preserve real names exactly; no placeholders.
        - Keep options comparable type.

        Return ONLY a JSON array:
        [{"label":"...", "description":"...", "aiSuggested":true}]
        """
    }

    static func biasPrompt(draft: RankingDraft, preferredOption: String, profile: AIUserProfile?) -> String {
        """
        Given this decision context and the user's apparent preference for \(preferredOption):
        Situation: \(draft.contextNarrative)
        Clarifying answers: \(draft.clarifyingQuestions.map { "\($0.question): \($0.answer)" }.joined(separator: "\n"))
        User profile: \(profile?.decisionStyle ?? "unknown"), \(profile?.biggestChallenge ?? "unknown"), \(profile?.valuesRanking.joined(separator: ", ") ?? "")

        Select 3 debiasing exercises from:
        [friend_test, ten_ten_ten, pre_mortem, worst_case, inversion, inaction_cost, values_check]

        RULES:
        - Tailor exercises to THIS user's challenge pattern.
        - If challenge is overthinking: prefer inversion, worst_case, commitment forcing.
        - If challenge is fear: prefer pre_mortem, inaction_cost, risk normalization.
        - Reference specifics from the situation.
        - Keep each question short and direct.

        Return ONLY a JSON array of exactly 3:
        [{"type":"...", "question":"...", "response":""}]
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
        - Scorecard: \(scorecard)
        - Bias challenge responses: \(challengeResponses)
        - User values: \(profile?.valuesRanking.joined(separator: ", ") ?? "")
        - Decision style: \(profile?.decisionStyle ?? "unknown")
        - Rankings: \(result.rankedVendors.map { "\($0.vendorName)=\($0.totalScore)" }.joined(separator: ", "))

        ANALYSIS PROCESS:
        1. Check alignment between scorecard winner and bias responses; flag contradictions.
        2. If any criterion >20% has low-confidence scores, state winner may flip.
        3. If margin between #1 and #2 is thin (<10%), state it as a toss-up.
        4. Identify what scorecard misses (emotional fit, relationships, optionality, reversibility).
        5. Connect recommendation to user's top value.

        Return ONLY valid JSON:
        {
          "recommendation":"1-2 sentences with conditions that would change it.",
          "trade_offs":["3 specific gain/loss trade-offs."],
          "blind_spots":["2-3 specific unmeasured factors."],
          "gut_check":"Connect recommendation to top value.",
          "next_step":"1 concrete action for today.",
          "confidence":{"level":"low|medium|high","reasoning":"What missing evidence would raise confidence?"}
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

#if canImport(FirebaseAuth)
final class FirebaseEmailAuthService: AuthServicing {
    private var appleCoordinator: AppleSignInCoordinator?

    func restoreSession() async -> AuthSession? {
        guard let user = Auth.auth().currentUser else { return nil }
        return Self.makeSession(from: user)
    }

    func signInWithEmail(email: String, password: String) async throws -> AuthSession {
        guard FirebaseApp.app() != nil else {
            throw ScoreWiseServiceError.featureUnavailable("Firebase is not configured. Add GoogleService-Info.plist before using live auth.")
        }
        let result = try await Auth.auth().signIn(withEmail: email, password: password)
        return Self.makeSession(from: result.user)
    }

    func createAccount(email: String, password: String, fullName: String) async throws -> AuthSession {
        guard FirebaseApp.app() != nil else {
            throw ScoreWiseServiceError.featureUnavailable("Firebase is not configured. Add GoogleService-Info.plist before using live auth.")
        }
        let result = try await Auth.auth().createUser(withEmail: email, password: password)
        if !fullName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            let changeRequest = result.user.createProfileChangeRequest()
            changeRequest.displayName = fullName
            try await changeRequest.commitChanges()
        }
        return Self.makeSession(from: Auth.auth().currentUser ?? result.user)
    }

    func signInWithApple() async throws -> AuthSession {
        guard FirebaseApp.app() != nil else {
            throw ScoreWiseServiceError.featureUnavailable("Firebase is not configured. Add GoogleService-Info.plist before using live auth.")
        }
        #if canImport(AuthenticationServices) && canImport(CryptoKit)
        guard let presenter = Self.topViewController() else {
            throw ScoreWiseServiceError.featureUnavailable("A presenting view controller was not available for Apple sign-in.")
        }

        let nonce = Self.randomNonceString()
        let credential = try await startAppleFlow(presentingFrom: presenter, rawNonce: nonce)
        return try await signInOrLink(with: credential, providerID: "apple.com")
        #else
        throw ScoreWiseServiceError.featureUnavailable("AuthenticationServices or CryptoKit is unavailable in this build.")
        #endif
    }

    func signInWithGoogle() async throws -> AuthSession {
        guard FirebaseApp.app() != nil else {
            throw ScoreWiseServiceError.featureUnavailable("Firebase is not configured. Add GoogleService-Info.plist before using live auth.")
        }
        #if canImport(GoogleSignIn)
        guard let clientID = FirebaseApp.app()?.options.clientID, !clientID.isEmpty else {
            throw ScoreWiseServiceError.featureUnavailable("Firebase client ID is missing. Update GoogleService-Info.plist.")
        }
        guard let presenter = Self.topViewController() else {
            throw ScoreWiseServiceError.featureUnavailable("A presenting view controller was not available for Google sign-in.")
        }

        let config = GIDConfiguration(clientID: clientID)
        GIDSignIn.sharedInstance.configuration = config

        let result = try await GIDSignIn.sharedInstance.signIn(withPresenting: presenter)
        guard let idToken = result.user.idToken?.tokenString else {
            throw ScoreWiseServiceError.featureUnavailable("Google sign-in completed without an ID token.")
        }
        let credential = GoogleAuthProvider.credential(
            withIDToken: idToken,
            accessToken: result.user.accessToken.tokenString
        )
        return try await signInOrLink(with: credential, providerID: "google.com")
        #else
        throw ScoreWiseServiceError.featureUnavailable("GoogleSignIn is not linked in this project. Add the GoogleSignIn iOS SDK.")
        #endif
    }

    func signOut() async throws {
        #if canImport(GoogleSignIn)
        GIDSignIn.sharedInstance.signOut()
        #endif
        try Auth.auth().signOut()
    }

    private static func makeSession(from user: FirebaseAuth.User) -> AuthSession {
        let displayName = user.displayName?.nonEmpty
            ?? user.email?.components(separatedBy: "@").first?.nonEmpty
            ?? "User"
        return AuthSession(
            userID: user.uid,
            email: user.email ?? "",
            displayName: displayName,
            providers: user.providerData.compactMap(\.providerID).isEmpty ? ["password"] : user.providerData.compactMap(\.providerID)
        )
    }

    private func signInOrLink(with credential: AuthCredential, providerID: String) async throws -> AuthSession {
        if let currentUser = Auth.auth().currentUser {
            if currentUser.providerData.contains(where: { $0.providerID == providerID }) {
                return Self.makeSession(from: currentUser)
            }

            do {
                let result = try await currentUser.linkAsync(with: credential)
                return Self.makeSession(from: result.user)
            } catch let error as NSError {
                let credentialConflictCodes: Set<Int> = [
                    AuthErrorCode.credentialAlreadyInUse.rawValue,
                    AuthErrorCode.providerAlreadyLinked.rawValue
                ]
                if credentialConflictCodes.contains(error.code) {
                    let result = try await Auth.auth().signInAsync(with: credential)
                    return Self.makeSession(from: result.user)
                }
                throw error
            }
        }

        let result = try await Auth.auth().signInAsync(with: credential)
        return Self.makeSession(from: result.user)
    }

    #if canImport(AuthenticationServices) && canImport(CryptoKit)
    private func startAppleFlow(presentingFrom presenter: UIViewController, rawNonce: String) async throws -> AuthCredential {
        let coordinator = AppleSignInCoordinator(presenter: presenter, rawNonce: rawNonce)
        appleCoordinator = coordinator
        defer { appleCoordinator = nil }
        return try await coordinator.start()
    }

    private static func randomNonceString(length: Int = 32) -> String {
        precondition(length > 0)
        let charset: [Character] = Array("0123456789ABCDEFGHIJKLMNOPQRSTUVXYZabcdefghijklmnopqrstuvwxyz-._")
        var result = ""
        var remainingLength = length

        while remainingLength > 0 {
            var randoms: [UInt8] = Array(repeating: 0, count: 16)
            let errorCode = SecRandomCopyBytes(kSecRandomDefault, randoms.count, &randoms)
            if errorCode != errSecSuccess {
                fatalError("Unable to generate nonce. OSStatus \(errorCode)")
            }

            randoms.forEach { random in
                if remainingLength == 0 {
                    return
                }

                if random < charset.count {
                    result.append(charset[Int(random)])
                    remainingLength -= 1
                }
            }
        }

        return result
    }

    fileprivate static func sha256(_ input: String) -> String {
        let inputData = Data(input.utf8)
        let hashedData = SHA256.hash(data: inputData)
        return hashedData.map { String(format: "%02x", $0) }.joined()
    }
    #endif

    private static func topViewController(
        base: UIViewController? = UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .flatMap(\.windows)
            .first(where: \.isKeyWindow)?
            .rootViewController
    ) -> UIViewController? {
        if let nav = base as? UINavigationController {
            return topViewController(base: nav.visibleViewController)
        }
        if let tab = base as? UITabBarController {
            return topViewController(base: tab.selectedViewController)
        }
        if let presented = base?.presentedViewController {
            return topViewController(base: presented)
        }
        return base
    }
}
#else
final class FirebaseEmailAuthService: AuthServicing {
    func restoreSession() async -> AuthSession? { nil }

    func signInWithEmail(email: String, password: String) async throws -> AuthSession {
        throw ScoreWiseServiceError.featureUnavailable("FirebaseAuth is not linked in this project. Add the Firebase iOS SDK and GoogleService-Info.plist.")
    }

    func createAccount(email: String, password: String, fullName: String) async throws -> AuthSession {
        throw ScoreWiseServiceError.featureUnavailable("FirebaseAuth is not linked in this project. Add the Firebase iOS SDK and GoogleService-Info.plist.")
    }

    func signInWithApple() async throws -> AuthSession {
        throw ScoreWiseServiceError.featureUnavailable("FirebaseAuth is not linked in this project. Add the Firebase iOS SDK and Apple sign-in wiring.")
    }

    func signInWithGoogle() async throws -> AuthSession {
        throw ScoreWiseServiceError.featureUnavailable("GoogleSignIn and FirebaseAuth are not linked in this project.")
    }

    func signOut() async throws {}
}
#endif

#if canImport(FirebaseAuth)
private extension Auth {
    func signInAsync(with credential: AuthCredential) async throws -> AuthDataResult {
        try await withCheckedThrowingContinuation { continuation in
            signIn(with: credential) { result, error in
                if let result {
                    continuation.resume(returning: result)
                } else {
                    continuation.resume(throwing: error ?? ScoreWiseServiceError.featureUnavailable("Firebase sign-in failed."))
                }
            }
        }
    }
}

private extension FirebaseAuth.User {
    func linkAsync(with credential: AuthCredential) async throws -> AuthDataResult {
        try await withCheckedThrowingContinuation { continuation in
            link(with: credential) { result, error in
                if let result {
                    continuation.resume(returning: result)
                } else {
                    continuation.resume(throwing: error ?? ScoreWiseServiceError.featureUnavailable("Credential linking failed."))
                }
            }
        }
    }
}
#endif

#if canImport(AuthenticationServices) && canImport(CryptoKit) && canImport(FirebaseAuth)
private final class AppleSignInCoordinator: NSObject, ASAuthorizationControllerDelegate, ASAuthorizationControllerPresentationContextProviding {
    private let presenter: UIViewController
    private let rawNonce: String
    private var continuation: CheckedContinuation<AuthCredential, Error>?

    init(presenter: UIViewController, rawNonce: String) {
        self.presenter = presenter
        self.rawNonce = rawNonce
    }

    func start() async throws -> AuthCredential {
        try await withCheckedThrowingContinuation { continuation in
            self.continuation = continuation

            let provider = ASAuthorizationAppleIDProvider()
            let request = provider.createRequest()
            request.requestedScopes = [.fullName, .email]
            request.nonce = FirebaseEmailAuthService.sha256(rawNonce)

            let controller = ASAuthorizationController(authorizationRequests: [request])
            controller.delegate = self
            controller.presentationContextProvider = self
            controller.performRequests()
        }
    }

    func presentationAnchor(for controller: ASAuthorizationController) -> ASPresentationAnchor {
        presenter.view.window ?? ASPresentationAnchor()
    }

    func authorizationController(controller: ASAuthorizationController, didCompleteWithAuthorization authorization: ASAuthorization) {
        guard let appleIDCredential = authorization.credential as? ASAuthorizationAppleIDCredential else {
            continuation?.resume(throwing: ScoreWiseServiceError.featureUnavailable("Apple sign-in returned an unexpected credential type."))
            continuation = nil
            return
        }

        guard let appleIDToken = appleIDCredential.identityToken,
              let idTokenString = String(data: appleIDToken, encoding: .utf8) else {
            continuation?.resume(throwing: ScoreWiseServiceError.featureUnavailable("Unable to read the Apple identity token."))
            continuation = nil
            return
        }

        let credential = OAuthProvider.appleCredential(
            withIDToken: idTokenString,
            rawNonce: rawNonce,
            fullName: appleIDCredential.fullName
        )
        continuation?.resume(returning: credential)
        continuation = nil
    }

    func authorizationController(controller: ASAuthorizationController, didCompleteWithError error: Error) {
        continuation?.resume(throwing: error)
        continuation = nil
    }
}
#endif

struct LocalMockAIService: AIservicing {
    func generateDecisionBrief(for draft: RankingDraft, extractedEvidence: [String], userProfile: AIUserProfile?) async throws -> DecisionBrief {
        DecisionEngine.shared.buildDecisionBrief(draft: draft, extractedEvidence: extractedEvidence, userProfile: userProfile)
    }

    func suggestRankingInputs(for draft: RankingDraft, context: UsageContext, extractedEvidence: [String], userProfile: AIUserProfile?) async throws -> AISuggestedInputs {
        DecisionEngine.shared.buildSuggestedInputs(
            draft: draft,
            context: context,
            extractedEvidence: extractedEvidence,
            userProfile: userProfile
        )
    }

    func generateClarifyingQuestions(for draft: RankingDraft, userProfile: AIUserProfile?) async throws -> [ClarifyingQuestionAnswer] {
        DecisionEngine.shared.generateClarifyingQuestions(draft: draft, userProfile: userProfile)
    }

    func suggestDecisionOptions(for draft: RankingDraft, userProfile: AIUserProfile?) async throws -> [DecisionOptionSnapshot] {
        DecisionEngine.shared
            .buildDecisionBrief(draft: draft, extractedEvidence: [], userProfile: userProfile)
            .detectedOptions
    }

    func generateBiasChallenges(for draft: RankingDraft, preferredOption: String, userProfile: AIUserProfile?) async throws -> [BiasChallengeResponse] {
        LocalDecisionIntelligence.biasChallenges(for: draft, preferredOption: preferredOption, userProfile: userProfile)
    }

    func startDecisionConversation(projectID: String, contextNarrative: String, usageContext: UsageContext, userProfile: AIUserProfile?) async throws -> DecisionConversationResponse {
        let brief = DecisionEngine.shared.buildDecisionBrief(
            draft: draftForConversation(projectID: projectID, contextNarrative: contextNarrative, usageContext: usageContext),
            extractedEvidence: [],
            userProfile: userProfile
        )
        let optionTexts = brief.detectedOptions
            .map(\.label)
            .filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
            .prefix(4)
        let options = Array(optionTexts.enumerated().map { index, text in
            DecisionChatOption(index: index + 1, text: text)
        })

        return DecisionConversationResponse(
            message: DecisionChatMessage(
                role: .assistant,
                content: "Let’s clarify what matters most before scoring. Which option best matches your current direction?",
                options: options,
                allowSkip: true,
                allowsFreeformReply: true,
                cta: nil,
                framework: .valuesAlignment,
                createdAt: .now,
                isTypingPlaceholder: false
            ),
            conversationState: DecisionConversationState(phase: .collecting, frameworksUsed: [.valuesAlignment])
        )
    }

    func continueDecisionConversation(projectID: String, transcript: [DecisionChatMessage], latestUserResponse: String, selectedOptionIndex: Int?, draft: RankingDraft, userProfile: AIUserProfile?) async throws -> DecisionConversationResponse {
        let used = transcript.compactMap(\.framework)
        if used.count >= 3 {
            return DecisionConversationResponse(
                message: DecisionChatMessage(
                    role: .assistant,
                    content: "I have enough context to set up your weighted matrix.",
                    options: [],
                    allowSkip: false,
                    allowsFreeformReply: false,
                    cta: ChatMessageCTA(title: "Set Up Your Options", action: .setupOptions),
                    framework: nil,
                    createdAt: .now,
                    isTypingPlaceholder: false
                ),
                conversationState: DecisionConversationState(phase: .transitionReady, frameworksUsed: Array(used.prefix(4)))
            )
        }

        let frameworks: [DecisionFramework] = [.riskAssessment, .opportunityCost, .reversibility]
        let framework = frameworks[min(used.count, frameworks.count - 1)]
        let questions = LocalDecisionIntelligence.clarifyingQuestions(for: draft, userProfile: userProfile).map(\.question)
        let content = questions.dropFirst(used.count).first ?? "What one missing fact would most change your decision?"

        return DecisionConversationResponse(
            message: DecisionChatMessage(
                role: .assistant,
                content: content,
                options: [],
                allowSkip: true,
                allowsFreeformReply: true,
                cta: nil,
                framework: framework,
                createdAt: .now,
                isTypingPlaceholder: false
            ),
            conversationState: DecisionConversationState(phase: .collecting, frameworksUsed: Array((used + [framework]).prefix(4)))
        )
    }

    func finalizeConversationForMatrix(projectID: String, transcript: [DecisionChatMessage], draft: RankingDraft, userProfile: AIUserProfile?) async throws -> DecisionMatrixSetup {
        let brief = DecisionEngine.shared.buildDecisionBrief(draft: draft, extractedEvidence: [], userProfile: userProfile)
        return DecisionMatrixSetup(
            decisionBrief: brief,
            suggestedOptions: brief.detectedOptions,
            suggestedCriteria: brief.suggestedCriteria
        )
    }

    func decisionChat(projectID: String, phase: String, message: String, draft: RankingDraft?, userProfile: AIUserProfile?) async throws -> AIChatResponse {
        DecisionEngine.shared.chatResponse(
            projectID: projectID,
            phase: phase,
            message: message,
            draft: draft,
            userProfile: userProfile
        )
    }

    func generateInsights(draft: RankingDraft, result: RankingResult, userProfile: AIUserProfile?) async throws -> InsightReportDraft {
        DecisionEngine.shared.buildInsightReport(draft: draft, result: result, userProfile: userProfile)
    }

    private func draftForConversation(projectID: String, contextNarrative: String, usageContext: UsageContext) -> RankingDraft {
        var draft = RankingDraft.empty
        draft.id = projectID
        draft.contextNarrative = contextNarrative
        draft.usageContext = usageContext
        return draft
    }
}

struct UnavailableAIService: AIservicing {
    private let reason: String

    init(reason: String) {
        self.reason = reason
    }

    func generateDecisionBrief(for draft: RankingDraft, extractedEvidence: [String], userProfile: AIUserProfile?) async throws -> DecisionBrief {
        throw unavailableError()
    }

    func suggestRankingInputs(for draft: RankingDraft, context: UsageContext, extractedEvidence: [String], userProfile: AIUserProfile?) async throws -> AISuggestedInputs {
        throw unavailableError()
    }

    func generateClarifyingQuestions(for draft: RankingDraft, userProfile: AIUserProfile?) async throws -> [ClarifyingQuestionAnswer] {
        throw unavailableError()
    }

    func suggestDecisionOptions(for draft: RankingDraft, userProfile: AIUserProfile?) async throws -> [DecisionOptionSnapshot] {
        throw unavailableError()
    }

    func generateBiasChallenges(for draft: RankingDraft, preferredOption: String, userProfile: AIUserProfile?) async throws -> [BiasChallengeResponse] {
        throw unavailableError()
    }

    func startDecisionConversation(projectID: String, contextNarrative: String, usageContext: UsageContext, userProfile: AIUserProfile?) async throws -> DecisionConversationResponse {
        throw unavailableError()
    }

    func continueDecisionConversation(projectID: String, transcript: [DecisionChatMessage], latestUserResponse: String, selectedOptionIndex: Int?, draft: RankingDraft, userProfile: AIUserProfile?) async throws -> DecisionConversationResponse {
        throw unavailableError()
    }

    func finalizeConversationForMatrix(projectID: String, transcript: [DecisionChatMessage], draft: RankingDraft, userProfile: AIUserProfile?) async throws -> DecisionMatrixSetup {
        throw unavailableError()
    }

    func decisionChat(projectID: String, phase: String, message: String, draft: RankingDraft?, userProfile: AIUserProfile?) async throws -> AIChatResponse {
        throw unavailableError()
    }

    func generateInsights(draft: RankingDraft, result: RankingResult, userProfile: AIUserProfile?) async throws -> InsightReportDraft {
        throw unavailableError()
    }

    private func unavailableError() -> Error {
        ScoreWiseServiceError.featureUnavailable(reason)
    }
}

enum LocalDecisionIntelligence {
    static func contextWarning(for narrative: String) -> String? {
        let trimmed = narrative.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return "Add the decision, the real options, and what makes this hard." }

        let words = trimmed.split(whereSeparator: \.isWhitespace)
        let lower = trimmed.lowercased()
        let decisionSignals = [" or ", "between ", "decide", "choose", "compare", "stay", "leave", "accept", "move", "hire", "candidate", "vendor", "provider", "switch"]
        let contextSignals = ["because", "but", "need", "want", "worried", "risk", "timeline", "budget", "salary", "fit", "cost", "constraint", "deadline"]
        let hasDecisionSignal = decisionSignals.contains(where: lower.contains)
        let hasContextSignal = contextSignals.contains(where: lower.contains)

        if words.count < 6 || trimmed.count < 28 {
            return "Add a bit more context so the AI can infer the real options and criteria."
        }

        if words.count < 12 && !(hasDecisionSignal && hasContextSignal) {
            return "Mention the options you are comparing and one key constraint or risk before continuing."
        }

        return nil
    }

    static func decisionBrief(for draft: RankingDraft, extractedEvidence: [String], userProfile: AIUserProfile?) -> DecisionBrief {
        let narrative = draft.contextNarrative.trimmingCharacters(in: .whitespacesAndNewlines)
        let context = combinedContext(for: draft, extractedEvidence: extractedEvidence)
        let inferredCategory = inferDecisionCategory(from: context, fallback: draft.category)
        let existingOptions = meaningfulOptions(from: draft)
        let options = existingOptions.count >= 2
            ? existingOptions
            : inferredOptions(from: draft, category: inferredCategory, userProfile: userProfile)
        let goals = inferredGoals(from: draft, context: context, category: inferredCategory, profile: userProfile)
        let constraints = inferredConstraints(from: draft, context: context)
        let risks = inferredRisks(from: draft, context: context, category: inferredCategory)
        let tensions = inferredTensions(from: draft, context: context, options: options, category: inferredCategory)
        let criteria = suggestedCriteria(
            narrative: narrative,
            category: inferredCategory,
            options: options,
            goals: goals,
            constraints: constraints,
            risks: risks,
            tensions: tensions,
            profile: userProfile
        )

        return DecisionBrief(
            summary: briefSummary(narrative: narrative, options: options, goals: goals, constraints: constraints, tensions: tensions),
            inferredCategory: inferredCategory,
            detectedOptions: options,
            goals: goals,
            constraints: constraints,
            risks: risks,
            tensions: tensions,
            suggestedCriteria: criteria
        )
    }

    static func suggestedInputs(for draft: RankingDraft, context: UsageContext, extractedEvidence: [String], userProfile: AIUserProfile?) -> AISuggestedInputs {
        let brief = decisionBrief(for: draft, extractedEvidence: extractedEvidence, userProfile: userProfile)
        let briefTextParts = [
            draft.contextNarrative,
            brief.summary,
            brief.goals.joined(separator: " "),
            brief.constraints.joined(separator: " "),
            brief.risks.joined(separator: " "),
            brief.tensions.joined(separator: " "),
            draft.alternativePathAnswer ?? ""
        ]
        let contextBlob = (briefTextParts + draft.clarifyingQuestions.map(\.answer) + extractedEvidence)
            .joined(separator: " ")
            .lowercased()

        let briefCriteria = brief.suggestedCriteria
        let criteria = RankingEngine.normalizedCriteria(briefCriteria)

        let evidenceText = extractedEvidence.joined(separator: "\n").lowercased()
        let answerText = draft.clarifyingQuestions.map(\.answer).joined(separator: " ").lowercased()
        let sourceCount = max(extractedEvidence.count, 1)
        let attachmentCount = draft.contextAttachments.count + draft.vendors.flatMap(\.attachments).count
        let winnerTheme = strongestTheme(in: contextBlob, profile: userProfile)
        let scores = scoreDrafts(
            vendors: draft.vendors,
            criteria: criteria,
            answerText: answerText,
            evidenceText: evidenceText,
            extractedEvidence: extractedEvidence,
            sourceCount: sourceCount,
            attachmentCount: attachmentCount,
            winnerTheme: winnerTheme,
            userProfile: userProfile
        )

        return AISuggestedInputs(criteria: criteria, draftScores: scores)
    }

    private static func scoreDrafts(
        vendors: [VendorDraft],
        criteria: [CriterionDraft],
        answerText: String,
        evidenceText: String,
        extractedEvidence: [String],
        sourceCount: Int,
        attachmentCount: Int,
        winnerTheme: String,
        userProfile: AIUserProfile?
    ) -> [ScoreDraft] {
        var drafts: [ScoreDraft] = []
        drafts.reserveCapacity(vendors.count * max(criteria.count, 1))

        for vendor in vendors {
            for criterion in criteria {
                drafts.append(
                    scoreDraft(
                        vendor: vendor,
                        criterion: criterion,
                        answerText: answerText,
                        evidenceText: evidenceText,
                        extractedEvidence: extractedEvidence,
                        sourceCount: sourceCount,
                        attachmentCount: attachmentCount,
                        winnerTheme: winnerTheme,
                        userProfile: userProfile
                    )
                )
            }
        }

        return drafts
    }

    private static func scoreDraft(
        vendor: VendorDraft,
        criterion: CriterionDraft,
        answerText: String,
        evidenceText: String,
        extractedEvidence: [String],
        sourceCount: Int,
        attachmentCount: Int,
        winnerTheme: String,
        userProfile: AIUserProfile?
    ) -> ScoreDraft {
        let vendorAttachmentText = vendor.attachments
            .map { [$0.fileName, $0.titleHint, $0.validationMessage, $0.sourceHost].joined(separator: " ") }
            .joined(separator: " ")
        let vendorText = [vendor.name, vendor.notes, vendorAttachmentText].joined(separator: " ").lowercased()
        let combinedText = vendorText + " " + answerText + " " + evidenceText
        let matchedSignals = signalCount(in: combinedText, for: criterion)
        let positiveMatchCount = signalMatches(in: combinedText, signals: positiveSignals(for: criterion))
        let negativeMatchCount = signalMatches(in: combinedText, signals: negativeSignals(for: criterion))
        let directEvidenceHits = vendorEvidenceHits(for: vendor, criterion: criterion, evidence: extractedEvidence)
        let topValueBoost = topValueAlignmentBoost(for: criterion, profile: userProfile)
        let themeBoost = criterion.name.lowercased().contains(winnerTheme) ? 0.35 : 0
        let stableOffset = Double(stableHash("\(vendor.id)|\(criterion.id)") % 17) / 10.0 - 0.8
        let evidenceBoost = min(Double(directEvidenceHits) * 0.42, 1.25)
        let attachmentBoost = vendor.attachments.isEmpty ? 0 : min(Double(vendor.attachments.count) * 0.18, 0.45)
        let downsidePenalty = min(Double(negativeMatchCount) * 0.45, 1.35)
        let baseScore = 5.0
            + Double(matchedSignals) * 0.28
            + Double(positiveMatchCount) * 0.42
            + evidenceBoost
            + attachmentBoost
            + topValueBoost
            + themeBoost
            - downsidePenalty
            + stableOffset
        let clamped = min(max(baseScore, 3.5), 9.4)
        let confidenceBase = extractedEvidence.isEmpty ? 0.56 : 0.66 + min(Double(sourceCount) * 0.04, 0.18)
        let confidence = min(
            max(confidenceBase + Double(directEvidenceHits) * 0.05 + (attachmentCount > 0 ? 0.04 : 0), 0.56),
            0.93
        )

        return ScoreDraft(
            vendorID: vendor.id,
            criterionID: criterion.id,
            score: (clamped * 10).rounded() / 10,
            source: .aiDraft,
            confidence: confidence,
            evidenceSnippet: evidenceSnippet(for: criterion, vendor: vendor, extractedEvidence: extractedEvidence)
        )
    }

    static func clarifyingQuestions(for draft: RankingDraft, userProfile: AIUserProfile?) -> [ClarifyingQuestionAnswer] {
        let focus = userProfile?.valuesRanking.first?.lowercased() ?? "your top priority"
        let challenge = userProfile?.biggestChallenge ?? ""
        let brief = decisionBrief(for: draft, extractedEvidence: [], userProfile: userProfile)
        let leadConstraint = brief.constraints.first?.lowercased() ?? "constraint"
        let leadRisk = brief.risks.first?.lowercased() ?? "main risk"
        let leadTension = brief.tensions.first?.lowercased() ?? "trade-off"

        let stakesQuestion: String
        switch challenge {
        case BiggestChallenge.fear.rawValue:
            stakesQuestion = "What would make choosing the wrong option genuinely costly here, and what evidence says that risk is real rather than assumed?"
        case BiggestChallenge.overthinking.rawValue:
            stakesQuestion = "What one outcome would make this feel like the right choice 6 months from now?"
        default:
            stakesQuestion = "What result matters most in this decision: protecting what you have now, moving toward something better, or keeping future options open?"
        }

        let constraintsQuestion = "Which part of this is truly non-negotiable: \(leadConstraint), and how should it rule options in or out?"
        let valuesQuestion = "The central tension looks like \(leadTension). Which option best protects \(focus) while still managing \(leadRisk)?"

        return [
            ClarifyingQuestionAnswer(question: stakesQuestion, answer: ""),
            ClarifyingQuestionAnswer(question: constraintsQuestion, answer: ""),
            ClarifyingQuestionAnswer(question: valuesQuestion, answer: "")
        ]
    }

    static func suggestedOptions(for draft: RankingDraft, userProfile: AIUserProfile?) -> [DecisionOptionSnapshot] {
        decisionBrief(for: draft, extractedEvidence: [], userProfile: userProfile).detectedOptions
    }

    static func biasChallenges(for draft: RankingDraft, preferredOption: String, userProfile: AIUserProfile?) -> [BiasChallengeResponse] {
        let topValue = userProfile?.valuesRanking.first?.lowercased() ?? "your top value"
        let challenge = userProfile?.biggestChallenge ?? ""
        let brief = decisionBrief(for: draft, extractedEvidence: [], userProfile: userProfile)
        let context = ([brief.summary] + brief.risks + brief.tensions).joined(separator: " ").lowercased()

        let allPrompts: [BiasChallengeResponse] = [
            BiasChallengeResponse(type: .friendTest, question: "If someone you care about had your exact facts and constraints, what would you tell them to do about \(preferredOption) and why?", response: ""),
            BiasChallengeResponse(type: .tenTenTen, question: "How will choosing \(preferredOption) feel in 10 minutes, 10 months, and 10 years?", response: ""),
            BiasChallengeResponse(type: .valuesCheck, question: "Which option best protects \(topValue), even if it is less comfortable right now?", response: ""),
            BiasChallengeResponse(type: .preMortem, question: "Assume \(preferredOption) fails. What is the most plausible reason it failed?", response: ""),
            BiasChallengeResponse(type: .worstCase, question: "What is the realistic worst-case outcome if you choose \(preferredOption), and how would you recover?", response: ""),
            BiasChallengeResponse(type: .inactionCost, question: "What is the cost of delaying this decision by another 30 days?", response: ""),
            BiasChallengeResponse(type: .inversion, question: "If you wanted to make the worst possible choice here, what would you ignore or rationalize?", response: "")
        ]

        let orderedTypes: [BiasChallengeType]
        switch challenge {
        case BiggestChallenge.overthinking.rawValue:
            orderedTypes = [.tenTenTen, .friendTest, .inactionCost]
        case BiggestChallenge.fear.rawValue:
            orderedTypes = [.worstCase, .preMortem, .friendTest]
        case BiggestChallenge.tooManyOptions.rawValue:
            orderedTypes = [.inversion, .valuesCheck, .inactionCost]
        default:
            orderedTypes = context.contains("risk") || context.contains("security")
                ? [.preMortem, .worstCase, .valuesCheck]
                : [.valuesCheck, .friendTest, .tenTenTen]
        }

        return orderedTypes.compactMap { type in
            allPrompts.first(where: { $0.type == type })
        }
    }

    static func insights(for draft: RankingDraft, result: RankingResult, userProfile: AIUserProfile?) -> InsightReportDraft {
        let brief = decisionBrief(for: draft, extractedEvidence: [], userProfile: userProfile)
        let ranked = result.rankedVendors
        let winner = ranked.first?.vendorName ?? "No clear winner"
        let runnerUp = ranked.dropFirst().first?.vendorName ?? "the next option"
        let topCriteria = draft.criteria.sorted { $0.weightPercent > $1.weightPercent }.prefix(3)
        let value = userProfile?.valuesRanking.first ?? "your top priority"
        let evidenceCount = draft.contextAttachments.count + draft.vendors.flatMap(\.attachments).count
        let biggestGap = strongestSeparation(in: draft, winnerID: ranked.first?.vendorID, runnerUpID: ranked.dropFirst().first?.vendorID)

        let summaryLines = topCriteria.map { criterion in
            let winnerScore = draft.scores.first(where: { $0.vendorID == ranked.first?.vendorID && $0.criterionID == criterion.id })?.score ?? 0
            let runnerUpScore = draft.scores.first(where: { $0.vendorID == ranked.dropFirst().first?.vendorID && $0.criterionID == criterion.id })?.score ?? 0
            return "\(criterion.name): \(winner) leads \(runnerUp) by \((winnerScore - runnerUpScore).formatted(.number.precision(.fractionLength(1)))) points, and this criterion carries \(Int(criterion.weightPercent.rounded()))% of the final decision."
        }

        var riskFlags = [
            "Validate any score below 0.60 confidence before treating it as reliable.",
            "Check whether the current leader still wins if your top criterion weight changes by 10%."
        ]
        if result.tieDetected {
            riskFlags.insert("The top two options are close enough that one criterion reweight could change the result.", at: 0)
        }
        if evidenceCount == 0 {
            riskFlags.insert("No supporting files or links were analyzed, so this recommendation relies mainly on your written inputs.", at: 0)
        }
        if let biggestGap {
            riskFlags.append("The current recommendation depends heavily on \(biggestGap.criterion.lowercased()); challenge whether that criterion deserves its current weight.")
        }

        let overlooked = [
            "Test the strongest assumption separating \(winner) from \(runnerUp).",
            "Check reversibility: how costly is it to unwind this choice in 3-6 months?",
            evidenceCount < 2
                ? "Add at least one external source or stakeholder input before treating the current leader as settled."
                : "Look for one external source or stakeholder input that could invalidate the current leader."
        ]

        let sensitivity = result.sensitivityFindings.map { finding in
            finding.winnerFlipped
                ? "If \(finding.criterionName.lowercased()) changes materially, the winner can flip."
                : "\(finding.criterionName) looks stable under moderate weight changes."
        }

        return InsightReportDraft(
            summary: ([brief.summary] + summaryLines).joined(separator: "\n"),
            winnerReasoning: "\(winner) currently appears strongest because it handles the core tension of \(brief.tensions.first?.lowercased() ?? "this decision") better than \(runnerUp), and it performs better on the criteria carrying the most weight, especially \(biggestGap?.criterion.lowercased() ?? "the highest-impact criteria").",
            riskFlags: riskFlags,
            overlookedStrategicPoints: overlooked,
            sensitivityFindings: sensitivity.isEmpty ? ["Gut check: choose the option that still protects \(value.lowercased()) if conditions become harder than expected."] : sensitivity
        )
    }

    static func chatResponse(projectID: String, phase: String, message: String, draft: RankingDraft?, userProfile: AIUserProfile?) -> AIChatResponse {
        guard let draft else {
            return AIChatResponse(
                content: "Describe the situation, the options you are considering, and the main constraint. I can then help you structure the decision.",
                recommendedActions: [
                    "Write the decision in one sentence.",
                    "List the real options, not just the preferred one.",
                    "State the most important constraint."
                ]
            )
        }

        let brief = decisionBrief(for: draft, extractedEvidence: [], userProfile: userProfile)
        let lowerMessage = message.lowercased()
        let value = userProfile?.valuesRanking.first?.lowercased() ?? "your top priority"
        let result = draft.scores.isEmpty || draft.criteria.isEmpty ? nil : RankingEngine.computeResult(for: draft)
        let winner = result?.rankedVendors.first?.vendorName
        let runnerUp = result?.rankedVendors.dropFirst().first?.vendorName
        let strongestGap = result.flatMap { _ in
            strongestSeparation(in: draft, winnerID: result?.rankedVendors.first?.vendorID, runnerUpID: result?.rankedVendors.dropFirst().first?.vendorID)
        }

        let content: String
        if phase == "post_challenge_reassurance" {
            let answeredChallenges = draft.biasChallenges.filter {
                !$0.response.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            }
            let uncertainty = result == nil ? "You still need one matrix pass before locking the choice." : "Treat this as a confidence check, not absolute certainty."
            let recommendationLine: String
            if let winner {
                recommendationLine = "\(winner)"
            } else {
                recommendationLine = "Not ready to finalize"
            }
            content = """
            Recommendation
            \(recommendationLine)

            Why this option leads
            Your challenge-check answers remain broadly aligned with the weighted evidence.

            Risks to consider
            \(uncertainty)

            Confidence level
            \(result == nil ? "Low" : "Medium")

            Next step
            Validate one key assumption this week, then finalize.
            """
            return AIChatResponse(
                content: content,
                recommendedActions: [
                    answeredChallenges.isEmpty ? "Capture one concrete risk in writing before finalizing." : "Act on one validation step tied to your biggest concern.",
                    "Set a decision deadline so reassurance turns into action."
                ]
            )
        } else if draft.contextNarrative.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            content = "I do not have enough context yet. Start with the decision in one sentence, then add the constraint or risk that matters most."
        } else if lowerMessage.contains("what should") || lowerMessage.contains("recommend") || lowerMessage.contains("best option") {
            if let winner {
                content = "\(winner) looks strongest right now because it scores better on the highest-weighted criteria. Before locking it in, test whether \(strongestGap?.criterion.lowercased() ?? "the top criterion") is weighted correctly and whether any file or link contradicts that lead."
            } else {
                content = "I can recommend a direction once you have either compared the options or added enough detail to generate criteria and scores."
            }
        } else if lowerMessage.contains("risk") || lowerMessage.contains("blind spot") {
            content = "The main risk is hidden confidence. If a score is based on weak evidence or a recent impression, it can make the leader look more certain than it is. Pressure-test the assumptions behind the top-weighted criterion first."
        } else if phase == "clarifying" {
            content = "Answer the clarifying questions with specifics, not general preferences. The main tension I see is \(brief.tensions.first?.lowercased() ?? "the central trade-off"), so I am looking for real constraints, measurable success, and any fact that rules an option out."
        } else if phase == "weigh" {
            content = "Use the weight matrix to express the real trade-off: \(brief.tensions.first?.lowercased() ?? "what matters most versus what feels safest"). If everything looks equally important, the model cannot separate the options cleanly."
        } else {
            content = "Use the evidence to challenge your current preference. The right choice is the one that still protects \(value) when assumptions become less favorable."
        }

        var actions: [String] = []
        if draft.contextAttachments.isEmpty && draft.vendors.flatMap(\.attachments).isEmpty {
            actions.append("Attach a document or link that supports the key facts behind this decision.")
        }
        if draft.clarifyingQuestions.contains(where: { $0.answer.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }) {
            actions.append("Answer the remaining clarifying questions with specific constraints or success metrics.")
        }
        if draft.criteria.isEmpty {
            actions.append("Generate criteria from the situation before trying to compare options.")
        } else if let strongestGap {
            actions.append("Review whether \(strongestGap.criterion) deserves its current weight.")
        }
        if let winner, let runnerUp {
            actions.append("Write one reason \(runnerUp) could still beat \(winner) if new evidence appears.")
        }

        return AIChatResponse(content: content, recommendedActions: Array(actions.prefix(3)))
    }

    private static func meaningfulOptions(from draft: RankingDraft) -> [DecisionOptionSnapshot] {
        draft.vendors
            .filter {
                let name = $0.name.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
                return !name.isEmpty && !name.hasPrefix("vendor ") && !name.hasPrefix("option ") && !name.hasPrefix("candidate ")
            }
            .map {
                DecisionOptionSnapshot(
                    id: $0.id,
                    label: $0.name,
                    description: $0.notes.nonEmpty ?? inferredDescription(for: $0.name, draft: draft),
                    aiSuggested: false
                )
            }
    }

    private static func inferDecisionCategory(from context: String, fallback: DecisionCategory) -> DecisionCategory {
        let lower = context.lowercased()
        if lower.contains("job offer") || lower.contains("career") || lower.contains("promotion") || lower.contains("salary") || lower.contains("company") || lower.contains("role") {
            return .career
        }
        if lower.contains("vendor") || lower.contains("provider") || lower.contains("proposal") || lower.contains("quote") || lower.contains("implementation") || lower.contains("service") {
            return .business
        }
        if lower.contains("tuition") || lower.contains("course") || lower.contains("degree") || lower.contains("study") {
            return .education
        }
        if lower.contains("investment") || lower.contains("loan") || lower.contains("mortgage") || lower.contains("portfolio") {
            return .finance
        }
        return fallback
    }

    private static func inferredOptions(from draft: RankingDraft, category: DecisionCategory, userProfile: AIUserProfile?) -> [DecisionOptionSnapshot] {
        if let extracted = extractExplicitChoiceOptions(from: draft), extracted.count >= 2 {
            return extracted
        }

        if category == .career, let extracted = extractCareerOptions(from: draft), extracted.count >= 2 {
            return extracted
        }

        let alternativePath = draft.alternativePathAnswer?.trimmingCharacters(in: .whitespacesAndNewlines)
        let alternativePathOption: DecisionOptionSnapshot?
        if let alternativePath, !alternativePath.isEmpty {
            alternativePathOption = alternativeOption(from: alternativePath, draft: draft)
        } else {
            alternativePathOption = nil
        }

        let existing = meaningfulOptions(from: draft)
        if existing.count >= 2 {
            if let alternativePathOption,
               !existing.contains(where: { normalizedText($0.label) == normalizedText(alternativePathOption.label) }) {
                return Array((existing + [alternativePathOption]).prefix(4))
            }
            return existing
        }
        if let alternativePathOption {
            return Array((existing + [alternativePathOption]).prefix(4))
        }

        return existing
    }

    private static func inferredGoals(from draft: RankingDraft, context: String, category: DecisionCategory, profile: AIUserProfile?) -> [String] {
        var goals: [String] = []
        let lower = context.lowercased()
        if isHiringContext(lower) {
            goals.append("Choose the candidate who is the best fit for the role rather than the most impressive on paper.")
            goals.append("Reduce hiring risk while protecting speed-to-fill and team fit.")
        }
        if category == .career {
            if lower.contains("dream company") { goals.append("Move closer to a high-aspiration employer without creating long-term regret.") }
            if lower.contains("analyst") || lower.contains("career path") { goals.append("Protect role fit and long-term career trajectory.") }
            if lower.contains("retail") { goals.append("Avoid taking a role that does not match the desired career direction.") }
        }
        if lower.contains("salary") || lower.contains("compensation") || lower.contains("budget") {
            goals.append("Improve financial outcome without undermining the core objective.")
        }
        if let topValue = profile?.valuesRanking.first, !topValue.isEmpty {
            goals.append("Protect \(topValue.lowercased()) while making the decision more defensible.")
        }
        if goals.isEmpty {
            goals.append("Choose the option that best balances upside, downside, and reversibility.")
        }
        return Array(goals.uniqued().prefix(3))
    }

    private static func inferredConstraints(from draft: RankingDraft, context: String) -> [String] {
        var constraints: [String] = []
        let lower = context.lowercased()
        if isHiringContext(lower) {
            constraints.append("Any finalist should satisfy the true must-haves for the role, not just interview well.")
        }
        if lower.contains("currently") || lower.contains("current") {
            constraints.append("Any new option should be meaningfully better than the current situation, not just different.")
        }
        if lower.contains("retail") && (lower.contains("don't want") || lower.contains("do not want") || lower.contains("not want")) {
            constraints.append("Role fit is constrained because retail work appears misaligned with the user's preferred path.")
        }
        if lower.contains("timeline") || lower.contains("deadline") || lower.contains("soon") {
            constraints.append("Timing matters, so the decision should not depend on a long uncertain path.")
        }
        if lower.contains("family") || lower.contains("location") {
            constraints.append("Personal and practical constraints may limit how flexible the choice really is.")
        }
        if draft.contextAttachments.isEmpty {
            constraints.append("Some key facts still need validation through evidence or direct clarification.")
        }
        return Array(constraints.uniqued().prefix(3))
    }

    private static func inferredRisks(from draft: RankingDraft, context: String, category: DecisionCategory) -> [String] {
        var risks: [String] = []
        let lower = context.lowercased()
        if isHiringContext(lower) {
            risks.append("Interview performance may be overweighted relative to actual role execution.")
            risks.append("Brand-name experience can create halo bias if the day-to-day role fit is weaker.")
        }
        if category == .career {
            risks.append("Brand prestige may be overweighted relative to role fit and long-term trajectory.")
            risks.append("The user may be underestimating the cost of stepping into the wrong role just to join a strong company.")
        }
        if lower.contains("dream company") {
            risks.append("Emotion around the dream-company signal may bias the comparison.")
        }
        if lower.contains("pilot") || lower.contains("trial") {
            risks.append("A reversible path may look safe but fail to resolve the underlying decision.")
        }
        if risks.isEmpty {
            risks.append("The current recommendation may rely on incomplete evidence or optimistic assumptions.")
        }
        return Array(risks.uniqued().prefix(3))
    }

    private static func inferredTensions(from draft: RankingDraft, context: String, options: [DecisionOptionSnapshot], category: DecisionCategory) -> [String] {
        var tensions: [String] = []
        let lower = context.lowercased()
        if isHiringContext(lower) {
            tensions.append("proven background versus direct fit for this exact role")
        }
        if category == .career {
            if lower.contains("dream company") && lower.contains("retail") {
                tensions.append("dream-company prestige versus role fit")
            }
            tensions.append("near-term practical fit versus long-term upside")
        } else if options.count >= 2 {
            tensions.append("\(options[0].label.lowercased()) versus \(options[1].label.lowercased()) on the criteria that matter most")
        }
        if tensions.isEmpty {
            tensions.append("certainty versus upside")
        }
        return Array(tensions.uniqued().prefix(3))
    }

    private static func suggestedCriteria(
        narrative: String,
        category: DecisionCategory,
        options: [DecisionOptionSnapshot],
        goals: [String],
        constraints: [String],
        risks: [String],
        tensions: [String],
        profile: AIUserProfile?
    ) -> [CriterionDraft] {
        let optionLabels = options.map(\.label)
        let optionDescriptions = options.compactMap(\.description)
        var briefParts: [String] = [narrative]
        briefParts.append(contentsOf: goals)
        briefParts.append(contentsOf: constraints)
        briefParts.append(contentsOf: risks)
        briefParts.append(contentsOf: tensions)
        briefParts.append(contentsOf: optionLabels)
        briefParts.append(contentsOf: optionDescriptions)
        let briefBlob = briefParts
            .joined(separator: " ")
            .lowercased()

        var criteria: [CriterionDraft] = []
        func add(_ name: String, _ detail: String, _ category: String, _ weight: Double) {
            guard !containsCriterion(named: name, in: criteria) else { return }
            criteria.append(CriterionDraft(name: name, detail: detail, category: category, weightPercent: weight))
        }

        if isHiringContext(briefBlob) {
            add("Role Fit", "How directly the candidate matches the actual responsibilities and level required", "Hiring", 22)
            add("Relevant Experience", "Evidence that the candidate has handled similar scope, complexity, or environment", "Hiring", 18)
            add("Delivery Risk", "Likelihood the candidate can ramp effectively and execute without hidden gaps", "Risk", 16)
            add("Communication", "How clearly the candidate can align, explain, and collaborate with stakeholders", "Team", 14)
            add("Compensation Fit", "Whether the candidate fits the budget and expected level without major trade-offs", "Financial", 12)
            add("Team Fit", "Whether the working style and expectations fit the team context described", "Team", 18)
        } else if category == .career {
            add("Role Fit", "How well the option matches the actual work the user wants to be doing day to day", "Career", 22)
            add("Career Trajectory", "Which path creates the stronger long-term direction and future opportunities", "Career", 20)
            add("Brand & Signaling Value", "How much employer reputation materially helps future mobility", "Strategy", 12)
            add("Growth & Learning", "Whether the role builds relevant skills, exposure, and future optionality", "Growth", 16)
            add("Compensation & Practical Impact", "Financial outcome and practical day-to-day impact", "Financial", 14)
            add("Reversibility", "How costly it would be to unwind this decision if it proves wrong", "Risk", 16)
        } else {
            let promptContext: UsageContext = category == .education ? .education : .work
            criteria = PromptEngineering.recommendedCriteria(
                from: briefBlob,
                context: promptContext,
                profile: profile,
                optionCount: options.count
            )
        }

        if briefBlob.contains("retail") && briefBlob.contains("analyst") {
            add("Path Continuity", "How directly the option supports the user's preferred functional career path", "Career", 18)
        }
        if briefBlob.contains("dream company") {
            add("Aspirational Value", "Whether joining this company creates real strategic upside rather than symbolic satisfaction", "Strategy", 10)
        }

        let normalizedCriteria = RankingEngine.normalizedCriteria(criteria)
        return Array(normalizedCriteria.prefix(8))
    }

    private static func containsCriterion(named name: String, in criteria: [CriterionDraft]) -> Bool {
        criteria.contains { $0.name.caseInsensitiveCompare(name) == .orderedSame }
    }

    private static func briefSummary(
        narrative: String,
        options: [DecisionOptionSnapshot],
        goals: [String],
        constraints: [String],
        tensions: [String]
    ) -> String {
        let optionSummary = options.prefix(2).map(\.label).joined(separator: " vs ")
        let goal = goals.first?.lowercased() ?? "make a sound decision"
        let constraint = constraints.first?.lowercased() ?? "the available constraints"
        let tension = tensions.first?.lowercased() ?? "the key trade-off"
        let core = optionSummary.isEmpty ? narrative : optionSummary
        return "Decision brief: \(core). The user is trying to \(goal) while respecting \(constraint). The central trade-off is \(tension)."
    }

    private static func extractCareerOptions(from draft: RankingDraft) -> [DecisionOptionSnapshot]? {
        let text = combinedContext(for: draft, extractedEvidence: []).replacingOccurrences(of: "\n", with: " ")
        let current = extractCurrentRole(from: text)
        let offer = extractOfferRole(from: text)

        var options: [DecisionOptionSnapshot] = []
        if let current {
            let label = current.company.isEmpty
                ? "Stay in current \(current.role.nonEmpty ?? "role")"
                : "Stay at \(current.company) in \(current.role.nonEmpty ?? "your current role")"
            let description = "Keep the current path, protect continuity, and preserve fit with \(current.role.nonEmpty ?? "the current role") while keeping the career path more direct."
            options.append(DecisionOptionSnapshot(label: label, description: description, aiSuggested: true))
        }
        if let offer {
            let companyLabel = offer.company.isEmpty ? "the new role" : offer.company
            let roleLabel = offer.role.nonEmpty ?? "the offered role"
            let label = "Accept \(companyLabel) \(roleLabel)"
            let description = "Move toward \(companyLabel) if the prestige, growth, and future signaling outweigh the role-fit risk of \(roleLabel)."
            options.append(DecisionOptionSnapshot(label: label, description: description, aiSuggested: true))
        }

        if options.count >= 2 {
            if let alternative = draft.alternativePathAnswer?.trimmingCharacters(in: .whitespacesAndNewlines),
               !alternative.isEmpty {
                options.append(alternativeOption(from: alternative, draft: draft))
            } else if let offer, text.lowercased().contains("dream company") {
                options.append(
                    DecisionOptionSnapshot(
                        label: "Clarify growth path with \(offer.company.isEmpty ? "the new company" : offer.company)",
                        description: "Ask whether there is a credible path from the offered role into a role closer to the user's long-term target before committing.",
                        aiSuggested: true
                    )
                )
            }
            return Array(options.prefix(3))
        }

        return nil
    }

    private static func extractExplicitChoiceOptions(from draft: RankingDraft) -> [DecisionOptionSnapshot]? {
        let text = combinedContext(for: draft, extractedEvidence: []).replacingOccurrences(of: "\n", with: " ")

        if let options = extractBetweenOptions(from: text), options.count >= 2 {
            return Array(options.prefix(4))
        }

        if let options = extractShouldIOptions(from: text), options.count >= 2 {
            return Array(options.prefix(4))
        }

        if let options = extractComparedListOptions(from: text), options.count >= 2 {
            return Array(options.prefix(4))
        }

        return nil
    }

    private static func extractBetweenOptions(from text: String) -> [DecisionOptionSnapshot]? {
        guard let match = regexGroups(
            pattern: #"(?i)(?:between|comparing)\s+(.+?)\s+and\s+(.+?)(?:[?.!,]|$)"#,
            in: text
        ), match.count >= 2 else {
            return nil
        }

        let candidates = match.prefix(2).map(cleanOptionLabel)
        let options = candidates.compactMap { label -> DecisionOptionSnapshot? in
            guard !label.isEmpty else { return nil }
            return DecisionOptionSnapshot(
                label: sentenceCase(label),
                description: "Option taken directly from your brief.",
                aiSuggested: true
            )
        }
        return options.count >= 2 ? options : nil
    }

    private static func extractShouldIOptions(from text: String) -> [DecisionOptionSnapshot]? {
        guard let match = regexGroups(
            pattern: #"(?i)should\s+i\s+(.+?)\s+or\s+(.+?)(?:[?.!,]|$)"#,
            in: text
        ), match.count >= 2 else {
            return nil
        }

        let options = match.prefix(2).compactMap { phrase -> DecisionOptionSnapshot? in
            let label = cleanOptionLabel(phrase)
            guard !label.isEmpty else { return nil }
            return DecisionOptionSnapshot(
                label: sentenceCase(label),
                description: "Option taken directly from your brief.",
                aiSuggested: true
            )
        }
        return options.count >= 2 ? options : nil
    }

    private static func extractComparedListOptions(from text: String) -> [DecisionOptionSnapshot]? {
        guard let match = regexGroups(
            pattern: #"(?i)(?:compare|comparing|choosing\s+between)\s+(.+?)(?:\s+for\s+|\s+based\s+on\s+|[?.!]|$)"#,
            in: text
        ), let first = match.first else {
            return nil
        }

        let normalized = first
            .replacingOccurrences(of: " and ", with: ",")
            .split(separator: ",")
            .map { cleanOptionLabel(String($0)) }
            .filter { !$0.isEmpty }

        let options = normalized.prefix(4).map { label in
            DecisionOptionSnapshot(
                label: sentenceCase(label),
                description: "Option taken directly from your brief.",
                aiSuggested: true
            )
        }
        return options.count >= 2 ? options : nil
    }

    private static func extractCurrentRole(from text: String) -> (role: String, company: String)? {
        if let match = regexGroups(
            pattern: #"(?i)(?:currently\s+)?(?:i['’]m\s+)?working\s+as\s+(.+?)\s+at\s+([A-Za-z][A-Za-z0-9&' .-]{2,60})"#,
            in: text
        ), match.count >= 2 {
            return (cleanExtractedPhrase(match[0]), cleanExtractedPhrase(match[1]))
        }
        if let match = regexGroups(
            pattern: #"(?i)(?:currently\s+)?(?:i['’]m\s+)?working\s+at\s+([A-Za-z][A-Za-z0-9&' .-]{2,60})"#,
            in: text
        ), let company = match.first {
            return ("current role", cleanExtractedPhrase(company))
        }
        return nil
    }

    private static func extractOfferRole(from text: String) -> (role: String, company: String)? {
        if let match = regexGroups(
            pattern: #"(?i)([A-Za-z][A-Za-z0-9&' .-]{2,60})\s+offered\s+me\s+(?:a\s+)?job\s+offer\s+as\s+(.+?)(?:\s+at\s+|\s+in\s+|$)"#,
            in: text
        ), match.count >= 2 {
            return (cleanExtractedPhrase(match[1]), cleanExtractedPhrase(match[0]))
        }
        if let match = regexGroups(
            pattern: #"(?i)(?:job\s+offer|offer)\s+as\s+(.+?)\s+(?:at|in)\s+([A-Za-z][A-Za-z0-9&' .-]{2,60})"#,
            in: text
        ), match.count >= 2 {
            return (cleanExtractedPhrase(match[0]), cleanExtractedPhrase(match[1]))
        }
        return nil
    }

    private static func regexGroups(pattern: String, in text: String) -> [String]? {
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return nil }
        let nsrange = NSRange(text.startIndex..<text.endIndex, in: text)
        guard let match = regex.firstMatch(in: text, range: nsrange), match.numberOfRanges > 1 else { return nil }
        return (1..<match.numberOfRanges).compactMap { index in
            let range = match.range(at: index)
            guard let swiftRange = Range(range, in: text) else { return nil }
            return String(text[swiftRange])
        }
    }

    private static func cleanExtractedPhrase(_ text: String) -> String {
        text
            .replacingOccurrences(of: "  ", with: " ")
            .trimmingCharacters(in: CharacterSet(charactersIn: " .,\n\t"))
    }

    private static func optionTemplates(for draft: RankingDraft) -> [(label: String, description: String)] {
        switch draft.category {
        case .career:
            return [
                ("Stay and negotiate", "Keep the current path but improve terms, scope, or timeline."),
                ("Accept the alternative offer", "Take the stronger external opportunity if the evidence supports it."),
                ("Create a short pilot path", "Delay the irreversible move and test the new direction with a time-boxed experiment.")
            ]
        case .finance:
            return [
                ("Lower-risk option", "Prioritize downside protection and predictable outcomes."),
                ("Higher-upside option", "Accept more volatility for stronger potential return."),
                ("Staged approach", "Commit partially now and reevaluate after a defined milestone.")
            ]
        case .business:
            return [
                ("Keep the current approach", "Preserve continuity if switching costs or execution risk are still too high."),
                ("Move to the stronger alternative", "Choose the option that better fits the evidence on quality, cost, and delivery confidence."),
                ("Run a short pilot first", "Use a scoped test before committing to a full switch.")
            ]
        case .health, .relationships, .lifestyle:
            return [
                ("Keep current path", "The more stable and lower-regret path."),
                ("Switch to new path", "The higher-change path with more upside and more uncertainty."),
                ("Time-boxed trial", "Test a reversible middle ground before fully committing.")
            ]
        default:
            return [
                ("Build internally", "Keep more control, but accept higher execution burden."),
                ("Choose an external solution", "Move faster by using an outside option with acceptable trade-offs."),
                ("Pilot before committing", "Run a smaller test first to reduce uncertainty.")
            ]
        }
    }

    private static func creativeOption(for draft: RankingDraft, userProfile: AIUserProfile?) -> DecisionOptionSnapshot {
        let challenge = userProfile?.biggestChallenge ?? ""
        let label: String
        let description: String

        switch draft.category {
        case .career:
            label = "Run a time-boxed negotiation"
            description = "Ask for a defined change in scope, compensation, or timeline before making an irreversible move."
        case .finance:
            label = "Commit in stages"
            description = "Reduce downside by making a partial move now and setting a review trigger before full commitment."
        case .business, .education:
            label = "Pilot the smallest viable version"
            description = "Test the leading option with a narrow pilot so you learn before committing fully."
        default:
            label = "Create a reversible trial path"
            description = "Choose the option that gives you new information without locking you in too early."
        }

        if challenge == BiggestChallenge.overthinking.rawValue {
            return DecisionOptionSnapshot(label: label, description: description + " This is designed to create clarity without forcing a permanent commitment too early.", aiSuggested: true)
        }

        return DecisionOptionSnapshot(label: label, description: description, aiSuggested: true)
    }

    private static func inferredDescription(for name: String, draft: RankingDraft) -> String {
        let context = draft.contextNarrative.lowercased()
        let lowerName = name.lowercased()
        if draft.category == .business || lowerName.contains("service") || lowerName.contains("agency") || lowerName.contains("vendor") {
            return "Compare this option on delivery quality, responsiveness, commercial terms, and how much execution risk it removes."
        }
        if context.contains("timeline") || context.contains("deadline") {
            return "This option should be evaluated for speed, implementation load, and delivery risk."
        }
        return "This option should be evaluated against the criteria that matter most in your current situation."
    }

    private static func alternativeOption(from answer: String, draft: RankingDraft) -> DecisionOptionSnapshot {
        let normalized = answer
            .replacingOccurrences(of: "\n", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let label = normalized
            .split(separator: ".")
            .first
            .map(String.init)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .prefix(44) ?? "Alternative path"

        return DecisionOptionSnapshot(
            label: String(label),
            description: "Alternative path from your answer: \(normalized)",
            aiSuggested: true
        )
    }

    private static func evidenceSnippet(for criterion: CriterionDraft, vendor: VendorDraft, extractedEvidence: [String]) -> String {
        let vendorName = vendor.name.trimmingCharacters(in: .whitespacesAndNewlines)
        let joinedEvidence = extractedEvidence.joined(separator: "\n")
        if let line = joinedEvidence
            .split(separator: "\n")
            .map(String.init)
            .first(where: {
                let lower = $0.lowercased()
                return lower.contains(vendorName.lowercased()) || lower.contains(criterion.name.lowercased())
            }) {
            return line
        }
        return "Drafted from your brief, answers, and the current evidence available for \(vendorName.isEmpty ? "this option" : vendorName)."
    }

    private static func signalCount(in text: String, for criterion: CriterionDraft) -> Int {
        let signals = criterionSignals(for: criterion)
        return signals.reduce(into: 0) { partialResult, signal in
            if text.contains(signal) {
                partialResult += 1
            }
        }
    }

    private static func signalMatches(in text: String, signals: [String]) -> Int {
        signals.reduce(into: 0) { partialResult, signal in
            if text.contains(signal) {
                partialResult += 1
            }
        }
    }

    private static func criterionSignals(for criterion: CriterionDraft) -> [String] {
        let key = criterion.name.lowercased()
        if key.contains("role fit") || key.contains("path continuity") {
            return ["role", "fit", "analyst", "retail", "career path", "misaligned", "aligned"]
        }
        if key.contains("career trajectory") {
            return ["career", "trajectory", "future", "promotion", "growth", "progression", "path"]
        }
        if key.contains("brand") || key.contains("signaling") || key.contains("aspirational") {
            return ["brand", "reputation", "prestige", "dream company", "signal", "name value"]
        }
        if key.contains("reversibility") {
            return ["reversible", "reverse", "switch", "return", "optionality", "exit"]
        }
        if key.contains("cost") || key.contains("budget") {
            return ["cost", "budget", "price", "fee", "cheaper", "roi", "salary", "compensation"]
        }
        if key.contains("risk") || key.contains("security") || key.contains("compliance") {
            return ["risk", "security", "compliance", "legal", "safe", "downside", "exposure"]
        }
        if key.contains("quality") || key.contains("performance") {
            return ["quality", "reliable", "performance", "outcome", "results", "strong"]
        }
        if key.contains("support") || key.contains("responsiveness") {
            return ["support", "service", "response", "availability", "partner"]
        }
        if key.contains("time") || key.contains("speed") {
            return ["timeline", "deadline", "fast", "quick", "time", "speed"]
        }
        if key.contains("integration") {
            return ["integration", "api", "compatibility", "migration", "stack"]
        }
        if key.contains("growth") || key.contains("scalability") {
            return ["growth", "scale", "future", "expand", "learning", "upside"]
        }
        return key.split(separator: " ").map(String.init)
    }

    private static func positiveSignals(for criterion: CriterionDraft) -> [String] {
        let key = criterion.name.lowercased()
        if key.contains("relevant experience") {
            return ["relevant", "similar", "experience", "hands-on", "delivered", "owned", "shipped", "managed"]
        }
        if key.contains("delivery risk") {
            return ["reliable", "consistent", "shipped", "delivered", "proven", "stable", "low risk"]
        }
        if key.contains("communication") {
            return ["clear", "communicates", "stakeholder", "collaborative", "explains", "alignment"]
        }
        if key.contains("team fit") {
            return ["team fit", "collaborative", "works well", "partnership", "cross-functional", "culture"]
        }
        if key.contains("compensation fit") {
            return ["within budget", "budget fit", "reasonable", "compensation fit", "salary fit"]
        }
        if key.contains("role fit") || key.contains("path continuity") {
            return ["aligned", "fit", "matches", "analyst", "career path", "preferred role"]
        }
        if key.contains("career trajectory") {
            return ["growth", "promotion", "future", "trajectory", "path", "upside", "progression"]
        }
        if key.contains("brand") || key.contains("signaling") || key.contains("aspirational") {
            return ["prestige", "reputation", "dream company", "brand", "signal", "strong company"]
        }
        if key.contains("reversibility") {
            return ["reversible", "easy to change", "optionality", "low lock-in", "recover"]
        }
        if key.contains("cost") || key.contains("budget") {
            return ["within budget", "savings", "lower cost", "affordable", "roi", "efficient"]
        }
        if key.contains("risk") || key.contains("security") || key.contains("compliance") {
            return ["compliant", "secure", "low risk", "certified", "controlled", "stable"]
        }
        if key.contains("time") || key.contains("speed") {
            return ["fast", "quick", "immediate", "on time", "short timeline"]
        }
        if key.contains("growth") || key.contains("learning") || key.contains("scalability") {
            return ["growth", "scale", "future", "promotion", "expand", "upside", "learn"]
        }
        if key.contains("quality") || key.contains("performance") {
            return ["quality", "reliable", "strong", "excellent", "proven", "better outcome"]
        }
        return criterionSignals(for: criterion)
    }

    private static func negativeSignals(for criterion: CriterionDraft) -> [String] {
        let key = criterion.name.lowercased()
        if key.contains("relevant experience") {
            return ["unclear experience", "untested", "adjacent only", "light experience", "limited exposure"]
        }
        if key.contains("delivery risk") {
            return ["risky", "uncertain", "ramp risk", "execution risk", "inconsistent", "gap"]
        }
        if key.contains("communication") {
            return ["unclear", "vague", "poor communication", "misaligned", "weak communication"]
        }
        if key.contains("team fit") {
            return ["poor fit", "misaligned", "friction", "mismatch", "culture mismatch"]
        }
        if key.contains("compensation fit") {
            return ["over budget", "too expensive", "salary gap", "compensation mismatch"]
        }
        if key.contains("role fit") || key.contains("path continuity") {
            return ["retail", "misaligned", "wrong role", "doesn't want", "do not want", "not fit"]
        }
        if key.contains("career trajectory") {
            return ["dead end", "off track", "misaligned", "detour", "stagnant"]
        }
        if key.contains("brand") || key.contains("signaling") || key.contains("aspirational") {
            return ["symbolic", "surface-level", "prestige only", "wrong role"]
        }
        if key.contains("reversibility") {
            return ["hard to reverse", "lock in", "costly to unwind", "stuck"]
        }
        if key.contains("cost") || key.contains("budget") {
            return ["expensive", "over budget", "hidden cost", "higher fee", "costly"]
        }
        if key.contains("risk") || key.contains("security") || key.contains("compliance") {
            return ["risk", "exposure", "security gap", "uncertain", "non compliant", "legal issue"]
        }
        if key.contains("time") || key.contains("speed") {
            return ["delay", "slow", "long timeline", "late", "blocked"]
        }
        if key.contains("support") {
            return ["poor support", "slow response", "unresponsive", "limited help"]
        }
        if key.contains("quality") || key.contains("performance") {
            return ["bug", "failure", "weak", "unstable", "poor quality"]
        }
        return ["risk", "delay", "unclear", "weak", "problem"]
    }

    private static func vendorEvidenceHits(for vendor: VendorDraft, criterion: CriterionDraft, evidence: [String]) -> Int {
        let vendorName = vendor.name.lowercased()
        let criterionName = criterion.name.lowercased()
        return evidence.reduce(into: 0) { partialResult, snippet in
            let lower = snippet.lowercased()
            if lower.contains(vendorName), lower.contains(criterionName) {
                partialResult += 2
            } else if lower.contains(vendorName) || lower.contains(criterionName) {
                partialResult += 1
            }
        }
    }

    private static func topValueAlignmentBoost(for criterion: CriterionDraft, profile: AIUserProfile?) -> Double {
        guard let topValue = profile?.valuesRanking.first?.lowercased(), !topValue.isEmpty else {
            return 0
        }

        let criterionBlob = "\(criterion.name) \(criterion.detail) \(criterion.category)".lowercased()
        if criterionBlob.contains(topValue) {
            return 0.55
        }
        if topValue.contains("security") && criterionBlob.contains("risk") {
            return 0.35
        }
        if topValue.contains("growth") && (criterionBlob.contains("learning") || criterionBlob.contains("scalability")) {
            return 0.35
        }
        if topValue.contains("stability") && (criterionBlob.contains("risk") || criterionBlob.contains("support")) {
            return 0.35
        }
        return 0
    }

    private static func strongestTheme(in context: String, profile: AIUserProfile?) -> String {
        let themes = ["cost", "risk", "timeline", "growth", "quality", "support", "security"]
        let matched = themes.max { lhs, rhs in
            context.components(separatedBy: lhs).count < context.components(separatedBy: rhs).count
        }
        if let matched, context.contains(matched) {
            return matched
        }
        if let topValue = profile?.valuesRanking.first?.lowercased(), !topValue.isEmpty {
            return topValue
        }
        return "quality"
    }

    private static func strongestSeparation(in draft: RankingDraft, winnerID: String?, runnerUpID: String?) -> (criterion: String, gap: Double)? {
        guard let winnerID, let runnerUpID else { return nil }
        return draft.criteria.compactMap { criterion in
            let winnerScore = draft.scores.first(where: { $0.vendorID == winnerID && $0.criterionID == criterion.id })?.score ?? 0
            let runnerScore = draft.scores.first(where: { $0.vendorID == runnerUpID && $0.criterionID == criterion.id })?.score ?? 0
            let gap = abs(winnerScore - runnerScore) * (criterion.weightPercent / 100)
            return gap > 0 ? (criterion.name, gap) : nil
        }
        .max { $0.1 < $1.1 }
    }

    private static func combinedContext(for draft: RankingDraft, extractedEvidence: [String]) -> String {
        let vendorText = draft.vendors
            .flatMap { vendor in
                [vendor.name, vendor.notes] + vendor.attachments.map { [$0.fileName, $0.titleHint, $0.validationMessage].joined(separator: " ") }
            }
            .joined(separator: " ")
        let answers = draft.clarifyingQuestions.map(\.answer).joined(separator: " ")
        let biasText = draft.biasChallenges.map(\.response).joined(separator: " ")
        let attachments = draft.contextAttachments.map { [$0.fileName, $0.titleHint, $0.validationMessage].joined(separator: " ") }.joined(separator: " ")
        return ([draft.contextNarrative, draft.conversationSummary, draft.alternativePathAnswer ?? "", vendorText, answers, biasText, attachments] + extractedEvidence)
            .joined(separator: " ")
    }

    private static func isHiringContext(_ text: String) -> Bool {
        let lower = text.lowercased()
        return lower.contains("candidate") ||
            lower.contains("recruit") ||
            lower.contains("hiring") ||
            lower.contains("hire") ||
            lower.contains("interview") ||
            lower.contains("applicant")
    }

    private static func cleanOptionLabel(_ text: String) -> String {
        text
            .replacingOccurrences(of: "\n", with: " ")
            .replacingOccurrences(of: "  ", with: " ")
            .trimmingCharacters(in: CharacterSet(charactersIn: " .,:;!?\"'"))
    }

    private static func sentenceCase(_ text: String) -> String {
        guard let first = text.first else { return text }
        return first.uppercased() + text.dropFirst()
    }

    private static func normalizedText(_ text: String) -> String {
        text
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
    }

    private static func stableHash(_ text: String) -> Int {
        text.unicodeScalars.reduce(5381) { (($0 << 5) &+ $0) &+ Int($1.value) }
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

    func generateDecisionBrief(for draft: RankingDraft, extractedEvidence: [String], userProfile: AIUserProfile?) async throws -> DecisionBrief {
        do {
            let text = try await sendMessage(
                system: AnthropicPromptBuilder.systemPrompt(profile: userProfile),
                user: AnthropicPromptBuilder.decisionBriefPrompt(draft: draft, extractedEvidence: extractedEvidence, profile: userProfile)
            )
            let data = try parseJSONObjectData(text)
            return try JSONDecoder().decode(DecisionBrief.self, from: data)
        } catch {
            return try await fallback.generateDecisionBrief(for: draft, extractedEvidence: extractedEvidence, userProfile: userProfile)
        }
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

    func startDecisionConversation(projectID: String, contextNarrative: String, usageContext: UsageContext, userProfile: AIUserProfile?) async throws -> DecisionConversationResponse {
        try await fallback.startDecisionConversation(
            projectID: projectID,
            contextNarrative: contextNarrative,
            usageContext: usageContext,
            userProfile: userProfile
        )
    }

    func continueDecisionConversation(projectID: String, transcript: [DecisionChatMessage], latestUserResponse: String, selectedOptionIndex: Int?, draft: RankingDraft, userProfile: AIUserProfile?) async throws -> DecisionConversationResponse {
        try await fallback.continueDecisionConversation(
            projectID: projectID,
            transcript: transcript,
            latestUserResponse: latestUserResponse,
            selectedOptionIndex: selectedOptionIndex,
            draft: draft,
            userProfile: userProfile
        )
    }

    func finalizeConversationForMatrix(projectID: String, transcript: [DecisionChatMessage], draft: RankingDraft, userProfile: AIUserProfile?) async throws -> DecisionMatrixSetup {
        try await fallback.finalizeConversationForMatrix(
            projectID: projectID,
            transcript: transcript,
            draft: draft,
            userProfile: userProfile
        )
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
        return AISuggestedInputs(
            criteria: criteria,
            draftScores: scores,
            citations: parseEvidenceCitations(payload["citations"] as Any)
        )
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
    private let allowLocalFallback: Bool

    init(
        functions: Functions? = nil,
        fallback: AIservicing = LocalMockAIService(),
        allowLocalFallback: Bool = ProcessInfo.processInfo.environment["SCOREWISE_ENABLE_LOCAL_AI_FALLBACK"] == "1"
    ) {
        self.functions = functions ?? Functions.functions()
        self.fallback = fallback
        self.allowLocalFallback = allowLocalFallback
    }

    func generateDecisionBrief(for draft: RankingDraft, extractedEvidence: [String], userProfile: AIUserProfile?) async throws -> DecisionBrief {
        do {
            var payload: [String: Any] = [
                "projectId": draft.id,
                "transcript": [],
                "draft": [
                    "title": draft.title,
                    "contextNarrative": draft.contextNarrative,
                    "usageContext": draft.usageContext.rawValue,
                    "vendors": draft.vendors.map { ["id": $0.id, "name": $0.name, "notes": $0.notes] },
                    "clarifyingQuestions": draft.clarifyingQuestions.map { ["question": $0.question, "answer": $0.answer] },
                    "extractedText": extractedEvidence
                ]
            ]
            if let userProfile {
                payload["userProfile"] = Self.userProfileDictionary(userProfile)
            }
            let result = try await functions.httpsCallable("finalizeConversationForMatrix").call(payload)
            return try Self.parseDecisionMatrixSetup(result.data, fallbackCategory: draft.category).decisionBrief
        } catch {
            if allowLocalFallback {
                logAIFallback(functionName: "generateDecisionBrief", projectID: draft.id, error: error)
                return try await fallback.generateDecisionBrief(for: draft, extractedEvidence: extractedEvidence, userProfile: userProfile)
            }
            logAICloudError(functionName: "generateDecisionBrief", projectID: draft.id, error: error)
            throw ScoreWiseServiceError.featureUnavailable("AI decision brief generation is unavailable right now. Please retry.")
        }
    }

    func suggestRankingInputs(for draft: RankingDraft, context: UsageContext, extractedEvidence: [String], userProfile: AIUserProfile?) async throws -> AISuggestedInputs {
        do {
            var payload: [String: Any] = [
                "projectId": draft.id,
                "usageContext": context.rawValue,
                "contextNarrative": draft.contextNarrative,
                "vendors": draft.vendors.map { ["id": $0.id, "name": $0.name, "notes": $0.notes] },
                "extractedText": extractedEvidence
            ]
            if let userProfile {
                payload["userProfile"] = Self.userProfileDictionary(userProfile)
            }
            let result = try await functions.httpsCallable("suggestRankingInputs").call(payload)
            return parseSuggestedInputs(result.data, draft: draft)
        } catch {
            if allowLocalFallback {
                logAIFallback(functionName: "suggestRankingInputs", projectID: draft.id, phase: context.rawValue, error: error)
                return try await fallback.suggestRankingInputs(for: draft, context: context, extractedEvidence: extractedEvidence, userProfile: userProfile)
            }
            logAICloudError(functionName: "suggestRankingInputs", projectID: draft.id, phase: context.rawValue, error: error)
            throw ScoreWiseServiceError.featureUnavailable("AI matrix suggestions are unavailable right now. Please retry.")
        }
    }

    func generateClarifyingQuestions(for draft: RankingDraft, userProfile: AIUserProfile?) async throws -> [ClarifyingQuestionAnswer] {
        do {
            var payload: [String: Any] = [
                "projectId": draft.id,
                "situationText": draft.contextNarrative
            ]
            if let userProfile {
                payload["userProfile"] = Self.userProfileDictionary(userProfile)
            }
            let result = try await functions.httpsCallable("generateClarifyingQuestions").call(payload)
            return Self.parseClarifyingQuestions(result.data)
        } catch {
            if allowLocalFallback {
                logAIFallback(functionName: "generateClarifyingQuestions", projectID: draft.id, error: error)
                return try await fallback.generateClarifyingQuestions(for: draft, userProfile: userProfile)
            }
            logAICloudError(functionName: "generateClarifyingQuestions", projectID: draft.id, error: error)
            throw ScoreWiseServiceError.featureUnavailable("AI clarifying questions are unavailable right now. Please retry.")
        }
    }

    func suggestDecisionOptions(for draft: RankingDraft, userProfile: AIUserProfile?) async throws -> [DecisionOptionSnapshot] {
        do {
            var payload: [String: Any] = [
                "projectId": draft.id,
                "situationText": draft.contextNarrative,
                "clarifyingQuestions": draft.clarifyingQuestions.map { ["question": $0.question, "answer": $0.answer] }
            ]
            if let userProfile {
                payload["userProfile"] = Self.userProfileDictionary(userProfile)
            }
            let result = try await functions.httpsCallable("suggestDecisionOptions").call(payload)
            return Self.parseOptions(result.data)
        } catch {
            if allowLocalFallback {
                logAIFallback(functionName: "suggestDecisionOptions", projectID: draft.id, error: error)
                return try await fallback.suggestDecisionOptions(for: draft, userProfile: userProfile)
            }
            logAICloudError(functionName: "suggestDecisionOptions", projectID: draft.id, error: error)
            throw ScoreWiseServiceError.featureUnavailable("AI option extraction is unavailable right now. Please retry.")
        }
    }

    func generateBiasChallenges(for draft: RankingDraft, preferredOption: String, userProfile: AIUserProfile?) async throws -> [BiasChallengeResponse] {
        do {
            var payload: [String: Any] = [
                "projectId": draft.id,
                "preferredOption": preferredOption,
                "situationText": draft.contextNarrative,
                "clarifyingQuestions": draft.clarifyingQuestions.map { ["question": $0.question, "answer": $0.answer] }
            ]
            if let userProfile {
                payload["userProfile"] = Self.userProfileDictionary(userProfile)
            }
            let result = try await functions.httpsCallable("generateBiasChallenges").call(payload)
            return Self.parseBiasChallenges(result.data)
        } catch {
            if allowLocalFallback {
                logAIFallback(functionName: "generateBiasChallenges", projectID: draft.id, error: error)
                return try await fallback.generateBiasChallenges(for: draft, preferredOption: preferredOption, userProfile: userProfile)
            }
            logAICloudError(functionName: "generateBiasChallenges", projectID: draft.id, error: error)
            throw ScoreWiseServiceError.featureUnavailable("AI challenge generation is unavailable right now. Please retry.")
        }
    }

    func startDecisionConversation(projectID: String, contextNarrative: String, usageContext: UsageContext, userProfile: AIUserProfile?) async throws -> DecisionConversationResponse {
        do {
            var payload: [String: Any] = [
                "projectId": projectID,
                "contextNarrative": contextNarrative,
                "usageContext": usageContext.rawValue
            ]
            if let userProfile {
                payload["userProfile"] = Self.userProfileDictionary(userProfile)
            }
            let result = try await functions.httpsCallable("startDecisionConversation").call(payload)
            return try Self.parseConversationResponse(result.data)
        } catch {
            if allowLocalFallback {
                logAIFallback(functionName: "startDecisionConversation", projectID: projectID, error: error)
                return try await fallback.startDecisionConversation(
                    projectID: projectID,
                    contextNarrative: contextNarrative,
                    usageContext: usageContext,
                    userProfile: userProfile
                )
            }
            logAICloudError(functionName: "startDecisionConversation", projectID: projectID, error: error)
            throw ScoreWiseServiceError.featureUnavailable("Could not start AI decision conversation. Please retry.")
        }
    }

    func continueDecisionConversation(projectID: String, transcript: [DecisionChatMessage], latestUserResponse: String, selectedOptionIndex: Int?, draft: RankingDraft, userProfile: AIUserProfile?) async throws -> DecisionConversationResponse {
        do {
            var payload: [String: Any] = [
                "projectId": projectID,
                "transcript": Self.serializeTranscript(transcript),
                "latestUserResponse": latestUserResponse,
                "selectedOptionIndex": selectedOptionIndex as Any,
                "draft": [
                    "title": draft.title,
                    "contextNarrative": draft.contextNarrative,
                    "chatPhase": draft.chatPhase.rawValue,
                    "frameworksUsed": draft.frameworksUsed.map(\.rawValue)
                ]
            ]
            if let userProfile {
                payload["userProfile"] = Self.userProfileDictionary(userProfile)
            }
            let result = try await functions.httpsCallable("continueDecisionConversation").call(payload)
            return try Self.parseConversationResponse(result.data)
        } catch {
            if allowLocalFallback {
                logAIFallback(functionName: "continueDecisionConversation", projectID: projectID, error: error)
                return try await fallback.continueDecisionConversation(
                    projectID: projectID,
                    transcript: transcript,
                    latestUserResponse: latestUserResponse,
                    selectedOptionIndex: selectedOptionIndex,
                    draft: draft,
                    userProfile: userProfile
                )
            }
            logAICloudError(functionName: "continueDecisionConversation", projectID: projectID, error: error)
            throw ScoreWiseServiceError.featureUnavailable("Could not continue AI decision conversation. Please retry.")
        }
    }

    func finalizeConversationForMatrix(projectID: String, transcript: [DecisionChatMessage], draft: RankingDraft, userProfile: AIUserProfile?) async throws -> DecisionMatrixSetup {
        do {
            var payload: [String: Any] = [
                "projectId": projectID,
                "transcript": Self.serializeTranscript(transcript),
                "draft": [
                    "title": draft.title,
                    "contextNarrative": draft.contextNarrative,
                    "usageContext": draft.usageContext.rawValue,
                    "chatPhase": draft.chatPhase.rawValue,
                    "frameworksUsed": draft.frameworksUsed.map(\.rawValue),
                    "vendors": draft.vendors.map { ["id": $0.id, "name": $0.name, "notes": $0.notes] },
                    "clarifyingQuestions": draft.clarifyingQuestions.map { ["question": $0.question, "answer": $0.answer] }
                ]
            ]
            if let userProfile {
                payload["userProfile"] = Self.userProfileDictionary(userProfile)
            }
            let result = try await functions.httpsCallable("finalizeConversationForMatrix").call(payload)
            return try Self.parseDecisionMatrixSetup(result.data, fallbackCategory: draft.category)
        } catch {
            if allowLocalFallback {
                logAIFallback(functionName: "finalizeConversationForMatrix", projectID: projectID, error: error)
                return try await fallback.finalizeConversationForMatrix(
                    projectID: projectID,
                    transcript: transcript,
                    draft: draft,
                    userProfile: userProfile
                )
            }
            logAICloudError(functionName: "finalizeConversationForMatrix", projectID: projectID, error: error)
            throw ScoreWiseServiceError.featureUnavailable("Could not finalize matrix setup from AI conversation. Please retry.")
        }
    }

    func decisionChat(projectID: String, phase: String, message: String, draft: RankingDraft?, userProfile: AIUserProfile?) async throws -> AIChatResponse {
        do {
            var payload: [String: Any] = [
                "projectId": projectID,
                "phase": phase,
                "message": message
            ]
            if let draft {
                payload["draft"] = [
                    "title": draft.title,
                    "contextNarrative": draft.contextNarrative
                ]
            }
            if let userProfile {
                payload["userProfile"] = Self.userProfileDictionary(userProfile)
            }
            let result = try await functions.httpsCallable("decisionChat").call(payload)
            guard let dictionary = result.data as? [String: Any] else {
                let shapeError = ScoreWiseServiceError.featureUnavailable("Invalid callable payload shape")
                if allowLocalFallback {
                    logAIFallback(functionName: "decisionChat", projectID: projectID, phase: phase, error: shapeError)
                    return try await fallback.decisionChat(projectID: projectID, phase: phase, message: message, draft: draft, userProfile: userProfile)
                }
                logAICloudError(functionName: "decisionChat", projectID: projectID, phase: phase, error: shapeError)
                throw ScoreWiseServiceError.featureUnavailable("AI analysis payload is invalid. Please retry.")
            }
            let content: String
            if let raw = dictionary["content"] as? String {
                content = raw
            } else if let structured = dictionary["content"] as? [String: Any] {
                let reassurance = structured["reassurance"] as? String
                let reasoning = structured["reasoning"] as? String
                let nextSteps = structured["nextSteps"] as? [String] ?? []
                let sections = [reassurance, reasoning]
                    .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
                    .filter { !$0.isEmpty }
                if nextSteps.isEmpty {
                    content = sections.joined(separator: "\n\n")
                } else {
                    let bullets = nextSteps.map { "• \($0)" }.joined(separator: "\n")
                    content = (sections + ["Next steps:\n\(bullets)"]).joined(separator: "\n\n")
                }
            } else {
                content = "I need more context to provide a grounded recommendation."
            }
            let actions = dictionary["recommendedActions"] as? [String] ?? []
            let citations = parseEvidenceCitations(dictionary["citations"] as Any)
            return AIChatResponse(content: content, recommendedActions: actions, citations: citations)
        } catch {
            if allowLocalFallback {
                logAIFallback(functionName: "decisionChat", projectID: projectID, phase: phase, error: error)
                return try await fallback.decisionChat(projectID: projectID, phase: phase, message: message, draft: draft, userProfile: userProfile)
            }
            logAICloudError(functionName: "decisionChat", projectID: projectID, phase: phase, error: error)
            throw ScoreWiseServiceError.featureUnavailable("AI analysis is unavailable right now. Please retry.")
        }
    }

    func generateInsights(draft: RankingDraft, result: RankingResult, userProfile: AIUserProfile?) async throws -> InsightReportDraft {
        do {
            var payload: [String: Any] = [
                "projectId": draft.id,
                "draft": [
                    "title": draft.title,
                    "usageContext": draft.usageContext.rawValue,
                    "contextNarrative": draft.contextNarrative,
                    "clarifyingQuestions": draft.clarifyingQuestions.map { ["question": $0.question, "answer": $0.answer] },
                    "biasChallenges": draft.biasChallenges.map { ["type": $0.type.rawValue, "question": $0.question, "response": $0.response] },
                    "vendors": draft.vendors.map { ["id": $0.id, "name": $0.name] },
                    "criteria": draft.criteria.map { ["id": $0.id, "name": $0.name, "weightPercent": $0.weightPercent] },
                    "scores": draft.scores.map {
                        [
                            "vendorID": $0.vendorID,
                            "criterionID": $0.criterionID,
                            "score": $0.score,
                            "confidence": $0.confidence,
                            "evidenceSnippet": $0.evidenceSnippet
                        ]
                    }
                ],
                "result": [
                    "winnerID": result.winnerID ?? "",
                    "confidenceScore": result.confidenceScore,
                    "tieDetected": result.tieDetected,
                    "rankedVendors": result.rankedVendors.map { ["vendorID": $0.vendorID, "vendorName": $0.vendorName, "totalScore": $0.totalScore] }
                ]
            ]
            if let userProfile {
                payload["userProfile"] = Self.userProfileDictionary(userProfile)
            }
            let raw = try await functions.httpsCallable("generateInsights").call(payload)
            guard let dictionary = raw.data as? [String: Any] else {
                let shapeError = ScoreWiseServiceError.featureUnavailable("Invalid callable payload shape")
                if allowLocalFallback {
                    logAIFallback(functionName: "generateInsights", projectID: draft.id, error: shapeError)
                    return try await fallback.generateInsights(draft: draft, result: result, userProfile: userProfile)
                }
                logAICloudError(functionName: "generateInsights", projectID: draft.id, error: shapeError)
                throw ScoreWiseServiceError.featureUnavailable("AI insights payload is invalid. Please retry.")
            }
            return InsightReportDraft(
                summary: dictionary["summary"] as? String ?? "",
                winnerReasoning: dictionary["winnerReasoning"] as? String ?? "",
                riskFlags: dictionary["riskFlags"] as? [String] ?? [],
                overlookedStrategicPoints: dictionary["overlookedStrategicPoints"] as? [String] ?? [],
                sensitivityFindings: dictionary["sensitivityFindings"] as? [String] ?? [],
                citations: parseEvidenceCitations(dictionary["citations"] as Any)
            )
        } catch {
            if allowLocalFallback {
                logAIFallback(functionName: "generateInsights", projectID: draft.id, error: error)
                return try await fallback.generateInsights(draft: draft, result: result, userProfile: userProfile)
            }
            logAICloudError(functionName: "generateInsights", projectID: draft.id, error: error)
            throw ScoreWiseServiceError.featureUnavailable("AI insight generation is unavailable right now. Please retry.")
        }
    }

    private func logAIFallback(functionName: String, projectID: String, phase: String? = nil, error: Error) {
        let phaseTag = phase?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false ? ", phase=\(phase ?? "")" : ""
        print("⚠️ AI_FALLBACK function=\(functionName), projectId=\(projectID)\(phaseTag), error=\(error.localizedDescription)")
    }

    private func logAICloudError(functionName: String, projectID: String, phase: String? = nil, error: Error) {
        let phaseTag = phase?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false ? ", phase=\(phase ?? "")" : ""
        print("❌ AI_CLOUD_ERROR function=\(functionName), projectId=\(projectID)\(phaseTag), error=\(error.localizedDescription)")
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

    private static func serializeTranscript(_ transcript: [DecisionChatMessage]) -> [[String: Any]] {
        transcript.map { message in
            [
                "id": message.id,
                "role": message.role.rawValue,
                "content": message.content,
                "options": message.options.map(\.text),
                "allowSkip": message.allowSkip,
                "allowsFreeformReply": message.allowsFreeformReply,
                "framework": message.framework?.rawValue as Any,
                "createdAt": ISO8601DateFormatter().string(from: message.createdAt)
            ]
        }
    }

    private static func parseConversationResponse(_ raw: Any) throws -> DecisionConversationResponse {
        guard let dictionary = raw as? [String: Any],
              let messagePayload = dictionary["message"] as? [String: Any],
              let statePayload = dictionary["conversationState"] as? [String: Any] else {
            throw ScoreWiseServiceError.featureUnavailable("Invalid conversation response payload.")
        }

        let content = (messagePayload["content"] as? String ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        if content.isEmpty {
            throw ScoreWiseServiceError.featureUnavailable("Conversation response was empty.")
        }
        let rawOptions = messagePayload["options"] as? [Any] ?? []
        let options: [DecisionChatOption] = rawOptions.enumerated().compactMap { index, item in
            if let text = item as? String {
                let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !trimmed.isEmpty else { return nil }
                return DecisionChatOption(index: index + 1, text: trimmed)
            }
            if let option = item as? [String: Any] {
                let text = (option["text"] as? String ?? option["label"] as? String ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
                guard !text.isEmpty else { return nil }
                let resolvedIndex = option["index"] as? Int ?? (index + 1)
                return DecisionChatOption(
                    id: option["id"] as? String ?? UUID().uuidString,
                    index: resolvedIndex,
                    text: text
                )
            }
            return nil
        }
        let cta: ChatMessageCTA?
        if let ctaPayload = messagePayload["cta"] as? [String: Any],
           let title = (ctaPayload["title"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines),
           !title.isEmpty {
            let actionRaw = ctaPayload["action"] as? String ?? ChatCTAAction.setupOptions.rawValue
            cta = ChatMessageCTA(title: title, action: ChatCTAAction(rawValue: actionRaw) ?? .setupOptions)
        } else {
            cta = nil
        }

        let framework: DecisionFramework?
        if let frameworkRaw = messagePayload["framework"] as? String {
            framework = DecisionFramework(rawValue: frameworkRaw)
        } else {
            framework = nil
        }

        let message = DecisionChatMessage(
            role: .assistant,
            content: content,
            options: options,
            allowSkip: messagePayload["allowSkip"] as? Bool ?? false,
            allowsFreeformReply: messagePayload["allowsFreeformReply"] as? Bool ?? false,
            cta: cta,
            framework: framework,
            createdAt: .now,
            isTypingPlaceholder: false
        )

        let phaseRaw = statePayload["phase"] as? String ?? ChatConversationPhase.collecting.rawValue
        let phase = ChatConversationPhase(rawValue: phaseRaw) ?? .collecting
        let frameworksUsed = ((statePayload["frameworksUsed"] as? [String]) ?? [])
            .compactMap { DecisionFramework(rawValue: $0) }
        let resolvedFrameworks: [DecisionFramework]
        if frameworksUsed.isEmpty, let framework {
            resolvedFrameworks = [framework]
        } else {
            resolvedFrameworks = frameworksUsed
        }
        let state = DecisionConversationState(phase: phase, frameworksUsed: resolvedFrameworks)

        return DecisionConversationResponse(message: message, conversationState: state)
    }

    private static func parseDecisionMatrixSetup(_ raw: Any, fallbackCategory: DecisionCategory) throws -> DecisionMatrixSetup {
        guard let dictionary = raw as? [String: Any] else {
            throw ScoreWiseServiceError.featureUnavailable("Invalid matrix setup payload.")
        }

        let briefPayload = dictionary["decisionBrief"] as? [String: Any] ?? [:]
        let briefOptions = parseOptions(briefPayload["detectedOptions"] as Any)
        let suggestedOptions = parseOptions(dictionary["suggestedOptions"] as Any)
        let briefCriteria = parseCriteria(briefPayload["suggestedCriteria"] as Any)
        let suggestedCriteria = parseCriteria(dictionary["suggestedCriteria"] as Any)

        let inferredCategory = DecisionCategory(rawValue: briefPayload["inferredCategory"] as? String ?? "") ?? fallbackCategory
        let decisionBrief = DecisionBrief(
            summary: (briefPayload["summary"] as? String ?? "").trimmingCharacters(in: .whitespacesAndNewlines),
            inferredCategory: inferredCategory,
            detectedOptions: briefOptions,
            goals: parseStringArray(briefPayload["goals"] as Any),
            constraints: parseStringArray(briefPayload["constraints"] as Any),
            risks: parseStringArray(briefPayload["risks"] as Any),
            tensions: parseStringArray(briefPayload["tensions"] as Any),
            suggestedCriteria: briefCriteria.isEmpty ? suggestedCriteria : briefCriteria
        )

        return DecisionMatrixSetup(
            decisionBrief: decisionBrief,
            suggestedOptions: suggestedOptions.isEmpty ? briefOptions : suggestedOptions,
            suggestedCriteria: suggestedCriteria.isEmpty ? decisionBrief.suggestedCriteria : suggestedCriteria
        )
    }

    private static func parseClarifyingQuestions(_ raw: Any) -> [ClarifyingQuestionAnswer] {
        if let dictionary = raw as? [String: Any] {
            let fallbackCitations = parseEvidenceCitations(dictionary["citations"] as Any)
            let array = dictionary["questions"] as? [Any] ?? []
            return array.compactMap {
                if let text = $0 as? String {
                    return ClarifyingQuestionAnswer(question: text, answer: "", citations: fallbackCitations)
                }
                if let dict = $0 as? [String: Any] {
                    return ClarifyingQuestionAnswer(
                        question: dict["question"] as? String ?? "",
                        answer: dict["answer"] as? String ?? "",
                        citations: {
                            let local = parseEvidenceCitations(dict["citations"] as Any)
                            return local.isEmpty ? fallbackCitations : local
                        }()
                    )
                }
                return nil
            }
        }

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
        if let array = raw as? [String] {
            return array.enumerated().compactMap { index, label in
                let trimmed = label.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !trimmed.isEmpty else { return nil }
                let lower = trimmed.lowercased()
                guard !lower.hasPrefix("vendor ") && !lower.hasPrefix("option ") else { return nil }
                return DecisionOptionSnapshot(
                    id: "opt_\(index + 1)",
                    label: trimmed,
                    type: inferredOptionType(from: trimmed),
                    description: nil,
                    aiSuggested: true
                )
            }
        }
        guard let array = raw as? [[String: Any]] else { return [] }
        return array.compactMap { item in
            let label = (item["label"] as? String ?? item["title"] as? String ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            guard !label.isEmpty else { return nil }
            let lower = label.lowercased()
            guard !lower.hasPrefix("vendor ") && !lower.hasPrefix("option ") else { return nil }
            let optionType = DecisionOptionType(rawValue: item["type"] as? String ?? "") ?? inferredOptionType(from: label)
            return DecisionOptionSnapshot(
                id: item["id"] as? String ?? UUID().uuidString,
                label: label,
                type: optionType,
                description: item["description"] as? String,
                aiSuggested: item["aiSuggested"] as? Bool ?? true
            )
        }
    }

    private static func parseCriteria(_ raw: Any) -> [CriterionDraft] {
        guard let array = raw as? [[String: Any]] else { return [] }
        return array.compactMap { item in
            let name = (item["name"] as? String ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            guard !name.isEmpty else { return nil }
            return CriterionDraft(
                id: item["id"] as? String ?? UUID().uuidString,
                name: name,
                detail: (item["detail"] as? String ?? "").trimmingCharacters(in: .whitespacesAndNewlines),
                category: (item["category"] as? String ?? "General").trimmingCharacters(in: .whitespacesAndNewlines),
                weightPercent: item["weightPercent"] as? Double ?? 0
            )
        }
    }

    private static func parseStringArray(_ raw: Any) -> [String] {
        guard let array = raw as? [Any] else { return [] }
        return array.compactMap { item -> String? in
            guard let text = item as? String else { return nil }
            let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed.isEmpty ? nil : trimmed
        }
    }

    private static func inferredOptionType(from label: String) -> DecisionOptionType {
        let lower = label.lowercased()
        if lower.contains("candidate") {
            return .candidate
        }
        if lower.contains("offer") || lower.contains("current job") || lower.contains("role") {
            return .offer
        }
        if lower.contains("school") || lower.contains("university") || lower.contains("college") {
            return .school
        }
        if lower.contains("vendor") || lower.contains("provider") {
            return .vendor
        }
        return .genericChoice
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
            return AISuggestedInputs(criteria: draft.criteria, draftScores: [], citations: [])
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
        return AISuggestedInputs(
            criteria: criteria,
            draftScores: scores,
            citations: parseEvidenceCitations(dictionary["citations"] as Any)
        )
    }
}
#endif

#if canImport(FirebaseFunctions)
final class FirebaseFunctionsExtractionService: FileExtractionServicing {
    private let functions: Functions
    private let fallback: FileExtractionServicing

    init(functions: Functions? = nil, fallback: FileExtractionServicing = LocalFileExtractionService()) {
        self.functions = functions ?? Functions.functions()
        self.fallback = fallback
    }

    func extractEvidence(for attachments: [VendorAttachment]) async throws -> [ExtractedAttachmentEvidence] {
        var results: [ExtractedAttachmentEvidence] = []

        for attachment in attachments {
            if isBackendOfficeAttachment(attachment), let backendResult = try await extractOfficeAttachment(attachment) {
                results.append(backendResult)
            } else {
                let fallbackResults = try await fallback.extractEvidence(for: [attachment])
                if let fallbackResult = fallbackResults.first {
                    results.append(fallbackResult)
                }
            }
        }

        return results
    }

    private func isBackendOfficeAttachment(_ attachment: VendorAttachment) -> Bool {
        let ext = URL(fileURLWithPath: attachment.fileName).pathExtension.lowercased()
        return ["docx", "xlsx", "xls", "numbers"].contains(ext)
    }

    private func extractOfficeAttachment(_ attachment: VendorAttachment) async throws -> ExtractedAttachmentEvidence? {
        let localURL = URL(fileURLWithPath: attachment.cloudPath)
        guard FileManager.default.fileExists(atPath: localURL.path) else {
            return nil
        }

        let fileData = try Data(contentsOf: localURL)
        let payload: [String: Any] = [
            "projectId": attachment.id,
            "uploadRefs": [[
                "attachmentId": attachment.id,
                "fileName": attachment.fileName,
                "contentType": attachment.contentType,
                "base64": fileData.base64EncodedString()
            ]]
        ]

        do {
            let raw = try await functions.httpsCallable("extractVendorFiles").call(payload)
            guard let dictionary = raw.data as? [String: Any],
                  let items = dictionary["items"] as? [[String: Any]],
                  let first = items.first else {
                return nil
            }
            return ExtractedAttachmentEvidence(
                attachmentID: first["attachmentId"] as? String ?? attachment.id,
                extractedText: first["extractedText"] as? String ?? "",
                status: AttachmentValidationStatus(rawValue: first["status"] as? String ?? "") ?? .needsReview,
                trustLevel: .uploaded,
                sourceHost: "",
                titleHint: first["titleHint"] as? String ?? attachment.fileName,
                validationMessage: first["validationMessage"] as? String ?? "Backend extraction completed."
            )
        } catch {
            let fallbackResults = try await fallback.extractEvidence(for: [attachment])
            return fallbackResults.first
        }
    }
}
#endif

struct SwiftDataPersistenceService: PersistenceServicing {
    func saveProjectDraft(_ draft: RankingDraft, ownerUserID: String, result: RankingResult?, insight: InsightReportDraft?, context: ModelContext) throws {
        if let existingProject = try fetchProjectEntity(id: draft.id, context: context) {
            context.delete(existingProject)
        }
        try deleteChildren(for: draft.id, context: context)

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
        let aiRecommendation = draft.decisionReport?.recommendation
            ?? result?.rankedVendors.first?.vendorName
            ?? insight?.winnerReasoning
            ?? ""
        let aiTradeOffs = insight?.summary ?? draft.decisionReport?.drivers.joined(separator: "\n") ?? ""
        let aiBlindSpots = insight?.riskFlags.joined(separator: "\n") ?? draft.decisionReport?.risks.joined(separator: "\n") ?? ""
        let aiGutCheck = insight?.winnerReasoning ?? draft.decisionReport?.recommendation ?? ""
        let aiNextStep = insight?.overlookedStrategicPoints.first ?? draft.decisionReport?.nextStep ?? ""

        let entity = RankingProjectEntity(
            id: draft.id,
            ownerUserID: ownerUserID,
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
            aiTradeOffs: aiTradeOffs,
            aiBlindSpots: aiBlindSpots,
            aiGutCheck: aiGutCheck,
            aiNextStep: aiNextStep,
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
            predicate: #Predicate<RankingProjectEntity> { project in
                project.ownerUserID == ownerUserID
            },
            sortBy: [SortDescriptor(\RankingProjectEntity.updatedAt, order: .reverse)]
        )
        return try context.fetch(descriptor)
    }

    func loadProjectDraft(for projectID: String, context: ModelContext) throws -> RankingDraft? {
        let descriptor = FetchDescriptor<ProjectVersionEntity>(
            predicate: #Predicate<ProjectVersionEntity> { version in
                version.projectID == projectID
            },
            sortBy: [SortDescriptor(\ProjectVersionEntity.createdAt, order: .reverse)]
        )
        guard let latestVersion = try context.fetch(descriptor).first else {
            return nil
        }
        return try JSONDecoder().decode(RankingDraft.self, from: Data(latestVersion.snapshotJSON.utf8))
    }

    func saveProfile(_ profile: UserProfileEntity, context: ModelContext) throws {
        if let existingProfile = try loadProfile(for: profile.id, context: context) {
            context.delete(existingProfile)
        }
        context.insert(profile)
        try context.save()
    }

    func loadProfile(for userID: String, context: ModelContext) throws -> UserProfileEntity? {
        let descriptor = FetchDescriptor<UserProfileEntity>(
            predicate: #Predicate<UserProfileEntity> { profile in
                profile.id == userID
            }
        )
        return try context.fetch(descriptor).first
    }

    private func fetchProjectEntity(id: String, context: ModelContext) throws -> RankingProjectEntity? {
        let descriptor = FetchDescriptor<RankingProjectEntity>(
            predicate: #Predicate<RankingProjectEntity> { project in
                project.id == id
            }
        )
        return try context.fetch(descriptor).first
    }

    private func deleteChildren(for projectID: String, context: ModelContext) throws {
        try context.fetch(
            FetchDescriptor<VendorEntity>(
                predicate: #Predicate<VendorEntity> { vendor in
                    vendor.projectID == projectID
                }
            )
        ).forEach(context.delete)

        try context.fetch(
            FetchDescriptor<CriterionEntity>(
                predicate: #Predicate<CriterionEntity> { criterion in
                    criterion.projectID == projectID
                }
            )
        ).forEach(context.delete)

        try context.fetch(
            FetchDescriptor<ScoreEntryEntity>(
                predicate: #Predicate<ScoreEntryEntity> { score in
                    score.projectID == projectID
                }
            )
        ).forEach(context.delete)

        try context.fetch(
            FetchDescriptor<ProjectVersionEntity>(
                predicate: #Predicate<ProjectVersionEntity> { version in
                    version.projectID == projectID
                }
            )
        ).forEach(context.delete)
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
        if ["txt", "md", "json", "xml", "html", "htm"].contains(ext) {
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
        if ["csv", "tsv"].contains(ext) {
            return extractDelimitedText(from: fileURL, fileName: attachment.fileName, attachmentID: attachment.id, delimiter: ext == "tsv" ? "\t" : ",")
        }
        if ["png", "jpg", "jpeg", "heic", "heif", "tif", "tiff", "bmp"].contains(ext) {
            return try await extractImageText(from: fileURL, fileName: attachment.fileName, attachmentID: attachment.id)
        }
        if ["docx", "xlsx", "xls", "numbers"].contains(ext) {
            return ExtractedAttachmentEvidence(
                attachmentID: attachment.id,
                extractedText: "",
                status: .needsReview,
                trustLevel: .uploaded,
                sourceHost: "",
                titleHint: attachment.fileName,
                validationMessage: "This Office document needs backend extraction."
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

    private func extractDelimitedText(from url: URL, fileName: String, attachmentID: String, delimiter: Character) -> ExtractedAttachmentEvidence {
        let raw = (try? String(contentsOf: url, encoding: .utf8))
            ?? (try? String(contentsOf: url, encoding: .unicode))
            ?? (try? String(contentsOf: url, encoding: .ascii))
            ?? ""
        let rows = raw
            .replacingOccurrences(of: "\r", with: "\n")
            .split(separator: "\n")
            .prefix(40)
            .map { row -> String in
                row
                    .split(separator: delimiter)
                    .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                    .filter { !$0.isEmpty }
                    .joined(separator: " | ")
            }
            .filter { !$0.isEmpty }
        let cleaned = rows.joined(separator: "\n")
        return ExtractedAttachmentEvidence(
            attachmentID: attachmentID,
            extractedText: formattedEvidence(title: fileName, body: cleaned),
            status: cleaned.isEmpty ? .needsReview : .ready,
            trustLevel: .uploaded,
            sourceHost: "",
            titleHint: fileName,
            validationMessage: cleaned.isEmpty ? "Spreadsheet loaded, but no readable rows were extracted." : "Spreadsheet rows parsed."
        )
    }

    private func extractImageText(from url: URL, fileName: String, attachmentID: String) async throws -> ExtractedAttachmentEvidence {
        #if canImport(Vision) && canImport(ImageIO)
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              let cgImage = CGImageSourceCreateImageAtIndex(source, 0, nil) else {
            return ExtractedAttachmentEvidence(
                attachmentID: attachmentID,
                extractedText: "",
                status: .unreadable,
                trustLevel: .uploaded,
                sourceHost: "",
                titleHint: fileName,
                validationMessage: "The image could not be opened for OCR."
            )
        }

        let text = try await recognizeText(in: cgImage)
        let cleaned = sanitizedText(text)
        return ExtractedAttachmentEvidence(
            attachmentID: attachmentID,
            extractedText: formattedEvidence(title: fileName, body: cleaned),
            status: cleaned.isEmpty ? .needsReview : .ready,
            trustLevel: .uploaded,
            sourceHost: "",
            titleHint: fileName,
            validationMessage: cleaned.isEmpty ? "Image loaded, but OCR found no readable text." : "Image OCR completed."
        )
        #else
        return ExtractedAttachmentEvidence(
            attachmentID: attachmentID,
            extractedText: "",
            status: .needsReview,
            trustLevel: .uploaded,
            sourceHost: "",
            titleHint: fileName,
            validationMessage: "OCR is unavailable in this build."
        )
        #endif
    }

    #if canImport(Vision) && canImport(ImageIO)
    private func recognizeText(in cgImage: CGImage) async throws -> String {
        try await withCheckedThrowingContinuation { continuation in
            let request = VNRecognizeTextRequest { request, error in
                if let error {
                    continuation.resume(throwing: error)
                    return
                }

                let observations = (request.results as? [VNRecognizedTextObservation]) ?? []
                let text = observations
                    .compactMap { $0.topCandidates(1).first?.string }
                    .joined(separator: "\n")
                continuation.resume(returning: text)
            }
            request.recognitionLevel = .accurate
            request.usesLanguageCorrection = true

            let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])
            do {
                try handler.perform([request])
            } catch {
                continuation.resume(throwing: error)
            }
        }
    }
    #endif

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

struct LocalNotificationService: NotificationServicing {
    func requestAuthorizationIfNeeded() async -> Bool {
        #if canImport(UserNotifications)
        return await withCheckedContinuation { continuation in
            let center = UNUserNotificationCenter.current()
            center.getNotificationSettings { settings in
                switch settings.authorizationStatus {
                case .authorized, .provisional, .ephemeral:
                    continuation.resume(returning: true)
                case .denied:
                    continuation.resume(returning: false)
                case .notDetermined:
                    center.requestAuthorization(options: [.alert, .badge, .sound]) { granted, _ in
                        continuation.resume(returning: granted)
                    }
                @unknown default:
                    continuation.resume(returning: false)
                }
            }
        }
        #else
        return false
        #endif
    }

    func scheduleFollowUp(for draft: RankingDraft, result: RankingResult?) async throws {
        #if canImport(UserNotifications)
        guard let followUpDate = draft.followUpDate else { return }
        guard await requestAuthorizationIfNeeded() else {
            throw ScoreWiseServiceError.featureUnavailable("Notifications are disabled for Clarity AI. Enable them in Settings to schedule follow-up reviews.")
        }

        let content = UNMutableNotificationContent()
        content.title = "Review your decision"
        if let winner = result?.rankedVendors.first?.vendorName, !winner.isEmpty {
            content.body = "Revisit \"\(draft.title)\" and see whether choosing \(winner) still holds up after 30 days."
        } else {
            content.body = "Revisit \"\(draft.title)\" and record what happened after 30 days."
        }
        content.sound = .default

        let triggerDate = max(followUpDate, Date().addingTimeInterval(5))
        let components = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute], from: triggerDate)
        let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: false)
        let request = UNNotificationRequest(identifier: notificationIdentifier(projectID: draft.id), content: content, trigger: trigger)
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: [notificationIdentifier(projectID: draft.id)])
        try await UNUserNotificationCenter.current().add(request)
        #endif
    }

    func cancelFollowUp(for projectID: String) async {
        #if canImport(UserNotifications)
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: [notificationIdentifier(projectID: projectID)])
        #endif
    }

    func cancelAllFollowUps() async {
        #if canImport(UserNotifications)
        UNUserNotificationCenter.current().removeAllPendingNotificationRequests()
        #endif
    }

    private func notificationIdentifier(projectID: String) -> String {
        "followup.\(projectID)"
    }
}

enum PromptEngineering {
    static func recommendedCriteria(from contextBlob: String, context: UsageContext, profile: AIUserProfile?, optionCount: Int) -> [CriterionDraft] {
        var candidates: [CriterionDraft] = []
        let looksLikeVendorComparison = contextBlob.contains("vendor")
            || contextBlob.contains("provider")
            || contextBlob.contains("agency")
            || contextBlob.contains("service")
            || contextBlob.contains("proposal")
            || contextBlob.contains("quote")

        func addCandidate(name: String, detail: String, category: String, weight: Double) {
            if candidates.contains(where: { $0.name.caseInsensitiveCompare(name) == .orderedSame }) {
                return
            }
            candidates.append(CriterionDraft(name: name, detail: detail, category: category, weightPercent: weight))
        }

        if looksLikeVendorComparison || context == .work {
            addCandidate(name: "Capability Fit", detail: "How well the option covers the actual scope, quality bar, and expected outcomes", category: "Performance", weight: 24)
            addCandidate(name: "Commercial Value", detail: "Price, total cost, and whether the value justifies the commitment", category: "Financial", weight: 18)
            addCandidate(name: "Execution Reliability", detail: "How likely this option is to deliver without avoidable delays, rework, or service gaps", category: "Execution", weight: 20)
            addCandidate(name: "Support & Responsiveness", detail: "Responsiveness, communication quality, and how issues will be handled", category: "Operations", weight: 18)
            addCandidate(name: "Strategic Fit", detail: "How well this option supports the broader objective behind the decision", category: "Strategy", weight: 20)
        } else {
            addCandidate(name: "Outcome Quality", detail: "Expected quality, reliability, and success of the result", category: "Performance", weight: 22)
            addCandidate(name: "Risk & Reversibility", detail: "Downside risk and how hard the choice is to unwind later", category: "Risk", weight: 20)
            addCandidate(name: "Time-to-Value", detail: "How quickly this option creates useful progress", category: "Execution", weight: 18)
            addCandidate(name: "Effort & Complexity", detail: "Implementation load, coordination cost, and ongoing friction", category: "Execution", weight: 16)
            addCandidate(name: "Strategic Fit", detail: "How well the option supports the broader goal behind this decision", category: "Strategy", weight: 24)
        }

        if contextBlob.contains("cost") || contextBlob.contains("budget") || contextBlob.contains("salary") || contextBlob.contains("price") {
            addCandidate(name: "Cost & Financial Impact", detail: "All-in cost, savings, or financial upside over the decision horizon", category: "Financial", weight: 24)
        }
        if contextBlob.contains("security") || contextBlob.contains("compliance") || contextBlob.contains("legal") {
            addCandidate(name: "Security & Compliance", detail: "Regulatory, legal, and security exposure", category: "Risk", weight: 21)
        }
        if contextBlob.contains("integration") || contextBlob.contains("api") || contextBlob.contains("migration") || contextBlob.contains("stack") {
            addCandidate(name: "Integration Fit", detail: "Compatibility with existing systems and switching cost", category: "Technical", weight: 18)
        }
        if contextBlob.contains("support") || contextBlob.contains("team") || contextBlob.contains("vendor") || contextBlob.contains("partner") {
            addCandidate(name: "Support & Responsiveness", detail: "How well this option is supported when problems appear", category: "Operations", weight: 16)
        }
        if contextBlob.contains("growth") || contextBlob.contains("learning") || contextBlob.contains("promotion") || contextBlob.contains("future") {
            addCandidate(name: "Growth Potential", detail: "Longer-term upside, learning, and room to expand", category: "Strategy", weight: 18)
        }
        if contextBlob.contains("culture") || contextBlob.contains("values") || contextBlob.contains("alignment") {
            addCandidate(name: "Values Alignment", detail: "Fit with the values and working style that matter most here", category: "Personal", weight: 18)
        }
        if context == .education {
            addCandidate(name: "Learning Curve", detail: "Ease of adoption and training burden", category: "Adoption", weight: 16)
        }
        if optionCount >= 4 {
            addCandidate(name: "Differentiation", detail: "How clearly this option stands apart from the alternatives", category: "Strategy", weight: 12)
        }

        if let topValue = profile?.valuesRanking.first?.lowercased(), !topValue.isEmpty {
            if topValue.contains("security") || topValue.contains("stability") {
                addCandidate(name: "Stability", detail: "Predictability, downside protection, and resilience under pressure", category: "Risk", weight: 18)
            } else if topValue.contains("growth") || topValue.contains("learning") {
                addCandidate(name: "Learning & Upside", detail: "Growth, learning, and long-term optionality", category: "Strategy", weight: 18)
            } else if topValue.contains("freedom") || topValue.contains("independence") {
                addCandidate(name: "Autonomy", detail: "Control, flexibility, and ability to make future moves", category: "Personal", weight: 17)
            } else if topValue.contains("relationship") || topValue.contains("connection") {
                addCandidate(name: "Stakeholder Impact", detail: "Effect on trust, collaboration, and key relationships", category: "People", weight: 17)
            }
        }

        return Array(RankingEngine.normalizedCriteria(Array(candidates.prefix(8))).prefix(8))
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
            guard let filePath = Bundle.main.path(forResource: "GoogleService-Info", ofType: "plist"),
                  let options = FirebaseOptions(contentsOfFile: filePath),
                  !containsPlaceholderCredentials(options) else {
                return
            }
            FirebaseApp.configure(options: options)
        }
        #endif
    }

    #if canImport(FirebaseCore)
    private static func containsPlaceholderCredentials(_ options: FirebaseOptions) -> Bool {
        let values = [
            options.googleAppID,
            options.clientID,
            options.apiKey,
            options.projectID,
            options.storageBucket
        ]
        return values.contains { value in
            let normalized = value?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() ?? ""
            return normalized.isEmpty || normalized.contains("replace_with") || normalized.contains("your_")
        }
    }
    #endif
}

struct AppServices {
    let auth: AuthServicing
    let ai: AIservicing
    let persistence: PersistenceServicing
    let extractor: FileExtractionServicing
    let pdf: PDFExportServicing
    let notifications: NotificationServicing

    static var live: AppServices {
        FirebaseBootstrap.configureIfPossible()
        #if canImport(FirebaseCore)
        let firebaseConfigured = FirebaseApp.app() != nil
        #else
        let firebaseConfigured = false
        #endif
        let aiService: AIservicing = {
            let allowDirect = ProcessInfo.processInfo.environment["SCOREWISE_ALLOW_DIRECT_AI_DEBUG"] == "1"
            let allowLocalFallback = ProcessInfo.processInfo.environment["SCOREWISE_ENABLE_LOCAL_AI_FALLBACK"] == "1"
            if allowDirect, let apiKey = ProcessInfo.processInfo.environment["ANTHROPIC_API_KEY"], !apiKey.isEmpty {
                return AnthropicAIService(apiKey: apiKey)
            }
            #if canImport(FirebaseFunctions) && canImport(FirebaseCore)
            if firebaseConfigured {
                return FirebaseFunctionsAIService(
                    fallback: LocalMockAIService(),
                    allowLocalFallback: allowLocalFallback
                )
            }
            if allowLocalFallback {
                return LocalMockAIService()
            }
            return UnavailableAIService(reason: "Cloud AI is not configured. Check Firebase setup and retry.")
            #else
            if allowLocalFallback {
                return LocalMockAIService()
            }
            return UnavailableAIService(reason: "Cloud AI is unavailable in this build configuration.")
            #endif
        }()
        let extractorService: FileExtractionServicing = {
            #if canImport(FirebaseFunctions) && canImport(FirebaseCore)
            if firebaseConfigured {
                return FirebaseFunctionsExtractionService(fallback: LocalFileExtractionService())
            }
            return LocalFileExtractionService()
            #else
            return LocalFileExtractionService()
            #endif
        }()
        return AppServices(
            auth: FirebaseEmailAuthService(),
            ai: aiService,
            persistence: SwiftDataPersistenceService(),
            extractor: extractorService,
            pdf: PDFExportService(),
            notifications: LocalNotificationService()
        )
    }
}

private extension String {
    var nonEmpty: String? {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}

private extension Array where Element: Hashable {
    func uniqued() -> [Element] {
        var seen: Set<Element> = []
        return filter { seen.insert($0).inserted }
    }
}
