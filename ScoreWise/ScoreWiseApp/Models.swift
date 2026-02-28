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

struct DecisionOptionSnapshot: Codable, Hashable, Identifiable {
    var id: String = UUID().uuidString
    var label: String
    var description: String?
    var aiSuggested: Bool

    enum CodingKeys: String, CodingKey {
        case id
        case label
        case description
        case aiSuggested
    }

    init(id: String = UUID().uuidString, label: String, description: String?, aiSuggested: Bool) {
        self.id = id
        self.label = label
        self.description = description
        self.aiSuggested = aiSuggested
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decodeIfPresent(String.self, forKey: .id) ?? UUID().uuidString
        label = try container.decode(String.self, forKey: .label)
        description = try container.decodeIfPresent(String.self, forKey: .description)
        aiSuggested = try container.decodeIfPresent(Bool.self, forKey: .aiSuggested) ?? true
    }
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
    var voiceInputURL: String?
    var contextAttachments: [VendorAttachment]
    var clarifyingQuestions: [ClarifyingQuestionAnswer]
    var vendors: [VendorDraft]
    var criteria: [CriterionDraft]
    var scores: [ScoreDraft]
    var biasChallenges: [BiasChallengeResponse]
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
            voiceInputURL: nil,
            contextAttachments: [],
            clarifyingQuestions: [],
            vendors: [
                VendorDraft(name: "Vendor A", notes: "", attachments: []),
                VendorDraft(name: "Vendor B", notes: "", attachments: [])
            ],
            criteria: [
                CriterionDraft(name: "Cost", detail: "Overall expected cost", category: "Financial", weightPercent: 34),
                CriterionDraft(name: "Quality", detail: "Output and reliability", category: "Performance", weightPercent: 33),
                CriterionDraft(name: "Support", detail: "Availability and response time", category: "Operations", weightPercent: 33)
            ],
            scores: [],
            biasChallenges: [],
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
    var createdAt: Date

    init(id: String, projectID: String, createdAt: Date = .now) {
        self.id = id
        self.projectID = projectID
        self.createdAt = createdAt
    }
}

@Model
final class ChatMessageEntity {
    @Attribute(.unique) var id: String
    var threadID: String
    var role: String
    var content: String
    var createdAt: Date

    init(id: String, threadID: String, role: String, content: String, createdAt: Date = .now) {
        self.id = id
        self.threadID = threadID
        self.role = role
        self.content = content
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
