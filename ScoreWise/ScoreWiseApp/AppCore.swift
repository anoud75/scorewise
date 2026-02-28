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
    enum Screen {
        case launch
        case auth
        case onboarding
        case postSurveySplash
        case home
        case history
        case ranking
        case results
        case profile
    }

    @Published var screen: Screen = .launch
    @Published var session: AuthSession?
    @Published var onboardingAnswers: [SurveyAnswer] = []
    @Published var activeDraft: RankingDraft = .empty
    @Published var activeResult: RankingResult?
    @Published var activeInsight: InsightReportDraft?
    @Published var recentProjects: [RankingProjectEntity] = []
    @Published var chatMessages: [ChatMessageDraft] = []
    @Published var busyMessage: String?
    @Published var lastError: String?
    @Published var userValuesRanking: [String] = []
    @Published var userInterests: [String] = []
    @Published var expressModeEnabled = false

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

    func bootstrap() {
        Task {
            session = await services.auth.restoreSession()
            if session == nil {
                screen = .auth
            } else {
                screen = .onboarding
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

    private func signIn(_ work: @escaping () async throws -> AuthSession) async {
        do {
            busyMessage = "Signing in..."
            session = try await work()
            busyMessage = nil
            screen = .onboarding
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

    func startNewComparison() {
        activeDraft = .empty
        activeResult = nil
        activeInsight = nil
        chatMessages.removeAll()
        screen = .ranking
    }

    func setExpressMode(_ enabled: Bool) {
        expressModeEnabled = enabled && expressModeAvailable
    }

    func prepareClarifyingQuestions() {
        guard !activeDraft.contextNarrative.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        if activeDraft.clarifyingQuestions.count == 3, activeDraft.clarifyingQuestions.allSatisfy({ !$0.question.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }) {
            return
        }

        Task {
            do {
                busyMessage = "Preparing clarifying questions..."
                let questions = try await services.ai.generateClarifyingQuestions(for: activeDraft, userProfile: userAIProfile)
                let normalized = Array(questions.prefix(3))
                if normalized.count == 3 {
                    activeDraft.clarifyingQuestions = normalized
                }
                busyMessage = nil
            } catch {
                busyMessage = nil
                lastError = error.localizedDescription
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
            ? (activeResult?.rankedVendors.first?.vendorName ?? activeDraft.vendors.first?.name ?? "Option A")
            : trimmedPreferred

        Task {
            do {
                busyMessage = "Preparing challenge prompts..."
                let challenges = try await services.ai.generateBiasChallenges(for: activeDraft, preferredOption: optionName, userProfile: userAIProfile)
                let normalized = Array(challenges.prefix(3))
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
        Task {
            do {
                try await generateAISuggestions()
                busyMessage = nil
            } catch {
                busyMessage = nil
                lastError = error.localizedDescription
            }
        }
    }

    func runExpressAnalysis() {
        Task {
            do {
                busyMessage = "Preparing quick clarity..."
                if activeDraft.vendors.allSatisfy({ $0.name.hasPrefix("Vendor ") || $0.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }) {
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
            try services.persistence.saveProjectDraft(activeDraft, result: activeResult, insight: activeInsight, context: modelContext)
            let owner = session?.userID ?? "local"
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
            recentProjects = []
            userValuesRanking = []
            userInterests = []
            expressModeEnabled = false
            screen = .auth
        }
    }

    func setDecisionOutcome(decided: Bool) {
        activeDraft.decisionStatus = decided ? .decided : .pending
        activeDraft.chosenOptionID = decided ? activeResult?.winnerID : nil
        activeDraft.lastUpdatedAt = .now
    }

    func setFollowUpReminder(enabled: Bool) {
        activeDraft.followUpDate = enabled ? Calendar.current.date(byAdding: .day, value: 30, to: .now) : nil
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
        busyMessage = "Generating AI suggestions..."
        let allAttachments = activeDraft.contextAttachments + activeDraft.vendors.flatMap(\.attachments)
        let extractedEvidence = try await services.extractor.extractEvidence(for: allAttachments)
        applyEvidenceMetadata(extractedEvidence)
        let suggestion = try await services.ai.suggestRankingInputs(
            for: activeDraft,
            context: activeDraft.usageContext,
            extractedEvidence: extractedEvidence.map(\.extractedText).filter { !$0.isEmpty },
            userProfile: userAIProfile
        )
        activeDraft.criteria = RankingEngine.normalizedCriteria(suggestion.criteria)
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
    }

    private func mergeSuggestedOptions(_ options: [DecisionOptionSnapshot]) {
        var remainingExisting = activeDraft.vendors
        var merged: [VendorDraft] = []

        for suggestion in options.prefix(8) {
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

    private func normalizedOptionName(_ name: String) -> String {
        name
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
    }

    private func isPlaceholderVendor(_ vendor: VendorDraft) -> Bool {
        let name = normalizedOptionName(vendor.name)
        return name.isEmpty || name.hasPrefix("vendor ") || name.hasPrefix("option ")
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
    var nonEmpty: String? {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}

private extension Array {
    var isNotEmpty: Bool { !isEmpty }
}
