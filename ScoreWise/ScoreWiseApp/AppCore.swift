import Foundation
import SwiftUI
import SwiftData

struct ChatMessageDraft: Identifiable, Hashable {
    var id: String = UUID().uuidString
    var role: String
    var content: String
    var timestamp: Date = .now
}

@MainActor
final class AppViewModel: ObservableObject {
    private enum LocalSessionKeys {
        static let guestUserID = "clarity.guest.user_id"
    }

    enum Screen {
        case launch
        case auth
        case onboarding
        case postSurveySplash
        case home
        case history
        case decisionChat
        case ranking
        case results
        case profile
    }

    enum RankingEntryMode: Equatable {
        case manual
        case chatReady
        case postAnalysisChallenge
    }

    enum AnalysisSource: String {
        case cloud
        case localFallback = "local_fallback"
        case unavailable
    }

    struct MatrixQualityFlags: Equatable {
        var allZeroScores = false
        var incompleteScores = false
        var lowVarianceCriteria: [String] = []

        var hasWarnings: Bool {
            allZeroScores || incompleteScores || !lowVarianceCriteria.isEmpty
        }
    }

    @Published var screen: Screen = .launch
    @Published var session: AuthSession?
    @Published var onboardingAnswers: [SurveyAnswer] = []
    @Published var activeDraft: RankingDraft = .empty
    @Published var activeResult: RankingResult?
    @Published var activeInsight: InsightReportDraft?
    @Published var recentProjects: [RankingProjectEntity] = []
    @Published var chatMessages: [ChatMessageDraft] = []
    @Published var decisionChatMessages: [DecisionChatMessage] = []
    @Published var decisionChatPhase: ChatConversationPhase = .opening
    @Published var isChatTyping = false
    @Published var pendingFreeformReply = ""
    @Published var aiModeLabel: String?
    @Published var matrixSetupReady = false
    @Published var rankingEntryMode: RankingEntryMode = .manual
    @Published var busyMessage: String?
    @Published var lastError: String?
    @Published var userValuesRanking: [String] = []
    @Published var userInterests: [String] = []
    @Published var expressModeEnabled = false
    @Published var aiSuggestionSummary: String?
    @Published var isApplyingAISuggestions = false
    @Published var optionsValidationMessage: String?
    @Published var analysisSource: AnalysisSource = .localFallback
    @Published var analysisStatusMessage: String?
    @Published var matrixQualityFlags = MatrixQualityFlags()
    @Published var isRefreshingInsights = false
    @Published var isGeneratingMatrix = false
    @Published var isGeneratingReassurance = false

    let decisionFlowV2Enabled = true

    let services: AppServices

    var expressModeAvailable: Bool {
        guard let profile = userAIProfile else { return false }
        return profile.speedPreference == SpeedPreference.quick.rawValue || profile.biggestChallenge == BiggestChallenge.overthinking.rawValue
    }

    private var userAIProfile: AIUserProfile? {
        let answerMap = Dictionary(uniqueKeysWithValues: onboardingAnswers.map { ($0.questionID, $0.value.lowercased()) })
        return AIUserProfile(
            primaryUsage: activeDraft.usageContext.rawValue,
            decisionStyle: decisionStyle(from: answerMap).rawValue,
            biggestChallenge: biggestChallenge(from: answerMap).rawValue,
            speedPreference: speedPreference(from: answerMap).rawValue,
            valuesRanking: userValuesRanking,
            interests: userInterests
        )
    }

    private var localAIFallbackEnabled: Bool {
        ProcessInfo.processInfo.environment["SCOREWISE_ENABLE_LOCAL_AI_FALLBACK"] == "1"
    }

    init(services: AppServices = .live) {
        self.services = services
    }

    func bootstrap(modelContext: ModelContext) {
        Task {
            session = await services.auth.restoreSession()
            if session == nil, let guestID = UserDefaults.standard.string(forKey: LocalSessionKeys.guestUserID), guestID.trimmed.isNotEmpty {
                session = AuthSession(
                    userID: guestID,
                    email: "guest@local",
                    displayName: "Guest",
                    providers: ["guest"]
                )
            }
            if session != nil {
                restorePersistedSessionState(modelContext: modelContext)
            } else {
                screen = .auth
            }
        }
    }

    func signInWithApple() {
        Task {
            await signIn { [self] in
                try await self.services.auth.signInWithApple()
            }
        }
    }

    func signInWithGoogle() {
        Task {
            await signIn { [self] in
                try await self.services.auth.signInWithGoogle()
            }
        }
    }

    func signInEmail(email: String, password: String) {
        Task {
            await signIn { [self] in
                try await self.services.auth.signInWithEmail(email: email, password: password)
            }
        }
    }

    func createAccount(email: String, password: String, fullName: String) {
        Task {
            await signIn { [self] in
                try await self.services.auth.createAccount(email: email, password: password, fullName: fullName)
            }
        }
    }

    func continueAsGuest() {
        busyMessage = nil
        let existingGuestID = UserDefaults.standard.string(forKey: LocalSessionKeys.guestUserID)?.trimmed
        let guestID = (existingGuestID?.isNotEmpty == true) ? (existingGuestID ?? "") : "guest-\(UUID().uuidString)"
        UserDefaults.standard.set(guestID, forKey: LocalSessionKeys.guestUserID)
        session = AuthSession(
            userID: guestID,
            email: "guest@local",
            displayName: "Guest",
            providers: ["guest"]
        )
        screen = .launch
    }

    private func signIn(_ work: @escaping () async throws -> AuthSession) async {
        do {
            busyMessage = "Signing in..."
            session = try await work()
            UserDefaults.standard.removeObject(forKey: LocalSessionKeys.guestUserID)
            busyMessage = nil
            screen = .launch
        } catch {
            busyMessage = nil
            lastError = error.localizedDescription
        }
    }

    func completeOnboarding(context: UsageContext, answers: [SurveyAnswer], valuesRanking: [String], interests: [String], modelContext: ModelContext) {
        guard let session else { return }
        onboardingAnswers = answers
        userValuesRanking = valuesRanking
        userInterests = interests

        let tags = SurveyTagger.deriveTags(from: answers)
        let answerMap = Dictionary(uniqueKeysWithValues: answers.map { ($0.questionID, $0.value.lowercased()) })
        let answerJSON = (try? JSONEncoder().encode(answers)).flatMap { String(data: $0, encoding: .utf8) } ?? "[]"
        let valuesJSON = (try? JSONEncoder().encode(valuesRanking)).flatMap { String(data: $0, encoding: .utf8) } ?? "[]"
        let interestsJSON = (try? JSONEncoder().encode(interests)).flatMap { String(data: $0, encoding: .utf8) } ?? "[]"
        let nameParts = session.displayName.split(separator: " ").map(String.init)
        let firstName = nameParts.first ?? ""
        let lastName = nameParts.dropFirst().joined(separator: " ")
        let profile = UserProfileEntity(
            id: session.userID,
            email: session.email,
            displayName: session.displayName,
            authProvidersCSV: session.providers.joined(separator: ","),
            usageContextRaw: context.rawValue,
            surveyAnswersJSON: answerJSON,
            decisionStyleTagsCSV: tags.joined(separator: ","),
            firstName: firstName,
            lastName: lastName,
            primaryUsageRaw: context.rawValue,
            decisionStyleRaw: decisionStyle(from: answerMap).rawValue,
            biggestChallengeRaw: biggestChallenge(from: answerMap).rawValue,
            speedPreferenceRaw: speedPreference(from: answerMap).rawValue,
            valuesRankingJSON: valuesJSON,
            interestsJSON: interestsJSON,
            appearanceRaw: AppearancePreference.auto.rawValue,
            notificationsEnabled: true,
            followUpReminders: answerMap["review"] == "often"
        )
        do {
            try services.persistence.saveProfile(profile, context: modelContext)
            expressModeEnabled = speedPreference(from: answerMap) == .quick && biggestChallenge(from: answerMap) == .overthinking
            screen = .postSurveySplash
        } catch {
            lastError = error.localizedDescription
        }
    }

    private func decisionStyle(from answers: [String: String]) -> DecisionStyle {
        let evidence = answers["evidence"] ?? ""
        let collaboration = answers["collaboration"] ?? ""
        if evidence == "high" || collaboration == "executive" {
            return .analytical
        }
        if evidence == "low" {
            return .intuitive
        }
        return .balanced
    }

    private func biggestChallenge(from answers: [String: String]) -> BiggestChallenge {
        let risk = answers["risk"] ?? ""
        let pace = answers["pace"] ?? ""
        if risk.contains("averse") {
            return .fear
        }
        if pace.contains("careful") {
            return .overthinking
        }
        if pace.contains("fast") {
            return .lackOfInfo
        }
        return .tooManyOptions
    }

    private func speedPreference(from answers: [String: String]) -> SpeedPreference {
        let pace = answers["pace"] ?? ""
        if pace.contains("fast") {
            return .quick
        }
        if pace.contains("careful") {
            return .deep
        }
        return .depends
    }

    func continueFromPostSurveySplash() {
        withAnimation(.spring(response: 0.45, dampingFraction: 0.86)) {
            screen = .home
        }
    }

    func decisionEntryWarning(for narrative: String) -> String? {
        LocalDecisionIntelligence.contextWarning(for: narrative)
    }

    func optionScopeValidation() -> OptionScopeValidation {
        DecisionEngine.shared.validateOptionScope(draft: activeDraft, userProfile: userAIProfile)
    }

    enum MatrixPreparationRoute {
        case options
        case clarify
        case weigh
    }

    func startNewComparison() {
        activeDraft = .empty
        activeResult = nil
        activeInsight = nil
        aiSuggestionSummary = nil
        optionsValidationMessage = nil
        matrixQualityFlags = MatrixQualityFlags()
        analysisSource = .localFallback
        analysisStatusMessage = nil
        isRefreshingInsights = false
        isGeneratingMatrix = false
        isGeneratingReassurance = false
        chatMessages.removeAll()
        rankingEntryMode = .manual
        screen = .ranking
    }

    func beginDecisionConversation(from narrative: String) {
        let trimmed = narrative.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        activeDraft = .empty
        activeResult = nil
        activeInsight = nil
        aiSuggestionSummary = nil
        chatMessages.removeAll()
        matrixQualityFlags = MatrixQualityFlags()
        analysisSource = .localFallback
        analysisStatusMessage = nil
        isRefreshingInsights = false
        isGeneratingMatrix = false
        isGeneratingReassurance = false
        decisionChatMessages = []
        decisionChatPhase = .collecting
        isChatTyping = false
        pendingFreeformReply = ""
        aiModeLabel = "Clarity AI"
        matrixSetupReady = false
        rankingEntryMode = .manual
        optionsValidationMessage = nil

        activeDraft.contextNarrative = trimmed
        activeDraft.title = truncatedTitle(from: trimmed, maxLength: 56)
        activeDraft.chatPhase = .collecting
        activeDraft.frameworksUsed = []
        activeDraft.postChallengeReassurance = nil
        activeDraft.constraintFindings = []
        activeDraft.decisionReport = nil
        activeDraft.unifiedContext = nil
        activeDraft.followUpCheckpoints = []
        activeDraft.followUpDeltaGuidance = nil

        decisionChatMessages.append(
            DecisionChatMessage(
                role: .assistant,
                content: "I’m analyzing your situation and will ask targeted decision questions.",
                options: [],
                allowSkip: false,
                allowsFreeformReply: false,
                cta: nil,
                framework: nil,
                createdAt: .now,
                isTypingPlaceholder: false
            )
        )

        decisionChatMessages.append(
            DecisionChatMessage(
                role: .user,
                content: trimmed,
                options: [],
                allowSkip: false,
                allowsFreeformReply: false,
                cta: nil,
                framework: nil,
                createdAt: .now,
                isTypingPlaceholder: false
            )
        )

        rebuildDecisionConversationSummary()
        refreshUnifiedDecisionContext()
        screen = .decisionChat
        requestStartDecisionConversation()
    }

    func sendFreeformChatReply() {
        let trimmed = pendingFreeformReply.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        pendingFreeformReply = ""
        decisionChatMessages.append(
            DecisionChatMessage(
                role: .user,
                content: trimmed,
                options: [],
                allowSkip: false,
                allowsFreeformReply: false,
                cta: nil,
                framework: nil,
                createdAt: .now,
                isTypingPlaceholder: false
            )
        )

        rebuildDecisionConversationSummary()
        refreshUnifiedDecisionContext()
        requestContinueDecisionConversation(latestUserResponse: trimmed, selectedOptionIndex: nil)
    }

    func selectChatOption(_ option: DecisionChatOption) {
        decisionChatMessages.append(
            DecisionChatMessage(
                role: .user,
                content: option.text,
                options: [],
                allowSkip: false,
                allowsFreeformReply: false,
                cta: nil,
                framework: nil,
                createdAt: .now,
                isTypingPlaceholder: false
            )
        )

        rebuildDecisionConversationSummary()
        refreshUnifiedDecisionContext()
        requestContinueDecisionConversation(latestUserResponse: option.text, selectedOptionIndex: option.index)
    }

    func skipChatQuestion() {
        decisionChatMessages.append(
            DecisionChatMessage(
                role: .user,
                content: "Skip",
                options: [],
                allowSkip: false,
                allowsFreeformReply: false,
                cta: nil,
                framework: nil,
                createdAt: .now,
                isTypingPlaceholder: false
            )
        )
        rebuildDecisionConversationSummary()
        refreshUnifiedDecisionContext()
        requestContinueDecisionConversation(latestUserResponse: "Skip", selectedOptionIndex: nil)
    }

    func completeChatAndPrepareMatrix() {
        Task {
            do {
                busyMessage = "Preparing weighted scoring setup..."
                refreshUnifiedDecisionContext()
                let setup = try await services.ai.finalizeConversationForMatrix(
                    projectID: activeDraft.id,
                    transcript: decisionChatMessages.filter { !$0.isTypingPlaceholder },
                    draft: activeDraft,
                    userProfile: userAIProfile
                )
                applyMatrixSetupFromConversation(setup)
                decisionChatPhase = .completed
                activeDraft.chatPhase = .completed
                activeDraft.chatCompletedAt = .now
                optionsValidationMessage = nil
                rebuildDecisionConversationSummary()
                activeDraft.constraintFindings = DecisionEngine.shared.detectConstraints(draft: activeDraft)
                rankingEntryMode = .chatReady
                trackFlowEvent("flow_entry_mode", details: "chatReady")
                matrixSetupReady = true
                aiModeLabel = "Clarity AI"
                busyMessage = nil
                screen = .ranking
            } catch {
                busyMessage = nil
                aiModeLabel = "AI unavailable"
                lastError = "Could not finalize matrix setup from Clarity AI. Please retry."
                appendConversationFailureMessage("I couldn’t finalize your matrix setup from Clarity AI. Please retry.")
            }
        }
    }

    func restorePersistedSessionState(modelContext: ModelContext) {
        guard let session else {
            screen = .auth
            return
        }

        do {
            recentProjects = try services.persistence.loadProjects(for: session.userID, context: modelContext)

            if let profile = try services.persistence.loadProfile(for: session.userID, context: modelContext) {
                hydrateOnboardingState(from: profile)
                if screen == .launch || screen == .auth || screen == .onboarding {
                    screen = .home
                }
            } else if screen == .launch || screen == .auth {
                screen = .onboarding
            }
        } catch {
            lastError = error.localizedDescription
            if screen == .launch {
                screen = .onboarding
            }
        }
    }

    func resumeDecision(_ project: RankingProjectEntity, modelContext: ModelContext) {
        do {
            guard let draft = try services.persistence.loadProjectDraft(for: project.id, context: modelContext) else {
                screen = .history
                return
            }

            activeDraft = draft
            activeResult = draft.criteria.isEmpty || draft.scores.isEmpty ? nil : RankingEngine.computeResult(for: draft)
            activeInsight = InsightReportDraft(
                summary: project.aiTradeOffs,
                winnerReasoning: project.aiGutCheck,
                riskFlags: project.aiBlindSpots.split(separator: "\n").map(String.init).filter { !$0.isEmpty },
                overlookedStrategicPoints: project.aiNextStep.isEmpty ? [] : [project.aiNextStep],
                sensitivityFindings: []
            )
            matrixQualityFlags = MatrixQualityFlags()
            analysisSource = .localFallback
            analysisStatusMessage = nil
            matrixSetupReady = draft.chatPhase == .completed
            rankingEntryMode = .manual
            optionsValidationMessage = nil

            if draft.chatPhase == .collecting || draft.chatPhase == .transitionReady {
                screen = .decisionChat
            } else if draft.decisionStatus == .inProgress {
                screen = .ranking
            } else {
                screen = .results
            }
        } catch {
            lastError = error.localizedDescription
        }
    }

    func setExpressMode(_ enabled: Bool) {
        expressModeEnabled = enabled && expressModeAvailable
    }

    func addVendorOption(name: String = "", notes: String = "") -> String? {
        guard activeDraft.vendors.count < 8 else { return nil }
        let option = VendorDraft(name: name, notes: notes, attachments: [])
        activeDraft.vendors.append(option)
        optionsValidationMessage = nil
        activeDraft.lastUpdatedAt = .now
        refreshUnifiedDecisionContext()
        return option.id
    }

    func updateVendorOption(id: String, name: String, notes: String) {
        guard let index = activeDraft.vendors.firstIndex(where: { $0.id == id }) else { return }
        activeDraft.vendors[index].name = name
        activeDraft.vendors[index].notes = notes
        optionsValidationMessage = nil
        activeDraft.lastUpdatedAt = .now
        refreshUnifiedDecisionContext()
    }

    func vendorOption(id: String) -> VendorDraft? {
        activeDraft.vendors.first(where: { $0.id == id })
    }

    func removeVendorOption(id: String) {
        guard activeDraft.vendors.count > 2 else { return }
        activeDraft.vendors.removeAll { $0.id == id }
        activeDraft.scores.removeAll { $0.vendorID == id }
        if activeDraft.chosenOptionID == id {
            activeDraft.chosenOptionID = nil
        }
        activeResult = nil
        activeInsight = nil
        optionsValidationMessage = nil
        activeDraft.lastUpdatedAt = .now
        refreshUnifiedDecisionContext()
    }

    func prepareClarifyingQuestions() {
        guard !activeDraft.contextNarrative.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }

        Task {
            do {
                busyMessage = "Preparing clarifying questions..."
                refreshUnifiedDecisionContext()
                let allAttachments = activeDraft.contextAttachments + activeDraft.vendors.flatMap(\.attachments)
                let extractedEvidence = try await services.extractor.extractEvidence(for: allAttachments)
                applyEvidenceMetadata(extractedEvidence)
                try await refreshDecisionBrief(extractedEvidence: extractedEvidence.map(\.extractedText).filter { !$0.isEmpty })
                if activeDraft.clarifyingQuestions.count >= 6,
                   activeDraft.clarifyingQuestions.allSatisfy({ !$0.question.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }) {
                    busyMessage = nil
                    return
                }
                let remoteQuestions = try await services.ai.generateClarifyingQuestions(for: activeDraft, userProfile: userAIProfile)
                let normalizedRemote = remoteQuestions
                    .map { ClarifyingQuestionAnswer(question: $0.question.trimmed, answer: $0.answer) }
                    .filter { $0.question.isNotEmpty }
                let selected: [ClarifyingQuestionAnswer]
                if normalizedRemote.count >= 6 || !localAIFallbackEnabled {
                    selected = normalizedRemote
                } else {
                    selected = DecisionEngine.shared.generateClarifyingQuestions(draft: activeDraft, userProfile: userAIProfile)
                }
                activeDraft.clarifyingQuestions = Array(selected.prefix(12))
                busyMessage = nil
            } catch {
                busyMessage = nil
                if localAIFallbackEnabled {
                    activeDraft.clarifyingQuestions = Array(DecisionEngine.shared.generateClarifyingQuestions(draft: activeDraft, userProfile: userAIProfile).prefix(12))
                } else {
                    lastError = "Could not load clarifying questions from Clarity AI. Please retry."
                }
            }
        }
    }

    func updateClarifyingAnswer(questionID: String, answer: String) {
        guard let index = activeDraft.clarifyingQuestions.firstIndex(where: { $0.id == questionID }) else { return }
        activeDraft.clarifyingQuestions[index].answer = answer
        activeDraft.lastUpdatedAt = .now
        refreshUnifiedDecisionContext()
    }

    func regenerateClarifyingQuestion(questionID: String) {
        guard let index = activeDraft.clarifyingQuestions.firstIndex(where: { $0.id == questionID }) else { return }
        let rejected = activeDraft.clarifyingQuestions[index].question.trimmed
        let existing = Set(activeDraft.clarifyingQuestions.map { $0.question.trimmed.lowercased() })

        Task {
            busyMessage = "Refreshing question..."
            defer { busyMessage = nil }
            do {
                let remote = try await services.ai.generateClarifyingQuestions(for: activeDraft, userProfile: userAIProfile)
                    .map { $0.question.trimmed }
                    .filter { !$0.isEmpty }
                let deterministic = DecisionEngine.shared
                    .generateClarifyingQuestions(draft: activeDraft, userProfile: userAIProfile)
                    .map { $0.question.trimmed }
                    .filter { !$0.isEmpty }

                let candidates = (remote + deterministic)
                    .filter { $0.caseInsensitiveCompare(rejected) != .orderedSame }
                    .filter { !existing.contains($0.lowercased()) }

                guard let replacement = candidates.first else { return }
                activeDraft.clarifyingQuestions[index].question = replacement
                activeDraft.clarifyingQuestions[index].answer = ""
                activeDraft.lastUpdatedAt = .now
            } catch {
                if localAIFallbackEnabled,
                   let deterministic = DecisionEngine.shared
                   .generateClarifyingQuestions(draft: activeDraft, userProfile: userAIProfile)
                   .map({ $0.question.trimmed })
                   .first(where: { $0.caseInsensitiveCompare(rejected) != .orderedSame && !existing.contains($0.lowercased()) }) {
                    activeDraft.clarifyingQuestions[index].question = deterministic
                    activeDraft.clarifyingQuestions[index].answer = ""
                    activeDraft.lastUpdatedAt = .now
                } else {
                    lastError = "Could not refresh this question from Clarity AI. Please retry."
                }
            }
        }
    }

    func suggestOptionsFromClarifyingAnswers() {
        guard activeDraft.clarifyingQuestions.contains(where: { !$0.answer.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }) else { return }

        Task {
            do {
                busyMessage = "Generating options..."
                refreshUnifiedDecisionContext()
                let allAttachments = activeDraft.contextAttachments + activeDraft.vendors.flatMap(\.attachments)
                let extractedEvidence = try await services.extractor.extractEvidence(for: allAttachments)
                applyEvidenceMetadata(extractedEvidence)
                try await refreshDecisionBrief(extractedEvidence: extractedEvidence.map(\.extractedText).filter { !$0.isEmpty })
                let options = try await services.ai.suggestDecisionOptions(for: activeDraft, userProfile: userAIProfile)
                let fallbackOptions = extractOptionNamesFromNarrative()
                if !options.isEmpty {
                    mergeSuggestedOptions(options)
                }
                if options.isEmpty || meaningfulVendorCount < 2 {
                    mergeSuggestedOptions(fallbackOptions)
                }
                busyMessage = nil
            } catch {
                mergeSuggestedOptions(extractOptionNamesFromNarrative())
                busyMessage = nil
                lastError = error.localizedDescription
            }
        }
    }

    func prepareBiasChallenges(preferredOption: String? = nil) {
        let trimmedPreferred = preferredOption?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let optionName = trimmedPreferred.isEmpty
            ? (activeResult?.rankedVendors.first?.vendorName ?? activeDraft.vendors.first?.name ?? "the leading option")
            : trimmedPreferred

        Task {
            do {
                busyMessage = "Preparing challenge prompts..."
                refreshUnifiedDecisionContext()
                let challenges = try await services.ai.generateBiasChallenges(for: activeDraft, preferredOption: optionName, userProfile: userAIProfile)
                print("📋 BIAS_CHALLENGES: received \(challenges.count) challenges, types: \(challenges.map(\.type.rawValue))")
                let normalized = Array(challenges.prefix(3)).map { challenge in
                    var compact = challenge
                    let singleSentence = challenge.question
                        .components(separatedBy: .newlines)
                        .joined(separator: " ")
                        .split(whereSeparator: { $0 == "." || $0 == "!" || $0 == "?" })
                        .first
                        .map(String.init)?
                        .trimmingCharacters(in: .whitespacesAndNewlines) ?? challenge.question
                    compact.question = String(singleSentence.prefix(100))
                    compact.quickPickOptions = Array(
                        challenge.quickPickOptions
                            .map(\.trimmed)
                            .filter(\.isNotEmpty)
                            .prefix(5)
                    )
                    if compact.quickPickOptions.isEmpty {
                        compact.quickPickOptions = defaultQuickPicks(for: challenge.type)
                    }
                    return compact
                }
                if !normalized.isEmpty {
                    activeDraft.biasChallenges = normalized
                    refreshUnifiedDecisionContext()
                }
                busyMessage = nil
            } catch {
                busyMessage = nil
                lastError = error.localizedDescription
            }
        }
    }

    func updateBiasChallengeResponse(challengeID: String, response: String) {
        guard let index = activeDraft.biasChallenges.firstIndex(where: { $0.id == challengeID }) else { return }
        activeDraft.biasChallenges[index].response = response
        activeDraft.lastUpdatedAt = .now
        refreshUnifiedDecisionContext()
    }

    func updateBiasChallengeQuickPick(challengeID: String, selection: String?) {
        guard let index = activeDraft.biasChallenges.firstIndex(where: { $0.id == challengeID }) else { return }
        let normalized = selection?.trimmed
        if normalized?.isEmpty == true {
            activeDraft.biasChallenges[index].selectedQuickPick = nil
        } else {
            activeDraft.biasChallenges[index].selectedQuickPick = normalized
        }
        activeDraft.lastUpdatedAt = .now
        refreshUnifiedDecisionContext()
    }

    func applyAISuggestions() {
        guard !isApplyingAISuggestions else { return }
        Task {
            do {
                isApplyingAISuggestions = true
                try await generateAISuggestions()
                isApplyingAISuggestions = false
                busyMessage = nil
            } catch {
                isApplyingAISuggestions = false
                busyMessage = nil
                lastError = error.localizedDescription
            }
        }
    }

    func runExpressAnalysis() {
        Task {
            do {
                busyMessage = "Preparing quick clarity..."
                if activeDraft.vendors.allSatisfy({ isPlaceholderVendor($0) }) {
                    let options = try await services.ai.suggestDecisionOptions(for: activeDraft, userProfile: userAIProfile)
                    if !options.isEmpty {
                        mergeSuggestedOptions(options)
                    }
                }
                try await generateAISuggestions()
                normalizeWeights()
                let result = RankingEngine.computeResult(for: activeDraft)
                activeResult = result
                activeDraft.decisionReport = DecisionEngine.shared.buildDecisionReport(
                    draft: activeDraft,
                    result: result,
                    userProfile: userAIProfile
                )
                analysisSource = .localFallback
                analysisStatusMessage = nil
                await refreshInsightsFromCloud(for: result, userInitiated: false)
                busyMessage = nil
            } catch {
                busyMessage = nil
                lastError = error.localizedDescription
            }
        }
    }

    func normalizeWeights() {
        activeDraft.criteria = RankingEngine.normalizedCriteria(activeDraft.criteria)
        activeDraft.lastUpdatedAt = .now
    }

    func computeResult(navigateToResults: Bool = true) {
        normalizeWeights()
        activeResult = RankingEngine.computeResult(for: activeDraft)
        guard let result = activeResult else { return }
        let fallbackReport = DecisionEngine.shared.buildDecisionReport(
            draft: activeDraft,
            result: result,
            userProfile: userAIProfile
        )
        activeDraft.decisionReport = fallbackReport
        analysisSource = .localFallback
        analysisStatusMessage = nil
        refreshUnifiedDecisionContext()

        if navigateToResults {
            screen = .results
        }

        Task {
            await refreshInsightsFromCloud(for: result, userInitiated: false)
        }
    }

    func retryAnalysisInsights() {
        guard let result = activeResult else { return }
        Task {
            await refreshInsightsFromCloud(for: result, userInitiated: true)
        }
    }

    private func refreshInsightsFromCloud(for result: RankingResult, userInitiated: Bool) async {
        isRefreshingInsights = true
        if !userInitiated {
            analysisStatusMessage = "Refreshing analysis with Clarity AI..."
        }
        if userInitiated {
            busyMessage = "Refreshing Clarity AI analysis..."
        }

        defer {
            if userInitiated {
                busyMessage = nil
            }
        }

        do {
            refreshUnifiedDecisionContext()
            let insight = try await services.ai.generateInsights(draft: activeDraft, result: result, userProfile: userAIProfile)
            activeInsight = insight
            activeDraft.decisionReport = buildDecisionReport(
                from: insight,
                result: result,
                fallback: activeDraft.decisionReport
            )
            refreshUnifiedDecisionContext()
            analysisSource = .cloud
            analysisStatusMessage = nil
        } catch {
            print("⚠️ INSIGHTS_FALLBACK: \(error.localizedDescription)")
            if activeDraft.decisionReport == nil {
                analysisSource = .unavailable
                analysisStatusMessage = "Clarity AI analysis is unavailable right now. Retry when your connection is stable."
                if userInitiated {
                    lastError = "Could not refresh Clarity AI analysis. Please retry."
                }
            } else {
                analysisSource = .localFallback
                analysisStatusMessage = "Showing local analysis while Clarity AI is unavailable. You can retry."
            }
        }
        isRefreshingInsights = false
    }

    private func buildDecisionReport(from insight: InsightReportDraft, result: RankingResult, fallback: DecisionReport?) -> DecisionReport {
        let fallbackReport = fallback ?? DecisionEngine.shared.buildDecisionReport(
            draft: activeDraft,
            result: result,
            userProfile: userAIProfile
        )

        let recommendation = insight.winnerReasoning.trimmed.isNotEmpty
            ? insight.winnerReasoning.trimmed
            : fallbackReport.recommendation
        let drivers = {
            let parsed = parseDriversFromInsight(insight)
            return parsed.isEmpty ? fallbackReport.drivers : parsed
        }()
        let risks = insight.riskFlags.filter { $0.trimmed.isNotEmpty }.isEmpty
            ? fallbackReport.risks
            : insight.riskFlags.filter { $0.trimmed.isNotEmpty }
        let nextStep = {
            if let value = insight.nextStep?.trimmed, value.isNotEmpty { return value }
            if let value = insight.overlookedStrategicPoints.first?.trimmed, value.isNotEmpty { return value }
            return fallbackReport.nextStep
        }()
        let biasChecks = insight.sensitivityFindings.filter { $0.trimmed.isNotEmpty }.isEmpty
            ? fallbackReport.biasChecks
            : insight.sensitivityFindings.filter { $0.trimmed.isNotEmpty }

        return DecisionReport(
            recommendation: recommendation,
            drivers: drivers,
            risks: risks,
            confidence: inferConfidenceLabel(from: insight, result: result),
            nextStep: nextStep,
            biasChecks: biasChecks
        )
    }

    private func parseDriversFromInsight(_ insight: InsightReportDraft) -> [String] {
        if let drivers = insight.drivers?.map(\.trimmed).filter(\.isNotEmpty), !drivers.isEmpty {
            return Array(drivers.prefix(3))
        }

        let summaryLines = insight.summary
            .split(separator: "\n")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .map { line in
                line
                    .replacingOccurrences(of: "• ", with: "")
                    .replacingOccurrences(of: "- ", with: "")
                    .trimmed
            }
            .filter { line in
                line.isNotEmpty &&
                    !line.lowercased().hasPrefix("decision summary") &&
                    !line.lowercased().hasPrefix("recommendation")
            }

        if !summaryLines.isEmpty {
            return Array(summaryLines.prefix(3))
        }

        guard let winner = activeResult?.rankedVendors.first,
              let runnerUp = activeResult?.rankedVendors.dropFirst().first else {
            return []
        }
        let winnerLabel = resolvedOptionLabel(vendorID: winner.vendorID, fallback: winner.vendorName)
        let runnerLabel = resolvedOptionLabel(vendorID: runnerUp.vendorID, fallback: runnerUp.vendorName)
        let criteria = activeDraft.criteria.sorted { $0.weightPercent > $1.weightPercent }.prefix(3)
        return criteria.map { criterion in
            let winnerScore = activeDraft.scores.first(where: { $0.vendorID == winner.vendorID && $0.criterionID == criterion.id })?.score ?? 0
            let runnerScore = activeDraft.scores.first(where: { $0.vendorID == runnerUp.vendorID && $0.criterionID == criterion.id })?.score ?? 0
            return "\(criterion.name): \(winnerLabel) \(String(format: "%.1f", winnerScore)) vs \(runnerLabel) \(String(format: "%.1f", runnerScore)) (\(Int(criterion.weightPercent.rounded()))% weight)."
        }
    }

    private func inferConfidenceLabel(from insight: InsightReportDraft, result: RankingResult) -> String {
        if let explicit = insight.confidenceLabel?.trimmed, explicit.isNotEmpty {
            return explicit
        }

        let signalText = (
            insight.sensitivityFindings +
            insight.riskFlags +
            [insight.summary]
        )
            .joined(separator: " ")
            .lowercased()

        if signalText.contains("low confidence") || signalText.contains("confidence is low") || result.tieDetected || result.confidenceScore < 0.45 {
            return "Low — the lead is sensitive to assumption changes."
        }

        if signalText.contains("high confidence") || signalText.contains("strong evidence") || result.confidenceScore >= 0.78 {
            return "High — the lead remains stable across key criteria."
        }

        return "Medium — the current winner is plausible but still needs one targeted validation."
    }

    func saveCurrentProject(modelContext: ModelContext) {
        do {
            let owner = session?.userID ?? "local"
            try services.persistence.saveProjectDraft(activeDraft, ownerUserID: owner, result: activeResult, insight: activeInsight, context: modelContext)
            recentProjects = try services.persistence.loadProjects(for: owner, context: modelContext)
        } catch {
            lastError = error.localizedDescription
        }
    }

    func loadRecent(modelContext: ModelContext) {
        do {
            let owner = session?.userID ?? "local"
            recentProjects = try services.persistence.loadProjects(for: owner, context: modelContext)
        } catch {
            lastError = error.localizedDescription
        }
    }

    func signOut() {
        Task {
            await services.notifications.cancelAllFollowUps()
            do {
                try await services.auth.signOut()
            } catch {
                lastError = error.localizedDescription
            }
            session = nil
            onboardingAnswers = []
            activeDraft = .empty
            activeResult = nil
            activeInsight = nil
            chatMessages = []
            decisionChatMessages = []
            decisionChatPhase = .opening
            isChatTyping = false
            pendingFreeformReply = ""
            aiModeLabel = nil
            matrixSetupReady = false
            rankingEntryMode = .manual
            optionsValidationMessage = nil
            isApplyingAISuggestions = false
            matrixQualityFlags = MatrixQualityFlags()
            analysisSource = .localFallback
            analysisStatusMessage = nil
            isRefreshingInsights = false
            isGeneratingMatrix = false
            isGeneratingReassurance = false
            recentProjects = []
            userValuesRanking = []
            userInterests = []
            expressModeEnabled = false
            UserDefaults.standard.removeObject(forKey: LocalSessionKeys.guestUserID)
            screen = .auth
        }
    }

    func setDecisionOutcome(decided: Bool) {
        activeDraft.decisionStatus = decided ? .decided : .pending
        activeDraft.chosenOptionID = decided ? activeResult?.winnerID : nil
        if decided {
            ensureFollowUpCheckpoints()
        } else {
            activeDraft.followUpDeltaGuidance = nil
        }
        activeDraft.lastUpdatedAt = .now
        refreshUnifiedDecisionContext()
        syncFollowUpNotification()
    }

    func beginStillThinkingChallengeFlow() {
        setDecisionOutcome(decided: false)
        activeDraft.postChallengeReassurance = nil
        rankingEntryMode = .postAnalysisChallenge
        trackFlowEvent("challenge_started_from_results")
        screen = .ranking
    }

    func completeChallengeFlowAndGenerateReassurance() {
        activeDraft.postChallengeReassurance = nil
        let winner = activeResult?.rankedVendors.first?.vendorName ?? activeDraft.vendors.first?.name ?? "the leading option"
        let confidence = activeResult?.confidenceScore ?? 0
        let responses = activeDraft.biasChallenges.map { challenge in
            let quickPick = challenge.selectedQuickPick?.trimmed
            let typed = challenge.response.trimmed
            let answer: String
            if quickPick?.isNotEmpty == true && typed.isNotEmpty {
                answer = "Quick pick: \(quickPick!). Notes: \(typed)"
            } else if quickPick?.isNotEmpty == true {
                answer = "Quick pick: \(quickPick!)"
            } else if typed.isNotEmpty {
                answer = typed
            } else {
                answer = "Skipped"
            }
            return "\(challenge.question)\nAnswer: \(answer)"
        }.joined(separator: "\n\n")
        let prompt = """
        Build post-challenge reassurance using the full decision context.
        Current leading option: \(winner)
        Confidence score: \(String(format: "%.2f", confidence))
        Challenge responses:
        \(responses)
        Return sections exactly:
        Reassurance now
        Why this still holds
        What could invalidate it
        Concrete next action in 48 hours
        """

        Task {
            do {
                busyMessage = "Preparing reassurance..."
                isGeneratingReassurance = true
                refreshUnifiedDecisionContext()
                let reply = try await services.ai.decisionChat(
                    projectID: activeDraft.id,
                    phase: "post_challenge_reassurance",
                    message: prompt,
                    draft: activeDraft,
                    userProfile: userAIProfile
                )
                activeDraft.postChallengeReassurance = reply.content.trimmed
                activeDraft.lastUpdatedAt = .now
                refreshUnifiedDecisionContext()
                trackFlowEvent("challenge_reassurance_generated")
                isGeneratingReassurance = false
                busyMessage = nil
            } catch {
                isGeneratingReassurance = false
                busyMessage = nil
                lastError = error.localizedDescription
                activeDraft.postChallengeReassurance = "You are doing the right thing by pressure-testing this choice. Keep the top recommendation, validate one key assumption this week, and decide after that check."
                refreshUnifiedDecisionContext()
            }
        }
    }

    func prepareMatrixFromNarrativeAndRoute() async -> MatrixPreparationRoute {
        optionsValidationMessage = nil
        let validation = DecisionEngine.shared.validateOptionScope(draft: activeDraft, userProfile: userAIProfile)
        let parsed = DecisionEngine.shared.parse(draft: activeDraft, extractedEvidence: [], userProfile: userAIProfile)
        let explicitOptions = parsed.explicitOptions.filter(\.isExplicitNamed)

        if !validation.isValid {
            optionsValidationMessage = validation.message
            trackFlowEvent("flow_step_transition", details: "describe_to_options_missing_explicit")
            return .options
        }

        mergeSuggestedOptions(explicitOptions)
        activeDraft.constraintFindings = DecisionEngine.shared.detectConstraints(draft: activeDraft)
        activeDraft.clarifyingQuestions = Array(DecisionEngine.shared.generateClarifyingQuestions(draft: activeDraft, userProfile: userAIProfile).prefix(12))
        refreshUnifiedDecisionContext()
        trackFlowEvent("flow_step_transition", details: "describe_to_clarify")
        return .clarify
    }

    func prepareScoringFromCurrentOptions() async -> Bool {
        optionsValidationMessage = nil
        let validation = optionScopeValidation()
        if !validation.isValid {
            optionsValidationMessage = validation.message
            return false
        }
        do {
            isApplyingAISuggestions = true
            busyMessage = "Preparing weighted scoring..."
            activeDraft.constraintFindings = DecisionEngine.shared.detectConstraints(draft: activeDraft)
            try await generateAISuggestions()
            normalizeWeights()
            busyMessage = nil
            isApplyingAISuggestions = false
            return true
        } catch {
            busyMessage = nil
            isApplyingAISuggestions = false
            lastError = error.localizedDescription
            trackFlowEvent("matrix_refresh_error", details: error.localizedDescription)
            return false
        }
    }

    func setFollowUpReminder(enabled: Bool) {
        if enabled {
            ensureFollowUpCheckpoints()
        } else {
            activeDraft.followUpDate = nil
            activeDraft.followUpCheckpoints = []
        }
        activeDraft.lastUpdatedAt = .now
        refreshUnifiedDecisionContext()
        syncFollowUpNotification()
    }

    func updateFollowUpCheckpointNotes(checkpointID: String, notes: String) {
        guard let index = activeDraft.followUpCheckpoints.firstIndex(where: { $0.id == checkpointID }) else { return }
        activeDraft.followUpCheckpoints[index].notes = notes
        activeDraft.lastUpdatedAt = .now
        refreshUnifiedDecisionContext()
    }

    func completeFollowUpCheckpoint(_ checkpointID: String) {
        guard let index = activeDraft.followUpCheckpoints.firstIndex(where: { $0.id == checkpointID }) else { return }
        activeDraft.followUpCheckpoints[index].completedAt = .now
        activeDraft.lastUpdatedAt = .now
        refreshUnifiedDecisionContext()
    }

    func generateFollowUpDeltaGuidance(checkpointID: String) {
        guard let checkpoint = activeDraft.followUpCheckpoints.first(where: { $0.id == checkpointID }) else { return }
        let winnerLabel = activeResult?.rankedVendors.first.map { resolvedOptionLabel(vendorID: $0.vendorID, fallback: $0.vendorName) } ?? "the current leading option"
        let prompt = """
        Provide a follow-up delta recommendation.
        Current winner: \(winnerLabel)
        Checkpoint: \(checkpoint.title)
        What changed:
        \(checkpoint.notes.trimmed.isEmpty ? "No updates provided yet." : checkpoint.notes.trimmed)

        Return concise sections:
        Recommendation update
        What changed materially
        Risk now
        Next action this week
        """

        Task {
            do {
                isGeneratingReassurance = true
                refreshUnifiedDecisionContext()
                let response = try await services.ai.decisionChat(
                    projectID: activeDraft.id,
                    phase: "follow_up_delta",
                    message: prompt,
                    draft: activeDraft,
                    userProfile: userAIProfile
                )
                activeDraft.followUpDeltaGuidance = response.content.trimmed
                activeDraft.lastUpdatedAt = .now
                isGeneratingReassurance = false
            } catch {
                isGeneratingReassurance = false
                lastError = error.localizedDescription
                activeDraft.followUpDeltaGuidance = "No strong change signal yet. Re-check your top weighted criterion with one fresh external input this week."
            }
        }
    }

    func updateAlternativePathAnswer(_ answer: String) {
        activeDraft.alternativePathAnswer = answer.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : answer.trimmingCharacters(in: .whitespacesAndNewlines)
        activeDraft.lastUpdatedAt = .now
        refreshUnifiedDecisionContext()
    }

    func exportPDF() async -> URL? {
        guard let result = activeResult else { return nil }
        do {
            return try services.pdf.makePDF(project: activeDraft, result: result, insight: activeInsight)
        } catch {
            lastError = error.localizedDescription
            return nil
        }
    }

    func askChat(_ prompt: String, phase: String) {
        guard !prompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        chatMessages.append(ChatMessageDraft(role: "user", content: prompt))
        refreshUnifiedDecisionContext()

        Task {
            do {
                let reply = try await services.ai.decisionChat(projectID: activeDraft.id, phase: phase, message: prompt, draft: activeDraft, userProfile: userAIProfile)
                chatMessages.append(ChatMessageDraft(role: "assistant", content: reply.content))
                if !reply.recommendedActions.isEmpty {
                    let actionSummary = reply.recommendedActions.map { "• \($0)" }.joined(separator: "\n")
                    chatMessages.append(ChatMessageDraft(role: "assistant", content: "Recommended actions:\n\(actionSummary)"))
                }
            } catch {
                lastError = error.localizedDescription
            }
        }
    }

    private func upsertScore(_ score: ScoreDraft) {
        if let existingIndex = activeDraft.scores.firstIndex(where: { $0.vendorID == score.vendorID && $0.criterionID == score.criterionID }) {
            activeDraft.scores[existingIndex] = score
        } else {
            activeDraft.scores.append(score)
        }
    }

    private func generateAISuggestions() async throws {
        if busyMessage == nil {
            busyMessage = "Generating AI suggestions..."
        }
        isGeneratingMatrix = true
        defer { isGeneratingMatrix = false }
        matrixQualityFlags = MatrixQualityFlags()
        activeDraft.decisionReport = nil
        refreshUnifiedDecisionContext()
        let allAttachments = activeDraft.contextAttachments + activeDraft.vendors.flatMap(\.attachments)
        let extractedEvidence = try await services.extractor.extractEvidence(for: allAttachments)
        applyEvidenceMetadata(extractedEvidence)
        try await refreshDecisionBrief(extractedEvidence: extractedEvidence.map(\.extractedText).filter { !$0.isEmpty })
        activeDraft.constraintFindings = DecisionEngine.shared.detectConstraints(draft: activeDraft)
        let suggestion = try await services.ai.suggestRankingInputs(
            for: activeDraft,
            context: activeDraft.usageContext,
            extractedEvidence: extractedEvidence.map(\.extractedText).filter { !$0.isEmpty },
            userProfile: userAIProfile
        )
        print("📊 SCORING: received \(suggestion.draftScores.count) scores, \(suggestion.criteria.count) criteria")
        var qualityFlags = MatrixQualityFlags()
        if !suggestion.draftScores.isEmpty && suggestion.draftScores.allSatisfy({ $0.score == 0 }) {
            qualityFlags.allZeroScores = true
            print("⚠️ SCORING: All scores are 0 — likely fallback/mock payload or invalid matrix draft")
        }
        activeDraft.criteria = RankingEngine.normalizedCriteria(suggestion.criteria)
        if activeDraft.criteria.isEmpty {
            if localAIFallbackEnabled {
                let deterministic = DecisionEngine.shared.buildSuggestedInputs(
                    draft: activeDraft,
                    context: activeDraft.usageContext,
                    extractedEvidence: extractedEvidence.map(\.extractedText).filter { !$0.isEmpty },
                    userProfile: userAIProfile
                )
                activeDraft.criteria = deterministic.criteria
            } else {
                throw ScoreWiseServiceError.featureUnavailable("Clarity AI returned no criteria for this matrix. Please retry.")
            }
        }
        activeDraft.scores.removeAll()
        let expectedScoreCount = activeDraft.vendors.count * activeDraft.criteria.count
        qualityFlags.incompleteScores = suggestion.draftScores.count < expectedScoreCount

        if !localAIFallbackEnabled && (qualityFlags.allZeroScores || qualityFlags.incompleteScores) {
            let reason = qualityFlags.allZeroScores
                ? "Clarity AI returned a zeroed score matrix. Please refresh AI suggestions."
                : "Clarity AI returned incomplete matrix scores. Please refresh AI suggestions."
            matrixQualityFlags = qualityFlags
            throw ScoreWiseServiceError.featureUnavailable(reason)
        }

        for score in suggestion.draftScores {
            if score.confidence < 0.60 {
                var lowConfidence = score
                lowConfidence.evidenceSnippet = "Needs review: low-confidence suggestion. " + score.evidenceSnippet
                upsertScore(lowConfidence)
            } else {
                upsertScore(score)
            }
        }

        let constraints = activeDraft.constraintFindings ?? []
        if activeDraft.scores.count < expectedScoreCount {
            if localAIFallbackEnabled {
                let fallbackScores = DecisionEngine.shared.matrixBuilder.buildScores(
                    draft: activeDraft,
                    criteria: activeDraft.criteria,
                    constraints: constraints,
                    autoScoringEngine: DecisionEngine.shared.autoScoringEngine
                )
                for score in fallbackScores where !activeDraft.scores.contains(where: { $0.vendorID == score.vendorID && $0.criterionID == score.criterionID }) {
                    upsertScore(score)
                }
            } else {
                throw ScoreWiseServiceError.featureUnavailable("Clarity AI returned incomplete matrix scores. Please refresh AI suggestions.")
            }
        }

        if constraints.contains(where: { !$0.violatedOptionIDs.isEmpty }) {
            for index in activeDraft.scores.indices {
                let vendorID = activeDraft.scores[index].vendorID
                let criterionID = activeDraft.scores[index].criterionID
                let criterionName = activeDraft.criteria.first(where: { $0.id == criterionID })?.name.lowercased() ?? ""
                if constraints.contains(where: { $0.violatedOptionIDs.contains(vendorID) }) &&
                    (criterionName.contains("constraint") || criterionName.contains("compensation") || criterionName.contains("work model")) {
                    activeDraft.scores[index].score = min(activeDraft.scores[index].score, 4.5)
                    activeDraft.scores[index].evidenceSnippet = "Constraint warning: verify this score before finalizing."
                }
            }
        }

        qualityFlags.incompleteScores = activeDraft.scores.count < expectedScoreCount
        qualityFlags.allZeroScores = !activeDraft.scores.isEmpty && activeDraft.scores.allSatisfy { $0.score == 0 }

        var lowVarianceCriteria: [String] = []
        for criterion in activeDraft.criteria {
            let scoreIndexes = activeDraft.scores.indices.filter { activeDraft.scores[$0].criterionID == criterion.id }
            guard scoreIndexes.count >= 2 else { continue }
            let uniqueScores = Set(scoreIndexes.map { Int((activeDraft.scores[$0].score * 10).rounded()) })
            if uniqueScores.count <= 1 {
                lowVarianceCriteria.append(criterion.name)
                for index in scoreIndexes {
                    let warning = "⚠️ Scores appear identical — review and adjust based on your knowledge."
                    if !activeDraft.scores[index].evidenceSnippet.contains("⚠️ Scores appear identical") {
                        let trimmedEvidence = activeDraft.scores[index].evidenceSnippet.trimmed
                        activeDraft.scores[index].evidenceSnippet = trimmedEvidence.isEmpty ? warning : "\(warning) \(trimmedEvidence)"
                    }
                    activeDraft.scores[index].confidence = min(activeDraft.scores[index].confidence, 0.30)
                }
            }
        }
        qualityFlags.lowVarianceCriteria = lowVarianceCriteria
        matrixQualityFlags = qualityFlags

        let readyEvidenceCount = extractedEvidence.filter { $0.status == .ready && !$0.extractedText.isEmpty }.count
        let optionNames = activeDraft.vendors
            .map(\.name)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .joined(separator: ", ")
        let topCriteria = activeDraft.criteria
            .sorted { $0.weightPercent > $1.weightPercent }
            .prefix(3)
            .map(\.name)
            .joined(separator: ", ")
        let lowConfidenceCount = activeDraft.scores.filter { $0.confidence < 0.60 }.count
        let confidenceSuffix = lowConfidenceCount == 0
            ? " Draft scores are mostly high-confidence."
            : " \(lowConfidenceCount) score suggestion\(lowConfidenceCount == 1 ? "" : "s") need extra review."
        let qualitySuffix: String
        if qualityFlags.hasWarnings {
            var warnings: [String] = []
            if qualityFlags.allZeroScores {
                warnings.append("all scores returned as zero")
            }
            if qualityFlags.incompleteScores {
                warnings.append("matrix is incomplete")
            }
            if !qualityFlags.lowVarianceCriteria.isEmpty {
                warnings.append("identical scoring on \(qualityFlags.lowVarianceCriteria.prefix(2).joined(separator: ", "))")
            }
            qualitySuffix = " Quality flags: \(warnings.joined(separator: "; "))."
        } else {
            qualitySuffix = ""
        }
        aiSuggestionSummary = "AI reviewed \(readyEvidenceCount) source\(readyEvidenceCount == 1 ? "" : "s"), built \(activeDraft.criteria.count) criteria for \(optionNames.isEmpty ? "your current options" : optionNames), and weighted \(topCriteria.isEmpty ? "the strongest factors it found" : topCriteria) most heavily.\(confidenceSuffix)\(qualitySuffix)"
        refreshUnifiedDecisionContext()
    }

    private func refreshDecisionBrief(extractedEvidence: [String]) async throws {
        let brief = try await services.ai.generateDecisionBrief(for: activeDraft, extractedEvidence: extractedEvidence, userProfile: userAIProfile)
        activeDraft.decisionBrief = brief
        activeDraft.category = brief.inferredCategory
        activeDraft.constraintFindings = DecisionEngine.shared.detectConstraints(draft: activeDraft)

        if activeDraft.vendors.allSatisfy(isPlaceholderVendor) || meaningfulVendorCount < 2 {
            mergeSuggestedOptions(brief.detectedOptions)
        }

        if shouldApplyBriefCriteria {
            activeDraft.criteria = RankingEngine.normalizedCriteria(brief.suggestedCriteria)
        }
        refreshUnifiedDecisionContext()
    }

    private func mergeSuggestedOptions(_ options: [DecisionOptionSnapshot]) {
        let explicitOptions = DecisionEngine.shared
            .parse(draft: activeDraft, extractedEvidence: [], userProfile: userAIProfile)
            .explicitOptions
            .filter(\.isExplicitNamed)
        let strictOptions: [DecisionOptionSnapshot]
        if explicitOptions.count >= 2 {
            trackFlowEvent("options_filtered_explicit", details: "count=\(explicitOptions.count)")
            let suggestedByComparable = Dictionary(uniqueKeysWithValues: options.map {
                (comparableOptionName($0.label), $0)
            })
            strictOptions = explicitOptions.prefix(8).map { explicit in
                let comparable = comparableOptionName(explicit.label)
                let matched = suggestedByComparable[comparable]
                return DecisionOptionSnapshot(
                    id: explicit.id,
                    label: explicit.label,
                    type: explicit.type,
                    description: matched?.description ?? explicit.description ?? "Option taken directly from your situation.",
                    aiSuggested: true
                )
            }
        } else {
            strictOptions = options.filter(\.isExplicitNamed)
        }
        guard !strictOptions.isEmpty else { return }

        var remainingExisting = activeDraft.vendors
        var merged: [VendorDraft] = []

        for suggestion in strictOptions.prefix(8) {
            let normalizedLabel = normalizedOptionName(suggestion.label)
            if let matchedIndex = remainingExisting.firstIndex(where: { normalizedOptionName($0.name) == normalizedLabel }) {
                let existing = remainingExisting.remove(at: matchedIndex)
                merged.append(
                    VendorDraft(
                        id: existing.id,
                        name: suggestion.label,
                        notes: existing.notes.nonEmpty ?? suggestion.description ?? "",
                        attachments: existing.attachments
                    )
                )
                continue
            }

            if let placeholderIndex = remainingExisting.firstIndex(where: isPlaceholderVendor) {
                let placeholder = remainingExisting.remove(at: placeholderIndex)
                merged.append(
                    VendorDraft(
                        id: placeholder.id,
                        name: suggestion.label,
                        notes: placeholder.notes.nonEmpty ?? suggestion.description ?? "",
                        attachments: placeholder.attachments
                    )
                )
                continue
            }

            merged.append(
                VendorDraft(
                    id: suggestion.id,
                    name: suggestion.label,
                    notes: suggestion.description ?? "",
                    attachments: []
                )
            )
        }

        for existing in remainingExisting where existing.attachments.isNotEmpty || existing.notes.nonEmpty != nil || !isPlaceholderVendor(existing) {
            merged.append(existing)
        }

        activeDraft.vendors = Array(merged.prefix(8))
        activeDraft.lastUpdatedAt = .now
    }

    private var meaningfulVendorCount: Int {
        activeDraft.vendors.filter { !isPlaceholderVendor($0) }.count
    }

    private var shouldApplyBriefCriteria: Bool {
        activeDraft.criteria.isEmpty || activeDraft.criteria.map(\.name) == ["Cost", "Quality", "Support"]
    }

    private func applyEvidenceMetadata(_ evidence: [ExtractedAttachmentEvidence]) {
        let evidenceByID = Dictionary(uniqueKeysWithValues: evidence.map { ($0.attachmentID, $0) })
        activeDraft.contextAttachments = activeDraft.contextAttachments.map { attachment in
            attachment.applyingEvidence(evidenceByID[attachment.id])
        }
        activeDraft.vendors = activeDraft.vendors.map { vendor in
            var vendorCopy = vendor
            vendorCopy.attachments = vendor.attachments.map { attachment in
                attachment.applyingEvidence(evidenceByID[attachment.id])
            }
            return vendorCopy
        }
        activeDraft.lastUpdatedAt = .now
    }

    private func buildUnifiedDecisionContext() -> UnifiedDecisionContext {
        let transcriptLines = decisionChatMessages
            .filter { !$0.isTypingPlaceholder && $0.content.trimmed.isNotEmpty }
            .map { message in
                let role = message.role == .assistant ? "Clarity" : "User"
                return "\(role): \(message.content.trimmed)"
            }

        let options = activeDraft.vendors
            .map { vendor in
                DecisionOptionSnapshot(
                    id: vendor.id,
                    label: vendor.name.trimmed,
                    type: .genericChoice,
                    description: vendor.notes.trimmed.isNotEmpty ? vendor.notes.trimmed : nil,
                    aiSuggested: false
                )
            }
            .filter(\.isExplicitNamed)

        let allAttachments = activeDraft.contextAttachments + activeDraft.vendors.flatMap(\.attachments)
        let attachmentEvidence = allAttachments.compactMap { attachment -> String? in
            let message = attachment.validationMessage.trimmed
            guard message.isNotEmpty else { return nil }
            let title = attachment.titleHint.nonEmpty ?? attachment.fileName
            return "\(title): \(message)"
        }
        let attachmentsSummary = allAttachments.compactMap { attachment -> String? in
            let title = attachment.titleHint.nonEmpty ?? attachment.fileName
            let host = attachment.sourceHost.nonEmpty
            let status = attachment.status.displayName
            let trust = attachment.trustLevel.displayName
            if let host {
                return "\(title) (\(host)) - \(status), \(trust)"
            }
            return "\(title) - \(status), \(trust)"
        }

        let challengeResponsesSummary = activeDraft.biasChallenges.map { challenge in
            let quickPick = challenge.selectedQuickPick?.trimmed
            let typed = challenge.response.trimmed
            let detail: String
            if quickPick?.isNotEmpty == true && typed.isNotEmpty {
                detail = "Quick pick: \(quickPick!). Notes: \(typed)"
            } else if quickPick?.isNotEmpty == true {
                detail = "Quick pick: \(quickPick!)"
            } else if typed.isNotEmpty {
                detail = "Notes: \(typed)"
            } else {
                detail = "No answer"
            }
            return "\(challenge.question) -> \(detail)"
        }

        let clarifyingCitations = activeDraft.clarifyingQuestions
            .compactMap(\.citations)
            .flatMap { $0 }
        let insightCitations = activeInsight?.citations ?? []
        let citationSet = Set((clarifyingCitations + insightCitations).map { "\($0.cardId)|\($0.sourceLabel)|\($0.usedFor.rawValue)" })
        let mergedCitations = citationSet.compactMap { key -> EvidenceCitation? in
            let pieces = key.components(separatedBy: "|")
            guard pieces.count == 3 else { return nil }
            return EvidenceCitation(
                cardId: pieces[0],
                sourceLabel: pieces[1],
                usedFor: EvidenceCitationUsage(rawValue: pieces[2]) ?? .recommendation
            )
        }

        return UnifiedDecisionContext(
            decisionNarrative: activeDraft.contextNarrative.trimmed,
            conversationTranscript: transcriptLines,
            clarifyingAnswers: activeDraft.clarifyingQuestions,
            options: options,
            constraints: activeDraft.constraintFindings ?? [],
            criteria: activeDraft.criteria,
            scores: activeDraft.scores,
            biasChallenges: activeDraft.biasChallenges,
            attachmentEvidence: attachmentEvidence,
            challengeResponsesSummary: challengeResponsesSummary,
            attachmentsSummary: attachmentsSummary,
            knowledgeCitations: mergedCitations
        )
    }

    private func refreshUnifiedDecisionContext() {
        activeDraft.unifiedContext = buildUnifiedDecisionContext()
    }

    private func hydrateOnboardingState(from profile: UserProfileEntity) {
        onboardingAnswers = (try? JSONDecoder().decode([SurveyAnswer].self, from: Data(profile.surveyAnswersJSON.utf8))) ?? []
        userValuesRanking = (try? JSONDecoder().decode([String].self, from: Data(profile.valuesRankingJSON.utf8))) ?? []
        userInterests = (try? JSONDecoder().decode([String].self, from: Data(profile.interestsJSON.utf8))) ?? []
        expressModeEnabled = profile.speedPreferenceRaw == SpeedPreference.quick.rawValue &&
            profile.biggestChallengeRaw == BiggestChallenge.overthinking.rawValue
    }

    private func syncFollowUpNotification() {
        Task {
            if activeDraft.followUpDate == nil && activeDraft.followUpCheckpoints.isEmpty {
                await services.notifications.cancelFollowUp(for: activeDraft.id)
                return
            }

            do {
                try await services.notifications.scheduleFollowUp(for: activeDraft, result: activeResult)
            } catch {
                lastError = error.localizedDescription
            }
        }
    }

    private func ensureFollowUpCheckpoints() {
        let now = Date()
        let day7 = Calendar.current.date(byAdding: .day, value: 7, to: now)
        let day30 = Calendar.current.date(byAdding: .day, value: 30, to: now)
        var checkpoints: [DecisionFollowUpCheckpoint] = []
        checkpoints.append(
            DecisionFollowUpCheckpoint(
                title: "7-day check-in",
                dueDate: day7 ?? now,
                completedAt: nil,
                notes: ""
            )
        )
        checkpoints.append(
            DecisionFollowUpCheckpoint(
                title: "30-day check-in",
                dueDate: day30 ?? now,
                completedAt: nil,
                notes: ""
            )
        )
        activeDraft.followUpCheckpoints = checkpoints
        activeDraft.followUpDate = checkpoints.last?.dueDate
    }

    private func defaultQuickPicks(for type: BiasChallengeType) -> [String] {
        switch type {
        case .friendTest:
            return ["Can justify clearly", "Need stronger case", "Still undecided"]
        case .preMortem:
            return ["Main risk is execution", "Main risk is fit", "Risk feels manageable"]
        case .inversion:
            return ["Would regret skipping alternative", "Would regret changing now", "Regret risk is balanced"]
        case .worstCase:
            return ["Backup plan exists", "Backup plan is weak", "Worst-case is unacceptable"]
        case .tenTenTen:
            return ["Still right long-term", "Only feels right now", "Need long-term proof"]
        case .inactionCost:
            return ["Delay is costly", "Delay cost is moderate", "Delay cost is low"]
        case .valuesCheck:
            return ["Aligned with top value", "Partially aligned", "Feels safe but misaligned"]
        }
    }

    private func normalizedOptionName(_ name: String) -> String {
        name
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
    }

    private func comparableOptionName(_ name: String) -> String {
        normalizedOptionName(name)
            .replacingOccurrences(of: "accept ", with: "")
            .replacingOccurrences(of: "choose ", with: "")
            .replacingOccurrences(of: "go with ", with: "")
            .replacingOccurrences(of: "the ", with: "")
            .replacingOccurrences(of: "offer ", with: "offer")
            .replacingOccurrences(of: "  ", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func explicitOptionNamesFromContext() -> [String] {
        DecisionEngine.shared
            .parse(draft: activeDraft, extractedEvidence: [], userProfile: userAIProfile)
            .explicitOptions
            .filter(\.isExplicitNamed)
            .map(\.label)
    }

    private func extractOptionNamesFromNarrative() -> [DecisionOptionSnapshot] {
        let explicit = DecisionEngine.shared
            .parse(draft: activeDraft, extractedEvidence: [], userProfile: userAIProfile)
            .explicitOptions
            .filter(\.isExplicitNamed)
        guard explicit.count >= 2 else { return [] }
        return Array(explicit.prefix(8))
    }

    func resolvedOptionLabel(vendorID: String, fallback: String? = nil) -> String {
        if let exact = activeDraft.vendors.first(where: { $0.id == vendorID })?.name.trimmed, exact.isNotEmpty {
            return exact
        }
        let fallbackName = fallback?.trimmed ?? ""
        if fallbackName.isNotEmpty, !isGenericOptionLabel(fallbackName) {
            return fallbackName
        }
        if let resultName = activeResult?.rankedVendors.first(where: { $0.vendorID == vendorID })?.vendorName.trimmed,
           resultName.isNotEmpty,
           !isGenericOptionLabel(resultName) {
            return resultName
        }
        return "Unknown option (data sync needed)"
    }

    func synthesizedRecommendationText() -> String {
        guard let result = activeResult, let winner = result.rankedVendors.first else {
            return "Choose the option that best matches your highest-weight criterion and hard constraints."
        }
        let winnerLabel = resolvedOptionLabel(vendorID: winner.vendorID, fallback: winner.vendorName)
        let margin = {
            guard result.rankedVendors.count > 1 else { return winner.totalScore }
            return max(0, winner.totalScore - result.rankedVendors[1].totalScore)
        }()
        let topCriteria = activeDraft.criteria
            .sorted { $0.weightPercent > $1.weightPercent }
            .prefix(2)
            .map(\.name)
            .joined(separator: " and ")
        if margin < 0.2 {
            return "\(winnerLabel) is currently leading, but the score difference is very small. Treat this as a near tie and decide using the highest-risk unmodeled factor."
        }
        let criteriaText = topCriteria.isEmpty ? "your weighted criteria" : topCriteria
        return "\(winnerLabel) leads by \(String(format: "%.1f", margin)) points based on \(criteriaText)."
    }

    func synthesizedReassuranceText() -> String {
        let recommendation = synthesizedRecommendationText()
        let answeredCount = activeDraft.biasChallenges.filter { !$0.response.trimmed.isEmpty }.count
        if answeredCount == 0 {
            return "\(recommendation) Capture one concrete risk in writing, run one validation check this week, then decide."
        }
        return "\(recommendation) Your challenge-check responses show deliberate thinking. Validate the biggest remaining uncertainty, then commit."
    }

    private func isGenericOptionLabel(_ value: String) -> Bool {
        let lower = value.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        return lower.hasPrefix("vendor ") || lower.hasPrefix("option ") || lower.hasPrefix("candidate ")
    }

    private func truncatedTitle(from text: String, maxLength: Int) -> String {
        let trimmed = text.trimmed
        guard trimmed.count > maxLength else { return trimmed }
        let words = trimmed.split(separator: " ")
        var current = ""
        for word in words {
            let candidate = current.isEmpty ? String(word) : "\(current) \(word)"
            if candidate.count > maxLength {
                break
            }
            current = candidate
        }
        if current.isEmpty {
            return "\(String(trimmed.prefix(maxLength)).trimmed)..."
        }
        return current.hasSuffix("...") ? current : "\(current)..."
    }

    private func trackFlowEvent(_ name: String, details: String = "") {
#if DEBUG
        if details.isEmpty {
            print("[FlowEvent] \(name)")
        } else {
            print("[FlowEvent] \(name): \(details)")
        }
#endif
    }

    private func firstRegexGroups(pattern: String, in text: String) -> [String]? {
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return nil }
        let nsrange = NSRange(text.startIndex..<text.endIndex, in: text)
        guard let match = regex.firstMatch(in: text, range: nsrange), match.numberOfRanges > 1 else { return nil }
        return (1..<match.numberOfRanges).compactMap { index in
            let range = match.range(at: index)
            guard let swiftRange = Range(range, in: text) else { return nil }
            return String(text[swiftRange]).trimmingCharacters(in: .whitespacesAndNewlines)
        }
    }

    private func allRegexGroups(pattern: String, in text: String) -> [[String]]? {
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return nil }
        let nsrange = NSRange(text.startIndex..<text.endIndex, in: text)
        let matches = regex.matches(in: text, range: nsrange)
        guard !matches.isEmpty else { return nil }
        return matches.map { match in
            (1..<match.numberOfRanges).compactMap { index in
                let range = match.range(at: index)
                guard let swiftRange = Range(range, in: text) else { return nil }
                return String(text[swiftRange]).trimmingCharacters(in: .whitespacesAndNewlines)
            }
        }
    }

    private func isPlaceholderVendor(_ vendor: VendorDraft) -> Bool {
        let name = normalizedOptionName(vendor.name)
        return name.isEmpty ||
            name.hasPrefix("vendor ") ||
            name.hasPrefix("option ") ||
            name.hasPrefix("candidate ")
    }

    private func rebuildDecisionConversationSummary() {
        let lines = decisionChatMessages
            .filter { !$0.isTypingPlaceholder && $0.role == .user && $0.content.trimmed.isNotEmpty && $0.content.trimmed.caseInsensitiveCompare("Skip") != .orderedSame }
            .map { $0.content.trimmed }
        activeDraft.conversationSummary = lines.joined(separator: "\n")
    }

    private func appendTypingPlaceholder() {
        decisionChatMessages.append(
            DecisionChatMessage(
                role: .assistant,
                content: "",
                options: [],
                allowSkip: false,
                allowsFreeformReply: false,
                cta: nil,
                framework: nil,
                createdAt: .now,
                isTypingPlaceholder: true
            )
        )
    }

    private func removeTypingPlaceholder() {
        if let index = decisionChatMessages.firstIndex(where: \.isTypingPlaceholder) {
            decisionChatMessages.remove(at: index)
        }
    }

    private func askedFrameworkQuestionCount() -> Int {
        decisionChatMessages.filter { !$0.isTypingPlaceholder && $0.role == .assistant && $0.framework != nil }.count
    }

    private func forceChatTransition(message: String = "I have enough context. Let's set up your comparison.") {
        removeTypingPlaceholder()
        decisionChatPhase = .transitionReady
        activeDraft.chatPhase = .transitionReady
        if decisionChatMessages.last?.cta == nil {
            decisionChatMessages.append(
                DecisionChatMessage(
                    role: .assistant,
                    content: message,
                    options: [],
                    allowSkip: false,
                    allowsFreeformReply: false,
                    cta: ChatMessageCTA(title: "Set Up Your Options", action: .setupOptions),
                    framework: nil,
                    createdAt: .now,
                    isTypingPlaceholder: false
                )
            )
        }
        isChatTyping = false
        refreshUnifiedDecisionContext()
    }

    private func requestStartDecisionConversation() {
        guard !isChatTyping else { return }
        refreshUnifiedDecisionContext()
        isChatTyping = true
        appendTypingPlaceholder()

        Task {
            do {
                let response = try await services.ai.startDecisionConversation(
                    projectID: activeDraft.id,
                    contextNarrative: activeDraft.contextNarrative,
                    usageContext: activeDraft.usageContext,
                    userProfile: userAIProfile
                )
                removeTypingPlaceholder()
                applyConversationResponse(response)
                aiModeLabel = "Clarity AI"
                isChatTyping = false
            } catch {
                removeTypingPlaceholder()
                aiModeLabel = "AI unavailable"
                appendConversationFailureMessage("I couldn’t start Clarity AI right now. Please retry.")
                isChatTyping = false
            }
        }
    }

    private func requestContinueDecisionConversation(latestUserResponse: String, selectedOptionIndex: Int?) {
        guard !isChatTyping else { return }
        refreshUnifiedDecisionContext()

        if let last = decisionChatMessages.last, last.cta != nil {
            return
        }

        let questionCount = askedFrameworkQuestionCount()
        if questionCount >= 4 {
            forceChatTransition()
            return
        }

        isChatTyping = true
        appendTypingPlaceholder()

        Task {
            do {
                let response = try await services.ai.continueDecisionConversation(
                    projectID: activeDraft.id,
                    transcript: decisionChatMessages.filter { !$0.isTypingPlaceholder },
                    latestUserResponse: latestUserResponse,
                    selectedOptionIndex: selectedOptionIndex,
                    draft: activeDraft,
                    userProfile: userAIProfile
                )
                removeTypingPlaceholder()
                applyConversationResponse(response)
                aiModeLabel = "Clarity AI"
                isChatTyping = false
            } catch {
                if questionCount >= 3 {
                    forceChatTransition(message: "I have enough context to build your matrix. Let's set up your options.")
                } else {
                    removeTypingPlaceholder()
                    aiModeLabel = "AI unavailable"
                    appendConversationFailureMessage("I couldn’t get the next Clarity AI turn. Please retry.")
                    isChatTyping = false
                }
            }
        }
    }

    private func applyConversationResponse(_ response: DecisionConversationResponse) {
        var message = response.message
        message.id = UUID().uuidString
        message.createdAt = .now
        decisionChatMessages.append(message)
        decisionChatPhase = response.conversationState.phase
        activeDraft.chatPhase = response.conversationState.phase
        activeDraft.frameworksUsed = response.conversationState.frameworksUsed
        activeDraft.lastUpdatedAt = .now
        rebuildDecisionConversationSummary()
        refreshUnifiedDecisionContext()
    }

    private func applyMatrixSetupFromConversation(_ setup: DecisionMatrixSetup) {
        activeDraft.decisionBrief = setup.decisionBrief
        activeDraft.category = setup.decisionBrief.inferredCategory
        activeDraft.chatDerivedOptions = setup.decisionBrief.detectedOptions
        activeDraft.chatDerivedCriteria = setup.suggestedCriteria
        let optionSource = setup.suggestedOptions.isEmpty ? setup.decisionBrief.detectedOptions : setup.suggestedOptions
        mergeSuggestedOptions(optionSource)
        activeDraft.criteria = RankingEngine.normalizedCriteria(
            setup.suggestedCriteria.isEmpty ? setup.decisionBrief.suggestedCriteria : setup.suggestedCriteria
        )
        activeDraft.constraintFindings = DecisionEngine.shared.detectConstraints(draft: activeDraft)
        activeDraft.lastUpdatedAt = .now
        refreshUnifiedDecisionContext()
    }

    private func appendConversationFailureMessage(_ text: String) {
        decisionChatMessages.append(
            DecisionChatMessage(
                role: .assistant,
                content: text,
                options: [],
                allowSkip: false,
                allowsFreeformReply: false,
                cta: nil,
                framework: nil,
                createdAt: .now,
                isTypingPlaceholder: false
            )
        )
    }
}

private extension VendorAttachment {
    func applyingEvidence(_ evidence: ExtractedAttachmentEvidence?) -> VendorAttachment {
        guard let evidence else { return self }
        var copy = self
        copy.status = evidence.status
        copy.trustLevel = evidence.trustLevel
        copy.sourceHost = evidence.sourceHost
        copy.titleHint = evidence.titleHint
        copy.validationMessage = evidence.validationMessage
        return copy
    }
}

private extension String {
    var trimmed: String {
        trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var isNotEmpty: Bool {
        !trimmed.isEmpty
    }

    var nonEmpty: String? {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    var capitalizedSentence: String {
        guard let first else { return self }
        return first.uppercased() + dropFirst()
    }
}

private extension Array {
    var isNotEmpty: Bool { !isEmpty }
}
