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
        decisionChatMessages = []
        decisionChatPhase = .collecting
        isChatTyping = false
        pendingFreeformReply = ""
        aiModeLabel = "Offline guidance"
        matrixSetupReady = false
        rankingEntryMode = .manual
        optionsValidationMessage = nil

        activeDraft.contextNarrative = trimmed
        activeDraft.title = String(trimmed.prefix(56))
        activeDraft.chatPhase = .collecting
        activeDraft.frameworksUsed = []
        activeDraft.postChallengeReassurance = nil
        activeDraft.constraintFindings = []
        activeDraft.decisionReport = nil

        decisionChatMessages.append(
            DecisionChatMessage(
                id: UUID().uuidString,
                role: .assistant,
                content: "I'm here to help you think through this decision clearly. What's on your mind?",
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
                id: UUID().uuidString,
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
        screen = .decisionChat
        queueNextDecisionChatTurn()
    }

    func sendFreeformChatReply() {
        let trimmed = pendingFreeformReply.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        pendingFreeformReply = ""
        decisionChatMessages.append(
            DecisionChatMessage(
                id: UUID().uuidString,
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
        queueNextDecisionChatTurn()
    }

    func selectChatOption(_ option: DecisionChatOption) {
        decisionChatMessages.append(
            DecisionChatMessage(
                id: UUID().uuidString,
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
        queueNextDecisionChatTurn()
    }

    func skipChatQuestion() {
        decisionChatMessages.append(
            DecisionChatMessage(
                id: UUID().uuidString,
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
        queueNextDecisionChatTurn()
    }

    func completeChatAndPrepareMatrix() {
        decisionChatPhase = .completed
        activeDraft.chatPhase = .completed
        activeDraft.chatCompletedAt = .now
        optionsValidationMessage = nil
        rebuildDecisionConversationSummary()
        Task {
            do {
                try await refreshDecisionBrief(extractedEvidence: [])
                activeDraft.chatDerivedOptions = activeDraft.decisionBrief?.detectedOptions ?? []
                activeDraft.chatDerivedCriteria = activeDraft.decisionBrief?.suggestedCriteria ?? []
                activeDraft.constraintFindings = DecisionEngine.shared.detectConstraints(draft: activeDraft)
            } catch {
                activeDraft.chatDerivedOptions = []
                activeDraft.chatDerivedCriteria = []
                activeDraft.constraintFindings = DecisionEngine.shared.detectConstraints(draft: activeDraft)
            }
            rankingEntryMode = .chatReady
            trackFlowEvent("flow_entry_mode", details: "chatReady")
            matrixSetupReady = true
            screen = .ranking
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
        return option.id
    }

    func updateVendorOption(id: String, name: String, notes: String) {
        guard let index = activeDraft.vendors.firstIndex(where: { $0.id == id }) else { return }
        activeDraft.vendors[index].name = name
        activeDraft.vendors[index].notes = notes
        optionsValidationMessage = nil
        activeDraft.lastUpdatedAt = .now
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
    }

    func prepareClarifyingQuestions() {
        guard !activeDraft.contextNarrative.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }

        Task {
            do {
                busyMessage = "Preparing clarifying questions..."
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
                let fallbackQuestions = DecisionEngine.shared.generateClarifyingQuestions(draft: activeDraft, userProfile: userAIProfile)
                let selected = normalizedRemote.count >= 6 ? normalizedRemote : fallbackQuestions
                activeDraft.clarifyingQuestions = Array(selected.prefix(12))
                busyMessage = nil
            } catch {
                busyMessage = nil
                activeDraft.clarifyingQuestions = Array(DecisionEngine.shared.generateClarifyingQuestions(draft: activeDraft, userProfile: userAIProfile).prefix(12))
            }
        }
    }

    func updateClarifyingAnswer(questionID: String, answer: String) {
        guard let index = activeDraft.clarifyingQuestions.firstIndex(where: { $0.id == questionID }) else { return }
        activeDraft.clarifyingQuestions[index].answer = answer
        activeDraft.lastUpdatedAt = .now
    }

    func suggestOptionsFromClarifyingAnswers() {
        guard activeDraft.clarifyingQuestions.contains(where: { !$0.answer.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }) else { return }

        Task {
            do {
                busyMessage = "Generating options..."
                let allAttachments = activeDraft.contextAttachments + activeDraft.vendors.flatMap(\.attachments)
                let extractedEvidence = try await services.extractor.extractEvidence(for: allAttachments)
                applyEvidenceMetadata(extractedEvidence)
                try await refreshDecisionBrief(extractedEvidence: extractedEvidence.map(\.extractedText).filter { !$0.isEmpty })
                let options = try await services.ai.suggestDecisionOptions(for: activeDraft, userProfile: userAIProfile)
                if !options.isEmpty {
                    mergeSuggestedOptions(options)
                }
                busyMessage = nil
            } catch {
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
                let challenges = try await services.ai.generateBiasChallenges(for: activeDraft, preferredOption: optionName, userProfile: userAIProfile)
                let normalized = Array(challenges.prefix(3)).map { challenge in
                    var compact = challenge
                    let singleSentence = challenge.question
                        .components(separatedBy: .newlines)
                        .joined(separator: " ")
                        .split(separator: ".")
                        .first
                        .map(String.init)?
                        .trimmingCharacters(in: .whitespacesAndNewlines) ?? challenge.question
                    compact.question = String(singleSentence.prefix(120))
                    return compact
                }
                if !normalized.isEmpty {
                    activeDraft.biasChallenges = normalized
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
                activeInsight = try await services.ai.generateInsights(draft: activeDraft, result: result, userProfile: userAIProfile)
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
        if let result = activeResult {
            activeDraft.decisionReport = DecisionEngine.shared.buildDecisionReport(
                draft: activeDraft,
                result: result,
                userProfile: userAIProfile
            )
        }

        Task {
            do {
                activeInsight = try await services.ai.generateInsights(draft: activeDraft, result: activeResult!, userProfile: userAIProfile)
            } catch {
                lastError = error.localizedDescription
            }
        }

        if navigateToResults {
            screen = .results
        }
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
        activeDraft.lastUpdatedAt = .now
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
            let answer = challenge.response.trimmed.isEmpty ? "Skipped" : challenge.response.trimmed
            return "\(challenge.question)\nAnswer: \(answer)"
        }.joined(separator: "\n\n")
        let prompt = """
        Reassure me using my challenge-check responses.
        Current leading option: \(winner)
        Confidence score: \(String(format: "%.2f", confidence))
        Challenge responses:
        \(responses)

        Give a calm recommendation with practical next steps and what uncertainty still remains.
        """

        Task {
            do {
                busyMessage = "Preparing reassurance..."
                let reply = try await services.ai.decisionChat(
                    projectID: activeDraft.id,
                    phase: "post_challenge_reassurance",
                    message: prompt,
                    draft: activeDraft,
                    userProfile: userAIProfile
                )
                activeDraft.postChallengeReassurance = reply.content.trimmed
                activeDraft.lastUpdatedAt = .now
                trackFlowEvent("challenge_reassurance_generated")
                busyMessage = nil
            } catch {
                busyMessage = nil
                lastError = error.localizedDescription
                activeDraft.postChallengeReassurance = "You are doing the right thing by pressure-testing this choice. Keep the top recommendation, validate one key assumption this week, and decide after that check."
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
        activeDraft.followUpDate = enabled ? Calendar.current.date(byAdding: .day, value: 30, to: .now) : nil
        activeDraft.lastUpdatedAt = .now
        syncFollowUpNotification()
    }

    func updateAlternativePathAnswer(_ answer: String) {
        activeDraft.alternativePathAnswer = answer.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : answer.trimmingCharacters(in: .whitespacesAndNewlines)
        activeDraft.lastUpdatedAt = .now
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
        activeDraft.decisionReport = nil
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
        activeDraft.criteria = RankingEngine.normalizedCriteria(suggestion.criteria)
        if activeDraft.criteria.isEmpty {
            let deterministic = DecisionEngine.shared.buildSuggestedInputs(
                draft: activeDraft,
                context: activeDraft.usageContext,
                extractedEvidence: extractedEvidence.map(\.extractedText).filter { !$0.isEmpty },
                userProfile: userAIProfile
            )
            activeDraft.criteria = deterministic.criteria
        }
        activeDraft.scores.removeAll()

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
        let fallbackScores = DecisionEngine.shared.matrixBuilder.buildScores(
            draft: activeDraft,
            criteria: activeDraft.criteria,
            constraints: constraints,
            autoScoringEngine: DecisionEngine.shared.autoScoringEngine
        )
        for score in fallbackScores where !activeDraft.scores.contains(where: { $0.vendorID == score.vendorID && $0.criterionID == score.criterionID }) {
            upsertScore(score)
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
        aiSuggestionSummary = "AI reviewed \(readyEvidenceCount) source\(readyEvidenceCount == 1 ? "" : "s"), built \(activeDraft.criteria.count) criteria for \(optionNames.isEmpty ? "your current options" : optionNames), and weighted \(topCriteria.isEmpty ? "the strongest factors it found" : topCriteria) most heavily.\(confidenceSuffix)"
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

    private func hydrateOnboardingState(from profile: UserProfileEntity) {
        onboardingAnswers = (try? JSONDecoder().decode([SurveyAnswer].self, from: Data(profile.surveyAnswersJSON.utf8))) ?? []
        userValuesRanking = (try? JSONDecoder().decode([String].self, from: Data(profile.valuesRankingJSON.utf8))) ?? []
        userInterests = (try? JSONDecoder().decode([String].self, from: Data(profile.interestsJSON.utf8))) ?? []
        expressModeEnabled = profile.speedPreferenceRaw == SpeedPreference.quick.rawValue &&
            profile.biggestChallengeRaw == BiggestChallenge.overthinking.rawValue
    }

    private func syncFollowUpNotification() {
        Task {
            if activeDraft.followUpDate == nil {
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

    private func queueNextDecisionChatTurn() {
        guard !isChatTyping else { return }

        if let last = decisionChatMessages.last, last.cta != nil {
            return
        }

        let nextMessage = nextDecisionChatMessage()
        decisionChatMessages.append(
            DecisionChatMessage(
                id: UUID().uuidString,
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
        isChatTyping = true

        Task {
            try? await Task.sleep(nanoseconds: 900_000_000)
            guard !Task.isCancelled else { return }
            if let index = decisionChatMessages.firstIndex(where: \.isTypingPlaceholder) {
                decisionChatMessages.remove(at: index)
            }
            decisionChatMessages.append(nextMessage)
            isChatTyping = false
        }
    }

    private func nextDecisionChatMessage() -> DecisionChatMessage {
        let turns = decisionChatTurnSeeds()

        if activeDraft.frameworksUsed.count >= turns.count {
            decisionChatPhase = .transitionReady
            activeDraft.chatPhase = .transitionReady
            return DecisionChatMessage(
                id: UUID().uuidString,
                role: .assistant,
                content: "I have enough context to turn this into real options, criteria, and draft scoring. Let's set up the comparison.",
                options: [],
                allowSkip: false,
                allowsFreeformReply: false,
                cta: ChatMessageCTA(title: "Set Up Your Options", action: .setupOptions),
                framework: nil,
                createdAt: .now,
                isTypingPlaceholder: false
            )
        }

        let nextTurn = turns[activeDraft.frameworksUsed.count]
        activeDraft.frameworksUsed.append(nextTurn.framework)
        activeDraft.chatPhase = .collecting

        return DecisionChatMessage(
            id: UUID().uuidString,
            role: .assistant,
            content: nextTurn.question,
            options: nextTurn.options.enumerated().map { index, text in
                DecisionChatOption(id: UUID().uuidString, index: index + 1, text: text)
            },
            allowSkip: true,
            allowsFreeformReply: true,
            cta: nil,
            framework: nextTurn.framework,
            createdAt: .now,
            isTypingPlaceholder: false
        )
    }

    private func decisionChatTurnSeeds() -> [(framework: DecisionFramework, question: String, options: [String])] {
        let brief = LocalDecisionIntelligence.decisionBrief(for: activeDraft, extractedEvidence: [], userProfile: userAIProfile)
        let optionLabels = brief.detectedOptions.map(\.label)
        let leadingGoal = conciseChatLabel(brief.goals.first, fallback: "Make the strongest long-term choice")
        let leadingConstraint = conciseChatLabel(brief.constraints.first, fallback: "A hard constraint rules options out")
        let leadingRisk = conciseChatLabel(brief.risks.first, fallback: "One risk could change the decision")
        let leadingTension = conciseChatLabel(brief.tensions.first, fallback: "There is one central trade-off")

        return [
            (
                .valuesAlignment,
                "What matters most in this decision right now?",
                uniqueChatOptions([
                    leadingGoal,
                    "Protect stability and avoid a bad move",
                    "Keep flexibility if facts change",
                    "Move toward the better long-term option"
                ])
            ),
            (
                .riskAssessment,
                "What would rule an option out fastest?",
                uniqueChatOptions([
                    leadingConstraint,
                    "The timeline is too slow",
                    "The money or practical trade-off is wrong",
                    leadingRisk
                ])
            ),
            (
                .opportunityCost,
                optionLabels.count >= 2
                    ? "Which option set is closest to the real choice?"
                    : "What kind of choice am I setting up for you?",
                optionLabels.count >= 2
                    ? uniqueChatOptions(Array(optionLabels.prefix(4)))
                    : uniqueChatOptions(chatFallbackOptionPrompts())
            ),
            (
                .reversibility,
                "What is still missing before I set up the scoring?",
                uniqueChatOptions([
                    "Nothing major, compare now",
                    "I need to validate one assumption",
                    "I need clearer option names",
                    leadingTension
                ])
            )
        ]
    }

    private func chatFallbackOptionPrompts() -> [String] {
        let lower = activeDraft.contextNarrative.lowercased()

        if lower.contains("job") || lower.contains("offer") || lower.contains("role") {
            return [
                "Stay with the current path",
                "Take the new role or offer",
                "Negotiate before deciding",
                "Something else"
            ]
        }

        if lower.contains("move") || lower.contains("city") || lower.contains("relocate") {
            return [
                "Stay where I am",
                "Move to the new place",
                "Test the move first",
                "Something else"
            ]
        }

        if lower.contains("hire") || lower.contains("candidate") || lower.contains("recruit") {
            return [
                "Compare named candidates",
                "Keep searching",
                "Make a conditional offer",
                "Something else"
            ]
        }

        if lower.contains("vendor") || lower.contains("provider") || lower.contains("tool") || lower.contains("platform") {
            return [
                "Keep the current solution",
                "Switch to the new option",
                "Pilot before committing",
                "Something else"
            ]
        }

        return [
            "Keep the current path",
            "Choose the strongest alternative",
            "Try a reversible middle option",
            "Something else"
        ]
    }

    private func conciseChatLabel(_ text: String?, fallback: String) -> String {
        guard let text, text.trimmed.isNotEmpty else { return fallback }
        let cleaned = text
            .replacingOccurrences(of: "Any new option should be ", with: "")
            .replacingOccurrences(of: "The user is ", with: "")
            .replacingOccurrences(of: "The current recommendation may ", with: "")
            .trimmed
        let words = cleaned.split(whereSeparator: \.isWhitespace)
        if words.count <= 8 {
            return cleaned
        }
        return words.prefix(8).joined(separator: " ")
    }

    private func uniqueChatOptions(_ candidates: [String]) -> [String] {
        var seen: Set<String> = []
        var results: [String] = []

        for candidate in candidates {
            let trimmed = candidate.trimmed
            guard !trimmed.isEmpty else { continue }
            let key = trimmed.lowercased()
            guard !seen.contains(key) else { continue }
            seen.insert(key)
            results.append(trimmed)
            if results.count == 4 {
                break
            }
        }

        while results.count < 4 {
            let fallback = ["Not sure yet", "Need more detail", "It depends on evidence", "Something else"][results.count]
            if !seen.contains(fallback.lowercased()) {
                seen.insert(fallback.lowercased())
                results.append(fallback)
            }
        }

        return results
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
