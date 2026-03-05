import Foundation
import SwiftData

enum UsageContext: String, Codable, CaseIterable, Identifiable {
    case personal
    case work
    case education
    case other

    var id: String { rawValue }
}

enum DecisionStyle: String, Codable, CaseIterable, Identifiable {
    case analytical
    case intuitive
    case balanced

    var id: String { rawValue }
}

enum BiggestChallenge: String, Codable, CaseIterable, Identifiable {
    case overthinking
    case fear
    case tooManyOptions = "too_many_options"
    case lackOfInfo = "lack_of_info"

    var id: String { rawValue }
}

enum SpeedPreference: String, Codable, CaseIterable, Identifiable {
    case quick
    case deep
    case depends

    var id: String { rawValue }
}

enum AppearancePreference: String, Codable, CaseIterable, Identifiable {
    case light
    case dark
    case auto

    var id: String { rawValue }
}

enum DecisionCategory: String, Codable, CaseIterable, Identifiable {
    case career
    case finance
    case health
    case relationships
    case business
    case education
    case lifestyle
    case creativity

    var id: String { rawValue }
}

enum DecisionStatus: String, Codable, CaseIterable, Identifiable {
    case inProgress = "in_progress"
    case decided
    case pending
    case reviewDue = "review_due"

    var id: String { rawValue }
}

enum AIConfidence: String, Codable, CaseIterable, Identifiable {
    case low
    case medium
    case high

    var id: String { rawValue }
}

enum BiasChallengeType: String, Codable, CaseIterable, Identifiable {
    case friendTest = "friend_test"
    case tenTenTen = "ten_ten_ten"
    case preMortem = "pre_mortem"
    case worstCase = "worst_case"
    case inversion
    case inactionCost = "inaction_cost"
    case valuesCheck = "values_check"

    var id: String { rawValue }
}

enum MessageRole: String, Codable, CaseIterable, Hashable, Identifiable {
    case user
    case assistant

    var id: String { rawValue }
}

enum ChatCTAAction: String, Codable, CaseIterable, Hashable, Identifiable {
    case setupOptions

    var id: String { rawValue }
}

enum DecisionFramework: String, Codable, CaseIterable, Hashable, Identifiable {
    case friendTest
    case tenTenTen
    case regretMinimization
    case riskAssessment
    case opportunityCost
    case valuesAlignment
    case reversibility
    case costOfInaction
    case socialProof
    case energyTest

    var id: String { rawValue }
}

enum ChatConversationPhase: String, Codable, CaseIterable, Hashable, Identifiable {
    case opening
    case collecting
    case transitionReady
    case completed

    var id: String { rawValue }
}

enum ProjectStatus: String, Codable {
    case draft
    case final
}

enum ScoreSource: String, Codable {
    case manual
    case aiDraft
}

enum AttachmentKind: String, Codable {
    case file
    case link
}

enum AttachmentValidationStatus: String, Codable {
    case pending
    case ready
    case needsReview = "needs_review"
    case unreadable
}

enum AttachmentTrustLevel: String, Codable {
    case uploaded
    case official
    case known
    case external
    case unknown
}

struct VendorAttachment: Codable, Hashable, Identifiable {
    var id: String = UUID().uuidString
    var fileName: String
    var contentType: String
    var cloudPath: String
    var kindRaw: String = AttachmentKind.file.rawValue
    var statusRaw: String = AttachmentValidationStatus.pending.rawValue
    var trustLevelRaw: String = AttachmentTrustLevel.uploaded.rawValue
    var sourceHost: String = ""
    var titleHint: String = ""
    var validationMessage: String = ""

    var kind: AttachmentKind {
        get { AttachmentKind(rawValue: kindRaw) ?? .file }
        set { kindRaw = newValue.rawValue }
    }

    var status: AttachmentValidationStatus {
        get { AttachmentValidationStatus(rawValue: statusRaw) ?? .pending }
        set { statusRaw = newValue.rawValue }
    }

    var trustLevel: AttachmentTrustLevel {
        get { AttachmentTrustLevel(rawValue: trustLevelRaw) ?? .unknown }
        set { trustLevelRaw = newValue.rawValue }
    }

    enum CodingKeys: String, CodingKey {
        case id
        case fileName
        case contentType
        case cloudPath
        case kindRaw
        case statusRaw
        case trustLevelRaw
        case sourceHost
        case titleHint
        case validationMessage
    }

    init(
        id: String = UUID().uuidString,
        fileName: String,
        contentType: String,
        cloudPath: String,
        kind: AttachmentKind = .file,
        status: AttachmentValidationStatus = .pending,
        trustLevel: AttachmentTrustLevel = .uploaded,
        sourceHost: String = "",
        titleHint: String = "",
        validationMessage: String = ""
    ) {
        self.id = id
        self.fileName = fileName
        self.contentType = contentType
        self.cloudPath = cloudPath
        self.kindRaw = kind.rawValue
        self.statusRaw = status.rawValue
        self.trustLevelRaw = trustLevel.rawValue
        self.sourceHost = sourceHost
        self.titleHint = titleHint
        self.validationMessage = validationMessage
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decodeIfPresent(String.self, forKey: .id) ?? UUID().uuidString
        fileName = try container.decode(String.self, forKey: .fileName)
        contentType = try container.decode(String.self, forKey: .contentType)
        cloudPath = try container.decode(String.self, forKey: .cloudPath)
        kindRaw = try container.decodeIfPresent(String.self, forKey: .kindRaw) ?? AttachmentKind.file.rawValue
        statusRaw = try container.decodeIfPresent(String.self, forKey: .statusRaw) ?? AttachmentValidationStatus.pending.rawValue
        trustLevelRaw = try container.decodeIfPresent(String.self, forKey: .trustLevelRaw) ?? AttachmentTrustLevel.uploaded.rawValue
        sourceHost = try container.decodeIfPresent(String.self, forKey: .sourceHost) ?? ""
        titleHint = try container.decodeIfPresent(String.self, forKey: .titleHint) ?? ""
        validationMessage = try container.decodeIfPresent(String.self, forKey: .validationMessage) ?? ""
    }
}

struct SurveyQuestion: Identifiable {
    let id: String
    let title: String
    let options: [String]
}

struct SurveyAnswer: Codable, Hashable {
    var questionID: String
    var value: String
}

struct ClarifyingQuestionAnswer: Codable, Hashable, Identifiable {
    var id: String = UUID().uuidString
    var question: String
    var answer: String
}

enum DecisionOptionType: String, Codable, Hashable, CaseIterable, Identifiable {
    case candidate
    case offer
    case school
    case vendor
    case genericChoice = "generic_choice"

    var id: String { rawValue }
}

struct DecisionOptionSnapshot: Codable, Hashable, Identifiable {
    var id: String = UUID().uuidString
    var label: String
    var type: DecisionOptionType
    var description: String?
    var aiSuggested: Bool

    enum CodingKeys: String, CodingKey {
        case id
        case label
        case type
        case description
        case aiSuggested
    }

    private enum LegacyCodingKeys: String, CodingKey {
        case title
    }

    init(
        id: String = UUID().uuidString,
        label: String,
        type: DecisionOptionType = .genericChoice,
        description: String?,
        aiSuggested: Bool
    ) {
        self.id = id
        self.label = label
        self.type = type
        self.description = description
        self.aiSuggested = aiSuggested
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let legacy = try decoder.container(keyedBy: LegacyCodingKeys.self)
        id = try container.decodeIfPresent(String.self, forKey: .id) ?? UUID().uuidString
        let decodedLabel = try container.decodeIfPresent(String.self, forKey: .label)
            ?? legacy.decodeIfPresent(String.self, forKey: .title)
            ?? ""
        label = decodedLabel
        type = try container.decodeIfPresent(DecisionOptionType.self, forKey: .type)
            ?? Self.inferredType(from: decodedLabel)
        description = try container.decodeIfPresent(String.self, forKey: .description)
        aiSuggested = try container.decodeIfPresent(Bool.self, forKey: .aiSuggested) ?? true
    }

    var isExplicitNamed: Bool {
        let normalized = label.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !normalized.isEmpty else { return false }
        if normalized.hasPrefix("vendor ") || normalized.hasPrefix("option ") || normalized.hasPrefix("candidate ") {
            return false
        }
        return true
    }

    private static func inferredType(from label: String) -> DecisionOptionType {
        let lower = label.lowercased()
        if lower.contains("offer") || lower.contains("current job") || lower.contains("current role") {
            return .offer
        }
        if lower.contains("candidate") {
            return .candidate
        }
        if lower.contains("school") || lower.contains("university") || lower.contains("college") {
            return .school
        }
        if lower.contains("vendor") || lower.contains("provider") {
            return .vendor
        }
        return .genericChoice
    }
}

struct DecisionBrief: Codable, Hashable {
    var summary: String
    var inferredCategory: DecisionCategory
    var detectedOptions: [DecisionOptionSnapshot]
    var goals: [String]
    var constraints: [String]
    var risks: [String]
    var tensions: [String]
    var suggestedCriteria: [CriterionDraft]
}

enum ConstraintType: String, Codable, Hashable, CaseIterable, Identifiable {
    case minimumSalary = "minimum_salary"
    case location
    case visa
    case remote
    case custom

    var id: String { rawValue }
}

struct ConstraintFinding: Codable, Hashable, Identifiable {
    var id: String = UUID().uuidString
    var type: ConstraintType
    var rule: String
    var violatedOptionIDs: [String]
    var violatedOptionLabels: [String]
    var severity: String
}

struct DecisionReport: Codable, Hashable {
    var recommendation: String
    var drivers: [String]
    var risks: [String]
    var confidence: String
    var nextStep: String
    var biasChecks: [String]
}

struct DecisionChatOption: Codable, Hashable, Identifiable {
    var id: String = UUID().uuidString
    var index: Int
    var text: String
}

struct ChatMessageCTA: Codable, Hashable {
    var title: String
    var action: ChatCTAAction
}

struct DecisionChatMessage: Codable, Hashable, Identifiable {
    var id: String = UUID().uuidString
    var role: MessageRole
    var content: String
    var options: [DecisionChatOption]
    var allowSkip: Bool
    var allowsFreeformReply: Bool
    var cta: ChatMessageCTA?
    var framework: DecisionFramework?
    var createdAt: Date
    var isTypingPlaceholder: Bool
}

struct DecisionMatrixSetup: Codable, Hashable {
    var decisionBrief: DecisionBrief
    var suggestedOptions: [DecisionOptionSnapshot]
    var suggestedCriteria: [CriterionDraft]
}

struct DecisionConversationState: Codable, Hashable {
    var phase: ChatConversationPhase
    var frameworksUsed: [DecisionFramework]
}

struct DecisionConversationResponse: Codable, Hashable {
    var message: DecisionChatMessage
    var conversationState: DecisionConversationState
}

struct BiasChallengeResponse: Codable, Hashable, Identifiable {
    var id: String = UUID().uuidString
    var type: BiasChallengeType
    var question: String
    var response: String

    enum CodingKeys: String, CodingKey {
        case id
        case type
        case question
        case response
    }

    init(id: String = UUID().uuidString, type: BiasChallengeType, question: String, response: String) {
        self.id = id
        self.type = type
        self.question = question
        self.response = response
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decodeIfPresent(String.self, forKey: .id) ?? UUID().uuidString
        type = try container.decode(BiasChallengeType.self, forKey: .type)
        question = try container.decode(String.self, forKey: .question)
        response = try container.decodeIfPresent(String.self, forKey: .response) ?? ""
    }
}

struct VendorDraft: Identifiable, Hashable, Codable {
    var id: String = UUID().uuidString
    var name: String
    var notes: String
    var attachments: [VendorAttachment]
}

struct CriterionDraft: Identifiable, Hashable, Codable {
    var id: String = UUID().uuidString
    var name: String
    var detail: String
    var category: String
    var weightPercent: Double
}

struct ScoreDraft: Identifiable, Hashable, Codable {
    var id: String = UUID().uuidString
    var vendorID: String
    var criterionID: String
    var score: Double
    var source: ScoreSource
    var confidence: Double
    var evidenceSnippet: String
}

struct RankingDraft: Identifiable, Hashable, Codable {
    var id: String = UUID().uuidString
    var title: String
    var usageContext: UsageContext
    var category: DecisionCategory
    var contextNarrative: String
    var decisionBrief: DecisionBrief?
    var chatThreadID: String?
    var chatPhase: ChatConversationPhase
    var chatCompletedAt: Date?
    var conversationSummary: String
    var frameworksUsed: [DecisionFramework]
    var chatDerivedOptions: [DecisionOptionSnapshot]
    var chatDerivedCriteria: [CriterionDraft]
    var constraintFindings: [ConstraintFinding]?
    var decisionReport: DecisionReport?
    var alternativePathAnswer: String?
    var voiceInputURL: String?
    var contextAttachments: [VendorAttachment]
    var clarifyingQuestions: [ClarifyingQuestionAnswer]
    var vendors: [VendorDraft]
    var criteria: [CriterionDraft]
    var scores: [ScoreDraft]
    var biasChallenges: [BiasChallengeResponse]
    var postChallengeReassurance: String?
    var decisionStatus: DecisionStatus
    var chosenOptionID: String?
    var followUpDate: Date?
    var outcomeRating: Int?
    var outcomeNotes: String
    var lastUpdatedAt: Date

    static var empty: RankingDraft {
        RankingDraft(
            title: "Untitled Comparison",
            usageContext: .work,
            category: .business,
            contextNarrative: "",
            decisionBrief: nil,
            chatThreadID: nil,
            chatPhase: .opening,
            chatCompletedAt: nil,
            conversationSummary: "",
            frameworksUsed: [],
            chatDerivedOptions: [],
            chatDerivedCriteria: [],
            constraintFindings: [],
            decisionReport: nil,
            alternativePathAnswer: nil,
            voiceInputURL: nil,
            contextAttachments: [],
            clarifyingQuestions: [],
            vendors: [
                VendorDraft(name: "", notes: "", attachments: []),
                VendorDraft(name: "", notes: "", attachments: [])
            ],
            criteria: [
                CriterionDraft(name: "Cost", detail: "Overall expected cost", category: "Financial", weightPercent: 34),
                CriterionDraft(name: "Quality", detail: "Output and reliability", category: "Performance", weightPercent: 33),
                CriterionDraft(name: "Support", detail: "Availability and response time", category: "Operations", weightPercent: 33)
            ],
            scores: [],
            biasChallenges: [],
            postChallengeReassurance: nil,
            decisionStatus: .inProgress,
            chosenOptionID: nil,
            followUpDate: nil,
            outcomeRating: nil,
            outcomeNotes: "",
            lastUpdatedAt: .now
        )
    }
}

struct VendorResult: Hashable {
    var vendorID: String
    var vendorName: String
    var totalScore: Double
}

struct SensitivityFinding: Hashable {
    var criterionName: String
    var winnerFlipped: Bool
}

struct RankingResult: Hashable {
    var projectID: String
    var rankedVendors: [VendorResult]
    var winnerID: String?
    var confidenceScore: Double
    var tieDetected: Bool
    var sensitivityFindings: [SensitivityFinding]
}

struct InsightReportDraft: Hashable {
    var summary: String
    var winnerReasoning: String
    var riskFlags: [String]
    var overlookedStrategicPoints: [String]
    var sensitivityFindings: [String]
}

@Model
final class UserProfileEntity {
    @Attribute(.unique) var id: String
    var firstName: String
    var lastName: String
    var email: String
    var passwordHash: String
    var displayName: String
    var authProvidersCSV: String
    var primaryUsageRaw: String
    var decisionStyleRaw: String
    var biggestChallengeRaw: String
    var speedPreferenceRaw: String
    var valuesRankingJSON: String
    var interestsJSON: String
    var appearanceRaw: String
    var notificationsEnabled: Bool
    var followUpReminders: Bool
    var usageContextRaw: String
    var surveyAnswersJSON: String
    var decisionStyleTagsCSV: String
    var createdAt: Date
    var updatedAt: Date

    init(
        id: String,
        email: String,
        displayName: String,
        authProvidersCSV: String,
        usageContextRaw: String,
        surveyAnswersJSON: String,
        decisionStyleTagsCSV: String,
        firstName: String = "",
        lastName: String = "",
        passwordHash: String = "",
        primaryUsageRaw: String = "",
        decisionStyleRaw: String = DecisionStyle.balanced.rawValue,
        biggestChallengeRaw: String = BiggestChallenge.lackOfInfo.rawValue,
        speedPreferenceRaw: String = SpeedPreference.depends.rawValue,
        valuesRankingJSON: String = "[]",
        interestsJSON: String = "[]",
        appearanceRaw: String = AppearancePreference.auto.rawValue,
        notificationsEnabled: Bool = true,
        followUpReminders: Bool = true,
        createdAt: Date = .now,
        updatedAt: Date = .now
    ) {
        let nameParts = displayName.split(separator: " ").map(String.init)
        self.id = id
        self.firstName = firstName.isEmpty ? (nameParts.first ?? "") : firstName
        self.lastName = lastName.isEmpty ? (nameParts.dropFirst().joined(separator: " ")) : lastName
        self.email = email
        self.passwordHash = passwordHash
        self.displayName = displayName
        self.authProvidersCSV = authProvidersCSV
        self.primaryUsageRaw = primaryUsageRaw.isEmpty ? usageContextRaw : primaryUsageRaw
        self.decisionStyleRaw = decisionStyleRaw
        self.biggestChallengeRaw = biggestChallengeRaw
        self.speedPreferenceRaw = speedPreferenceRaw
        self.valuesRankingJSON = valuesRankingJSON
        self.interestsJSON = interestsJSON
        self.appearanceRaw = appearanceRaw
        self.notificationsEnabled = notificationsEnabled
        self.followUpReminders = followUpReminders
        self.usageContextRaw = usageContextRaw
        self.surveyAnswersJSON = surveyAnswersJSON
        self.decisionStyleTagsCSV = decisionStyleTagsCSV
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}

@Model
final class RankingProjectEntity {
    @Attribute(.unique) var id: String
    var ownerUserID: String
    var title: String
    var statusRaw: String
    var usageContextRaw: String
    var situationText: String
    var categoryRaw: String
    var voiceInputURL: String
    var clarifyingQuestionsJSON: String
    var optionsJSON: String
    var biasChallengesJSON: String
    var vendorCount: Int
    var criteriaCount: Int
    var winningVendorID: String
    var confidenceScore: Double
    var aiRecommendation: String
    var aiTradeOffs: String
    var aiBlindSpots: String
    var aiGutCheck: String
    var aiNextStep: String
    var aiConfidenceRaw: String
    var chosenOptionID: String
    var followUpDate: Date?
    var outcomeRating: Int?
    var outcomeNotes: String
    var createdAt: Date
    var updatedAt: Date
    var lastComputedAt: Date

    init(
        id: String,
        ownerUserID: String,
        title: String,
        statusRaw: String,
        usageContextRaw: String,
        situationText: String = "",
        categoryRaw: String = DecisionCategory.business.rawValue,
        voiceInputURL: String = "",
        clarifyingQuestionsJSON: String = "[]",
        optionsJSON: String = "[]",
        biasChallengesJSON: String = "[]",
        vendorCount: Int,
        criteriaCount: Int,
        winningVendorID: String,
        confidenceScore: Double,
        aiRecommendation: String = "",
        aiTradeOffs: String = "",
        aiBlindSpots: String = "",
        aiGutCheck: String = "",
        aiNextStep: String = "",
        aiConfidenceRaw: String = AIConfidence.medium.rawValue,
        chosenOptionID: String = "",
        followUpDate: Date? = nil,
        outcomeRating: Int? = nil,
        outcomeNotes: String = "",
        createdAt: Date = .now,
        updatedAt: Date = .now,
        lastComputedAt: Date = .now
    ) {
        self.id = id
        self.ownerUserID = ownerUserID
        self.title = title
        self.statusRaw = statusRaw
        self.usageContextRaw = usageContextRaw
        self.situationText = situationText
        self.categoryRaw = categoryRaw
        self.voiceInputURL = voiceInputURL
        self.clarifyingQuestionsJSON = clarifyingQuestionsJSON
        self.optionsJSON = optionsJSON
        self.biasChallengesJSON = biasChallengesJSON
        self.vendorCount = vendorCount
        self.criteriaCount = criteriaCount
        self.winningVendorID = winningVendorID
        self.confidenceScore = confidenceScore
        self.aiRecommendation = aiRecommendation
        self.aiTradeOffs = aiTradeOffs
        self.aiBlindSpots = aiBlindSpots
        self.aiGutCheck = aiGutCheck
        self.aiNextStep = aiNextStep
        self.aiConfidenceRaw = aiConfidenceRaw
        self.chosenOptionID = chosenOptionID
        self.followUpDate = followUpDate
        self.outcomeRating = outcomeRating
        self.outcomeNotes = outcomeNotes
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.lastComputedAt = lastComputedAt
    }
}

@Model
final class VendorEntity {
    @Attribute(.unique) var id: String
    var projectID: String
    var name: String
    var notes: String
    var attachmentsJSON: String

    init(id: String, projectID: String, name: String, notes: String, attachmentsJSON: String) {
        self.id = id
        self.projectID = projectID
        self.name = name
        self.notes = notes
        self.attachmentsJSON = attachmentsJSON
    }
}

@Model
final class CriterionEntity {
    @Attribute(.unique) var id: String
    var projectID: String
    var name: String
    var detail: String
    var category: String
    var weightPercent: Double

    init(id: String, projectID: String, name: String, detail: String, category: String, weightPercent: Double) {
        self.id = id
        self.projectID = projectID
        self.name = name
        self.detail = detail
        self.category = category
        self.weightPercent = weightPercent
    }
}

@Model
final class ScoreEntryEntity {
    @Attribute(.unique) var id: String
    var projectID: String
    var vendorID: String
    var criterionID: String
    var score: Double
    var sourceRaw: String
    var confidence: Double
    var evidenceSnippet: String

    init(
        id: String,
        projectID: String,
        vendorID: String,
        criterionID: String,
        score: Double,
        sourceRaw: String,
        confidence: Double,
        evidenceSnippet: String
    ) {
        self.id = id
        self.projectID = projectID
        self.vendorID = vendorID
        self.criterionID = criterionID
        self.score = score
        self.sourceRaw = sourceRaw
        self.confidence = confidence
        self.evidenceSnippet = evidenceSnippet
    }
}

@Model
final class InsightReportEntity {
    @Attribute(.unique) var id: String
    var projectID: String
    var summary: String
    var winnerReasoning: String
    var riskFlagsJSON: String
    var overlookedStrategicPointsJSON: String
    var sensitivityFindingsJSON: String

    init(
        id: String,
        projectID: String,
        summary: String,
        winnerReasoning: String,
        riskFlagsJSON: String,
        overlookedStrategicPointsJSON: String,
        sensitivityFindingsJSON: String
    ) {
        self.id = id
        self.projectID = projectID
        self.summary = summary
        self.winnerReasoning = winnerReasoning
        self.riskFlagsJSON = riskFlagsJSON
        self.overlookedStrategicPointsJSON = overlookedStrategicPointsJSON
        self.sensitivityFindingsJSON = sensitivityFindingsJSON
    }
}

@Model
final class ChatThreadEntity {
    @Attribute(.unique) var id: String
    var projectID: String
    var phaseRaw: String
    var isComplete: Bool
    var projectTitle: String
    var lastMessageAt: Date
    var frameworksJSON: String
    var createdAt: Date

    init(
        id: String,
        projectID: String,
        phaseRaw: String = ChatConversationPhase.opening.rawValue,
        isComplete: Bool = false,
        projectTitle: String = "",
        lastMessageAt: Date = .now,
        frameworksJSON: String = "[]",
        createdAt: Date = .now
    ) {
        self.id = id
        self.projectID = projectID
        self.phaseRaw = phaseRaw
        self.isComplete = isComplete
        self.projectTitle = projectTitle
        self.lastMessageAt = lastMessageAt
        self.frameworksJSON = frameworksJSON
        self.createdAt = createdAt
    }
}

@Model
final class ChatMessageEntity {
    @Attribute(.unique) var id: String
    var threadID: String
    var role: String
    var content: String
    var optionsJSON: String
    var allowSkip: Bool
    var allowsFreeformReply: Bool
    var ctaJSON: String
    var frameworkRaw: String?
    var sequenceNumber: Int
    var isTypingPlaceholder: Bool
    var createdAt: Date

    init(
        id: String,
        threadID: String,
        role: String,
        content: String,
        optionsJSON: String = "[]",
        allowSkip: Bool = false,
        allowsFreeformReply: Bool = false,
        ctaJSON: String = "",
        frameworkRaw: String? = nil,
        sequenceNumber: Int = 0,
        isTypingPlaceholder: Bool = false,
        createdAt: Date = .now
    ) {
        self.id = id
        self.threadID = threadID
        self.role = role
        self.content = content
        self.optionsJSON = optionsJSON
        self.allowSkip = allowSkip
        self.allowsFreeformReply = allowsFreeformReply
        self.ctaJSON = ctaJSON
        self.frameworkRaw = frameworkRaw
        self.sequenceNumber = sequenceNumber
        self.isTypingPlaceholder = isTypingPlaceholder
        self.createdAt = createdAt
    }
}

@Model
final class ProjectVersionEntity {
    @Attribute(.unique) var id: String
    var projectID: String
    var versionNumber: Int
    var snapshotJSON: String
    var createdAt: Date

    init(id: String, projectID: String, versionNumber: Int, snapshotJSON: String, createdAt: Date = .now) {
        self.id = id
        self.projectID = projectID
        self.versionNumber = versionNumber
        self.snapshotJSON = snapshotJSON
        self.createdAt = createdAt
    }
}
