import Foundation

struct DecisionEngine {
    static let shared = DecisionEngine()

    let knowledgeBase = DecisionKnowledgeBase.shared
    let situationParser = SituationParser()
    let optionExtractor = OptionExtractor()
    let constraintDetector = ConstraintDetector()
    let clarifyingQuestionGenerator = ClarifyingQuestionGenerator()
    let criteriaGenerator = CriteriaGenerator()
    let weightEngine = WeightEngine()
    let matrixBuilder = MatrixBuilder()
    let autoScoringEngine = AutoScoringEngine()
    let resultInterpreter = ResultInterpreter()
    let biasDetector = BiasDetector()
    let recommendationEngine = RecommendationEngine()
    let decisionReportGenerator = DecisionReportGenerator()

    func parse(draft: RankingDraft, extractedEvidence: [String], userProfile: AIUserProfile?) -> ParsedSituation {
        let parsed = situationParser.parse(draft: draft, extractedEvidence: extractedEvidence)
        let extracted = optionExtractor.extract(from: parsed, draft: draft, userProfile: userProfile)
        let comparableCheck = optionExtractor.comparableCheck(for: extracted, recruiterMode: parsed.isRecruiterMode)
        return ParsedSituation(
            narrative: parsed.narrative,
            combinedContext: parsed.combinedContext,
            inferredCategory: parsed.inferredCategory,
            usageContext: parsed.usageContext,
            isRecruiterMode: parsed.isRecruiterMode,
            explicitOptions: extracted,
            comparableOptionCheck: comparableCheck
        )
    }

    func validateOptionScope(draft: RankingDraft, userProfile: AIUserProfile?) -> OptionScopeValidation {
        let parsed = parse(draft: draft, extractedEvidence: [], userProfile: userProfile)
        let explicitNamed = parsed.explicitOptions.filter(\.isExplicitNamed)
        guard explicitNamed.count >= 2 else {
            return OptionScopeValidation(
                isValid: false,
                message: "Add at least 2 explicit named options before weighted scoring.",
                missingCount: max(0, 2 - explicitNamed.count),
                invalidReasons: ["Need at least 2 explicit named options."]
            )
        }

        if !parsed.comparableOptionCheck.comparable {
            let reasons = parsed.comparableOptionCheck.violations
            return OptionScopeValidation(
                isValid: false,
                message: "Options must be comparable types. Remove mixed strategy/process options.",
                missingCount: 0,
                invalidReasons: reasons
            )
        }

        return .empty
    }

    func detectConstraints(draft: RankingDraft, parsed: ParsedSituation? = nil) -> [ConstraintFinding] {
        let resolved = parsed ?? parse(draft: draft, extractedEvidence: [], userProfile: nil)
        return constraintDetector.detect(from: resolved, draft: draft)
    }

    func buildDecisionBrief(draft: RankingDraft, extractedEvidence: [String], userProfile: AIUserProfile?) -> DecisionBrief {
        let parsed = parse(draft: draft, extractedEvidence: extractedEvidence, userProfile: userProfile)
        let constraints = constraintDetector.detect(from: parsed, draft: draft)
        let criteria = weightEngine.normalize(
            criteriaGenerator.generate(
                from: parsed,
                constraints: constraints,
                userProfile: userProfile
            ),
            userProfile: userProfile,
            constraints: constraints
        )

        let goals = defaultGoals(parsed: parsed, userProfile: userProfile)
        let tensions = defaultTensions(parsed: parsed)
        let risks = defaultRisks(parsed: parsed, constraints: constraints)

        let summary = """
        Decision summary: \(parsed.explicitOptions.map(\.label).joined(separator: " vs ")).
        Priority focus: \(goals.first ?? "balance upside and downside").
        """

        return DecisionBrief(
            summary: summary,
            inferredCategory: parsed.inferredCategory,
            detectedOptions: parsed.explicitOptions,
            goals: goals,
            constraints: constraints.map(\.rule),
            risks: risks,
            tensions: tensions,
            suggestedCriteria: criteria
        )
    }

    func generateClarifyingQuestions(draft: RankingDraft, userProfile: AIUserProfile?) -> [ClarifyingQuestionAnswer] {
        let parsed = parse(draft: draft, extractedEvidence: [], userProfile: userProfile)
        let constraints = detectConstraints(draft: draft, parsed: parsed)
        return clarifyingQuestionGenerator.generate(
            from: parsed,
            constraints: constraints,
            userProfile: userProfile
        )
    }

    func buildSuggestedInputs(
        draft: RankingDraft,
        context: UsageContext,
        extractedEvidence: [String],
        userProfile: AIUserProfile?
    ) -> AISuggestedInputs {
        let brief = buildDecisionBrief(draft: draft, extractedEvidence: extractedEvidence, userProfile: userProfile)
        let constraints = detectConstraints(draft: draft, parsed: parse(draft: draft, extractedEvidence: extractedEvidence, userProfile: userProfile))
        let criteria = weightEngine.normalize(brief.suggestedCriteria, userProfile: userProfile, constraints: constraints)
        let scores = matrixBuilder.buildScores(
            draft: draft,
            criteria: criteria,
            constraints: constraints,
            autoScoringEngine: autoScoringEngine
        )
        return AISuggestedInputs(criteria: criteria, draftScores: scores)
    }

    func buildDecisionReport(draft: RankingDraft, result: RankingResult, userProfile: AIUserProfile?) -> DecisionReport {
        let constraints = detectConstraints(draft: draft)
        let interpreted = resultInterpreter.interpret(draft: draft, result: result, constraints: constraints)
        let biases = biasDetector.detect(draft: draft, result: result, userProfile: userProfile)
        let recommendation = recommendationEngine.recommend(draft: draft, result: result, interpreted: interpreted, constraints: constraints)
        return decisionReportGenerator.generate(
            recommendation: recommendation,
            interpreted: interpreted,
            biases: biases
        )
    }

    func buildInsightReport(draft: RankingDraft, result: RankingResult, userProfile: AIUserProfile?) -> InsightReportDraft {
        let report = buildDecisionReport(draft: draft, result: result, userProfile: userProfile)
        return InsightReportDraft(
            summary: report.drivers.joined(separator: "\n"),
            winnerReasoning: report.recommendation,
            riskFlags: report.risks,
            overlookedStrategicPoints: [report.nextStep],
            sensitivityFindings: report.biasChecks + [report.confidence],
            drivers: report.drivers,
            confidenceLabel: report.confidence,
            nextStep: report.nextStep
        )
    }

    func chatResponse(
        projectID: String,
        phase: String,
        message: String,
        draft: RankingDraft?,
        userProfile: AIUserProfile?
    ) -> AIChatResponse {
        guard let draft else {
            return AIChatResponse(
                content: "Recommendation\nI need your actual options and one non-negotiable constraint first.\n\nWhy this option leads\nNot enough context yet.\n\nRisks to consider\nUnknown constraints.\n\nConfidence level\nLow\n\nNext step\nShare the decision and at least 2 explicit options.",
                recommendedActions: [
                    "State the exact options you are comparing.",
                    "Add one hard constraint.",
                    "Add one primary success metric."
                ]
            )
        }

        if phase == "post_challenge_reassurance" {
            let winner = RankingEngine.computeResult(for: draft).rankedVendors.first?.vendorName ?? "the leading option"
            return AIChatResponse(
                content: "Recommendation\n\(winner)\n\nWhy this option leads\nYour challenge-check answers still align with the highest-weighted evidence.\n\nRisks to consider\nOne or two assumptions are still unverified.\n\nConfidence level\nMedium\n\nNext step\nRun one validation check this week, then finalize.",
                recommendedActions: [
                    "Validate one key assumption.",
                    "Set a final decision date."
                ]
            )
        }

        let result = draft.criteria.isEmpty || draft.scores.isEmpty ? nil : RankingEngine.computeResult(for: draft)
        guard let result else {
            return AIChatResponse(
                content: "Recommendation\nNot ready yet\n\nWhy this option leads\nThe matrix is not complete.\n\nRisks to consider\nWithout weighted scores, the choice is narrative-driven only.\n\nConfidence level\nLow\n\nNext step\nComplete criteria, weights, and initial scores first.",
                recommendedActions: [
                    "Complete weighted scoring.",
                    "Check constraints against each option."
                ]
            )
        }

        let report = buildDecisionReport(draft: draft, result: result, userProfile: userProfile)
        let content = """
        Recommendation
        \(report.recommendation)

        Why this option leads
        \(report.drivers.first ?? "Highest weighted criteria support the lead.")

        Risks to consider
        \(report.risks.first ?? "One assumption can still shift the result.")

        Confidence level
        \(report.confidence)

        Next step
        \(report.nextStep)
        """

        let actions = (report.risks.prefix(2) + [report.nextStep]).uniqued()
        return AIChatResponse(content: content, recommendedActions: actions)
    }

    private func defaultGoals(parsed: ParsedSituation, userProfile: AIUserProfile?) -> [String] {
        var goals: [String] = []
        if parsed.isRecruiterMode {
            goals.append("Select the candidate with the strongest role fit and execution reliability.")
        }
        if parsed.inferredCategory == .career {
            goals.append("Balance growth, compensation, and trajectory.")
        }
        if let top = userProfile?.valuesRanking.first, top.trimmed.isNotEmpty {
            goals.append("Protect \(top.lowercased()).")
        }
        if goals.isEmpty {
            goals.append("Make the most defensible choice under your constraints.")
        }
        return goals
    }

    private func defaultTensions(parsed: ParsedSituation) -> [String] {
        if parsed.explicitOptions.count >= 2 {
            return ["\(parsed.explicitOptions[0].label) versus \(parsed.explicitOptions[1].label) on your highest-priority criteria."]
        }
        return ["Certainty versus upside."]
    }

    private func defaultRisks(parsed: ParsedSituation, constraints: [ConstraintFinding]) -> [String] {
        var risks: [String] = []
        if constraints.contains(where: { !$0.violatedOptionIDs.isEmpty }) {
            risks.append("At least one option violates a hard constraint.")
        }
        if parsed.combinedContext.lowercased().contains("dream company") || parsed.combinedContext.lowercased().contains("prestige") {
            risks.append("Prestige bias may distort role-fit weighting.")
        }
        if risks.isEmpty {
            risks.append("One high-weight criterion may be overweighted relative to evidence quality.")
        }
        return risks
    }
}

struct DecisionKnowledgeBase {
    static let shared = DecisionKnowledgeBase()

    let recruiterRules: [KnowledgeRule] = [
        KnowledgeRule(scope: "constraints", triggerTerms: ["visa", "sponsorship"], outputHint: "Treat visa mismatch as hard constraint."),
        KnowledgeRule(scope: "criteria", triggerTerms: ["candidate", "role fit"], outputHint: "Prioritize role fit, execution evidence, and risk."),
        KnowledgeRule(scope: "bias", triggerTerms: ["prestige", "brand"], outputHint: "Flag halo/prestige bias.")
    ]

    let individualRules: [KnowledgeRule] = [
        KnowledgeRule(scope: "constraints", triggerTerms: ["minimum salary", "cannot go below"], outputHint: "Treat compensation floor as hard gate."),
        KnowledgeRule(scope: "criteria", triggerTerms: ["offer", "current job"], outputHint: "Prioritize fit, growth, compensation, and reversibility."),
        KnowledgeRule(scope: "bias", triggerTerms: ["dream company", "fear"], outputHint: "Check prestige bias and loss aversion.")
    ]

    func rules(for parsed: ParsedSituation) -> [KnowledgeRule] {
        parsed.isRecruiterMode ? recruiterRules : individualRules
    }
}

struct ClarifyingQuestionGenerator {
    func generate(from parsed: ParsedSituation, constraints: [ConstraintFinding], userProfile: AIUserProfile?) -> [ClarifyingQuestionAnswer] {
        let options = Array(parsed.explicitOptions.filter(\.isExplicitNamed).prefix(2)).map(\.label)
        let optionA = options.first ?? "the first option"
        let optionB = options.dropFirst().first ?? "the second option"
        let topValue = userProfile?.valuesRanking.first?.lowercased() ?? "your top priority"
        let salaryRule = constraints.first(where: { $0.type == .minimumSalary })?.rule

        var questions: [String] = [
            "Is your goal immediate stability or long-term upside? (Stability / Upside)",
            "If choosing now, do you pick \(optionA) or \(optionB)? (\(optionA) / \(optionB))",
            "Which is less acceptable now: lower pay or lower growth? (Lower pay / Lower growth)",
            "Do you require a reversible choice even with lower upside? (Yes / No)",
            "Should any hard-constraint violation auto-eliminate an option? (Yes / No)",
            "What should weigh more: role fit or prestige signal? (Role fit / Prestige)",
            "Do you prefer faster decision speed over higher certainty? (Faster / Certainty)",
            "If evidence is mixed, should tie-breaker be \(topValue) or risk control? (\(topValue.capitalized) / Risk)"
        ]

        if let salaryRule {
            questions.insert("Is this non-negotiable: \(salaryRule)? (Yes / No)", at: 2)
        }

        if parsed.isRecruiterMode {
            questions = [
                "Is direct role-fit more important than pedigree? (Yes / No)",
                "Should failing must-have skills auto-exclude a candidate? (Yes / No)",
                "What is stronger tie-breaker: interview signal or role evidence? (Interview / Role evidence)",
                "Is compensation fit a hard gate for shortlist approval? (Yes / No)",
                "Do you prioritize time-to-fill over upside potential? (Time-to-fill / Upside)",
                "Should location or visa mismatch auto-exclude candidates? (Yes / No)",
                "Should team-fit weight equal technical-fit weight? (Equal / Not equal)",
                "Would you accept lower confidence to close faster? (Yes / No)"
            ]
        }

        return Array(questions.prefix(12)).map { question in
            let compact = String(question.prefix(140)).trimmingCharacters(in: .whitespacesAndNewlines)
            return ClarifyingQuestionAnswer(question: compact, answer: "")
        }
    }
}

struct CriteriaGenerator {
    func generate(from parsed: ParsedSituation, constraints: [ConstraintFinding], userProfile: AIUserProfile?) -> [CriterionDraft] {
        var criteria: [CriterionDraft] = []

        func add(_ name: String, _ detail: String, _ category: String, _ weight: Double) {
            guard !criteria.contains(where: { $0.name.caseInsensitiveCompare(name) == .orderedSame }) else { return }
            criteria.append(CriterionDraft(name: name, detail: detail, category: category, weightPercent: weight))
        }

        if parsed.isRecruiterMode {
            add("Role fit", "Match to core responsibilities and level", "Hiring", 24)
            add("Execution evidence", "Evidence the candidate can deliver in this exact context", "Hiring", 19)
            add("Compensation fit", "Alignment with compensation constraints", "Financial", 14)
            add("Team collaboration", "Cross-functional communication and team compatibility", "Team", 14)
            add("Ramp speed", "Expected time to productive contribution", "Delivery", 13)
            add("Retention risk", "Risk of mismatch or short tenure", "Risk", 16)
        } else if parsed.inferredCategory == .career {
            add("Compensation & benefits", "Financial package versus baseline constraints", "Financial", 20)
            add("Role fit", "How well day-to-day work matches your target path", "Career", 20)
            add("Growth trajectory", "Long-term progression and learning upside", "Growth", 19)
            add("Work model & location", "Remote/hybrid/on-site fit with practical constraints", "Lifestyle", 14)
            add("Risk & reversibility", "Downside if this choice is wrong and recovery cost", "Risk", 14)
            add("Brand & signaling value", "External signaling value without over-weighting prestige", "Strategy", 13)
        } else {
            add("Expected outcome quality", "Likelihood of achieving the desired outcome", "Outcome", 24)
            add("Cost & effort", "Total cost, complexity, and effort to execute", "Financial", 19)
            add("Risk exposure", "Main downside scenarios and severity", "Risk", 17)
            add("Time to value", "How quickly the option starts delivering value", "Execution", 15)
            add("Flexibility", "Ability to adjust or reverse if assumptions fail", "Strategy", 13)
            add("Evidence strength", "How well current evidence supports this option", "Evidence", 12)
        }

        if constraints.contains(where: { $0.severity == "hard_violation" }) {
            add("Constraint compliance", "Hard-rule adherence before weighted comparison", "Gating", 18)
        }

        return Array(criteria.prefix(8))
    }
}

struct WeightEngine {
    func normalize(_ criteria: [CriterionDraft], userProfile: AIUserProfile?, constraints: [ConstraintFinding]) -> [CriterionDraft] {
        guard !criteria.isEmpty else { return [] }
        var adjusted = criteria
        let topValue = userProfile?.valuesRanking.first?.lowercased() ?? ""

        for index in adjusted.indices {
            let name = adjusted[index].name.lowercased()
            if name.contains("constraint") && constraints.contains(where: { $0.severity == "hard_violation" || !$0.violatedOptionIDs.isEmpty }) {
                adjusted[index].weightPercent += 8
            }
            if topValue.contains("growth"), name.contains("growth") {
                adjusted[index].weightPercent += 6
            }
            if topValue.contains("security"), (name.contains("risk") || name.contains("constraint")) {
                adjusted[index].weightPercent += 6
            }
            if topValue.contains("freedom"), (name.contains("flexibility") || name.contains("reversibility") || name.contains("work model")) {
                adjusted[index].weightPercent += 6
            }
            if topValue.contains("achievement"), (name.contains("outcome") || name.contains("role fit")) {
                adjusted[index].weightPercent += 6
            }
        }

        return RankingEngine.normalizedCriteria(adjusted)
    }
}

struct MatrixBuilder {
    func buildScores(
        draft: RankingDraft,
        criteria: [CriterionDraft],
        constraints: [ConstraintFinding],
        autoScoringEngine: AutoScoringEngine
    ) -> [ScoreDraft] {
        var scores: [ScoreDraft] = []
        for vendor in draft.vendors {
            for criterion in criteria {
                scores.append(
                    autoScoringEngine.score(
                        draft: draft,
                        vendor: vendor,
                        criterion: criterion,
                        constraints: constraints
                    )
                )
            }
        }
        return scores
    }
}

struct AutoScoringEngine {
    func score(draft: RankingDraft, vendor: VendorDraft, criterion: CriterionDraft, constraints: [ConstraintFinding]) -> ScoreDraft {
        let vendorBlob = [vendor.name, vendor.notes, draft.contextNarrative]
            .joined(separator: " ")
            .lowercased()
        let criterionKey = criterion.name.lowercased()
        let positiveSignals = signals(for: criterionKey)
        let hits = positiveSignals.reduce(into: 0) { count, signal in
            if vendorBlob.contains(signal) { count += 1 }
        }

        let hardViolation = constraints.contains(where: { $0.violatedOptionIDs.contains(vendor.id) && $0.severity == "hard_violation" })
        let base = 5.8
        let score = min(max(base + Double(hits) * 0.55 - (hardViolation ? 2.3 : 0), 1.0), 9.6)
        let confidence = min(max(0.58 + Double(vendor.attachments.count) * 0.06 + (hardViolation ? -0.08 : 0), 0.45), 0.92)
        let evidence = hardViolation
            ? "Potential constraint conflict found for this option."
            : "Draft score inferred from provided context and option notes."

        return ScoreDraft(
            vendorID: vendor.id,
            criterionID: criterion.id,
            score: (score * 10).rounded() / 10,
            source: .aiDraft,
            confidence: confidence,
            evidenceSnippet: evidence
        )
    }

    private func signals(for criterionKey: String) -> [String] {
        if criterionKey.contains("compensation") || criterionKey.contains("cost") {
            return ["salary", "compensation", "benefits", "cost", "package", "budget"]
        }
        if criterionKey.contains("growth") || criterionKey.contains("trajectory") {
            return ["growth", "learning", "trajectory", "promotion", "progression", "upside"]
        }
        if criterionKey.contains("role fit") || criterionKey.contains("fit") {
            return ["fit", "aligned", "role", "responsibility", "scope", "relevant"]
        }
        if criterionKey.contains("risk") || criterionKey.contains("constraint") {
            return ["risk", "safe", "stability", "uncertain", "constraint", "violate"]
        }
        if criterionKey.contains("work model") || criterionKey.contains("location") {
            return ["remote", "hybrid", "onsite", "on-site", "location", "commute"]
        }
        if criterionKey.contains("brand") || criterionKey.contains("signal") {
            return ["brand", "prestige", "reputation", "signal", "known company"]
        }
        if criterionKey.contains("execution") || criterionKey.contains("delivery") {
            return ["delivered", "execution", "ownership", "impact", "shipped"]
        }
        return criterionKey.split(separator: " ").map(String.init)
    }
}

struct ResultInterpreter {
    func interpret(draft: RankingDraft, result: RankingResult, constraints: [ConstraintFinding]) -> InterpretedResult {
        let winner = result.rankedVendors.first
        let runnerUp = result.rankedVendors.dropFirst().first
        let winnerName = winner?.vendorName ?? "the leading option"
        let runnerName = runnerUp?.vendorName ?? "the next option"
        let topCriteria = draft.criteria.sorted { $0.weightPercent > $1.weightPercent }.prefix(3)

        let drivers: [String] = topCriteria.map { criterion in
            let winnerScore = draft.scores.first { $0.vendorID == winner?.vendorID && $0.criterionID == criterion.id }?.score ?? 0
            let secondScore = draft.scores.first { $0.vendorID == runnerUp?.vendorID && $0.criterionID == criterion.id }?.score ?? 0
            let gap = (winnerScore - secondScore).rounded(to: 1)
            return "\(criterion.name) (\(Int(criterion.weightPercent.rounded()))%): \(winnerName) \(winnerScore.rounded(to: 1)) vs \(runnerName) \(secondScore.rounded(to: 1)) (gap \(gap))."
        }

        var risks: [String] = []
        if result.tieDetected {
            let margin = ((winner?.totalScore ?? 0) - (runnerUp?.totalScore ?? 0)).rounded(to: 1)
            risks.append("Top options are near-tied (\(margin) points), so one criterion reweight can flip the winner.")
        }
        if result.confidenceScore < 0.6 {
            let lowConfidenceCount = draft.scores.filter { $0.confidence < 0.60 }.count
            risks.append("Evidence confidence is limited (\(lowConfidenceCount) low-confidence score\(lowConfidenceCount == 1 ? "" : "s")).")
        }
        if let unstable = result.sensitivityFindings.first(where: \.winnerFlipped) {
            risks.append("Sensitivity check: changing \(unstable.criterionName.lowercased()) can flip the winner.")
        }
        let violated = constraints.filter { !$0.violatedOptionIDs.isEmpty }
        if !violated.isEmpty {
            let labels = violated.flatMap(\.violatedOptionLabels).uniqued().prefix(3).joined(separator: ", ")
            risks.append("Hard-constraint issues detected for \(labels.isEmpty ? "one or more options" : labels).")
        }
        if risks.isEmpty {
            risks.append("Validate the top weighted criterion (\(topCriteria.first?.name ?? "fit")) with one external check before finalizing.")
        }

        let confidence: String
        switch result.confidenceScore {
        case ..<0.45:
            confidence = "Low — the lead is thin or depends on weak evidence."
        case ..<0.75:
            confidence = "Medium — the lead is directionally clear but still sensitive to one assumption."
        default:
            confidence = "High — the leader remains stable across weighted criteria and sensitivity checks."
        }

        return InterpretedResult(drivers: drivers.isEmpty ? ["Weighted scores currently favor one option across key criteria."] : drivers, risks: risks, confidence: confidence)
    }
}

struct BiasDetector {
    func detect(draft: RankingDraft, result: RankingResult, userProfile: AIUserProfile?) -> [String] {
        let text = [draft.contextNarrative, draft.conversationSummary].joined(separator: "\n").lowercased()
        var flags: [String] = []

        if text.contains("dream company") || text.contains("prestige") || text.contains("big name") {
            flags.append("Prestige bias: brand signal may be overweighted versus role fit.")
        }
        if text.contains("current job") || text.contains("already invested") || text.contains("years here") {
            flags.append("Sunk-cost bias: past investment may be distorting forward-looking value.")
        }
        if text.contains("afraid") || text.contains("wrong choice") || text.contains("lose") {
            flags.append("Loss aversion: downside fear may be overweighted versus expected upside.")
        }
        if result.tieDetected {
            flags.append("Overconfidence risk: close scores do not justify absolute certainty.")
        }
        if let challenge = userProfile?.biggestChallenge, challenge == BiggestChallenge.overthinking.rawValue {
            flags.append("Analysis paralysis risk: prioritize one disconfirming test over more brainstorming.")
        }

        return Array(flags.prefix(3))
    }
}

struct RecommendationEngine {
    func recommend(draft: RankingDraft, result: RankingResult, interpreted: InterpretedResult, constraints: [ConstraintFinding]) -> RecommendationSummary {
        let winner = result.rankedVendors.first?.vendorName.trimmed.nonEmpty ?? "Top option"
        let runnerUp = result.rankedVendors.dropFirst().first?.vendorName.trimmed.nonEmpty ?? "the runner-up"
        let decisive = decisiveCriterion(in: draft, result: result)
        let hardViolationOnWinner = constraints.contains { finding in
            finding.violatedOptionLabels.contains(where: { comparable($0) == comparable(winner) }) && finding.severity == "hard_violation"
        }

        let recommendation: String
        if hardViolationOnWinner {
            let decisiveText = decisive.map { " It currently leads most on \($0.name)." } ?? ""
            recommendation = "\(winner) leads on weighted scores, but it violates a hard constraint.\(decisiveText) Do not finalize before resolving that constraint."
        } else {
            if let decisive {
                recommendation = "\(winner) is recommended because it has the strongest weighted lead on \(decisive.name) (\(decisive.winnerScore.rounded(to: 1)) vs \(decisive.runnerScore.rounded(to: 1)))."
            } else {
                recommendation = "\(winner) is the recommended option based on weighted fit across your top criteria."
            }
        }

        let nextStep: String
        if hardViolationOnWinner {
            nextStep = "Resolve the hard-constraint gap for \(winner) before making the final choice."
        } else if isHiringContext(draft.contextNarrative) {
            let criterion = decisive?.name ?? "role fit"
            nextStep = "Run a 30-minute trial task and one reference check for \(winner), focused on \(criterion.lowercased())."
        } else if isCareerContext(draft.contextNarrative) {
            nextStep = "Book a scope/compensation validation call this week, then decide between \(winner) and \(runnerUp)."
        } else if draft.usageContext == .work {
            let criterion = decisive?.name ?? "the top criterion"
            nextStep = "Run a short pilot this week to verify \(criterion.lowercased()) before committing."
        } else {
            nextStep = "Run one concrete validation step in 7 days, then finalize between \(winner) and \(runnerUp)."
        }

        return RecommendationSummary(text: recommendation, nextStep: nextStep)
    }

    private func decisiveCriterion(in draft: RankingDraft, result: RankingResult) -> (name: String, winnerScore: Double, runnerScore: Double, weightedImpact: Double)? {
        guard let winnerID = result.rankedVendors.first?.vendorID,
              let runnerID = result.rankedVendors.dropFirst().first?.vendorID else {
            return nil
        }

        let ranked = draft.criteria.compactMap { criterion -> (name: String, winnerScore: Double, runnerScore: Double, weightedImpact: Double)? in
            let winnerScore = draft.scores.first(where: { $0.vendorID == winnerID && $0.criterionID == criterion.id })?.score ?? 0
            let runnerScore = draft.scores.first(where: { $0.vendorID == runnerID && $0.criterionID == criterion.id })?.score ?? 0
            let weightedImpact = (winnerScore - runnerScore) * (criterion.weightPercent / 100)
            return (criterion.name, winnerScore, runnerScore, weightedImpact)
        }
            .sorted { $0.weightedImpact > $1.weightedImpact }

        return ranked.first
    }

    private func isHiringContext(_ context: String) -> Bool {
        let lower = context.lowercased()
        return lower.contains("candidate") || lower.contains("hire") || lower.contains("recruit")
    }

    private func isCareerContext(_ context: String) -> Bool {
        let lower = context.lowercased()
        return lower.contains("job") || lower.contains("offer") || lower.contains("salary") || lower.contains("career")
    }

    private func comparable(_ text: String) -> String {
        text.lowercased().replacingOccurrences(of: " ", with: "")
    }
}

struct DecisionReportGenerator {
    func generate(recommendation: RecommendationSummary, interpreted: InterpretedResult, biases: [String]) -> DecisionReport {
        DecisionReport(
            recommendation: recommendation.text,
            drivers: interpreted.drivers,
            risks: interpreted.risks,
            confidence: interpreted.confidence,
            nextStep: recommendation.nextStep,
            biasChecks: biases
        )
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
        let value = trimmed
        return value.isEmpty ? nil : value
    }
}

private extension Array where Element: Hashable {
    func uniqued() -> [Element] {
        var seen = Set<Element>()
        return filter { seen.insert($0).inserted }
    }
}

private extension Double {
    func rounded(to digits: Int) -> Double {
        guard digits >= 0 else { return self }
        let precision = pow(10.0, Double(digits))
        return (self * precision).rounded() / precision
    }
}
