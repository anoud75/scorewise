import Foundation

struct OptionExtractor {
    private enum OptionKind {
        case entity
        case strategy
        case baseline
    }

    func extract(from parsed: ParsedSituation, draft: RankingDraft, userProfile: AIUserProfile?) -> [DecisionOptionSnapshot] {
        var options: [DecisionOptionSnapshot] = []
        let source = [parsed.narrative, draft.conversationSummary]
            .joined(separator: "\n")

        extractShouldOptions(from: source).forEach { appendOption(&options, option: $0) }
        extractBetweenOptions(from: source).forEach { appendOption(&options, option: $0) }
        extractVersusOptions(from: source).forEach { appendOption(&options, option: $0) }
        extractOfferRows(from: source).forEach { appendOption(&options, option: $0) }
        extractCandidateRows(from: source).forEach { appendOption(&options, option: $0) }
        extractLabeledRows(from: source).forEach { appendOption(&options, option: $0) }

        for vendor in draft.vendors {
            let name = trim(vendor.name)
            guard !name.isEmpty else { continue }
            let option = DecisionOptionSnapshot(
                id: vendor.id,
                label: name,
                type: inferredType(label: name, recruiterMode: parsed.isRecruiterMode),
                description: trim(vendor.notes).nonEmpty ?? "Option from your draft.",
                aiSuggested: false
            )
            appendOption(&options, option: option)
        }

        let nonStrategy = options.filter { optionKind(for: $0.label) != .strategy }
        let scoped = comparableScopedOptions(from: nonStrategy)
        if scoped.count >= 2 {
            return Array(scoped.prefix(8))
        }

        return Array(nonStrategy.prefix(8))
    }

    func comparableCheck(for options: [DecisionOptionSnapshot], recruiterMode: Bool) -> ComparableOptionCheck {
        let comparable = comparableScopedOptions(from: options)
        guard comparable.count >= 2 else {
            return ComparableOptionCheck(
                comparable: false,
                detectedType: nil,
                violations: ["Need at least 2 comparable explicit options."]
            )
        }

        let resolvedType = majorityType(in: comparable, recruiterMode: recruiterMode)
        let mixedTypes = Set(comparable.map(\.type)).count > 1
        if mixedTypes {
            return ComparableOptionCheck(
                comparable: false,
                detectedType: resolvedType,
                violations: ["Options include mixed types. Use one comparable type (candidate vs candidate, offer vs offer)."]
            )
        }

        return ComparableOptionCheck(comparable: true, detectedType: resolvedType, violations: [])
    }

    private func comparableScopedOptions(from options: [DecisionOptionSnapshot]) -> [DecisionOptionSnapshot] {
        let explicitNamed = options.filter(\.isExplicitNamed)
        guard explicitNamed.count >= 2 else { return explicitNamed }

        let majority = majorityType(in: explicitNamed, recruiterMode: false)
        return explicitNamed.filter { option in
            guard !isGenericPlaceholderLabel(option.label) else { return false }
            if let majority {
                return option.type == majority || option.type == .genericChoice
            }
            return true
        }
    }

    private func majorityType(in options: [DecisionOptionSnapshot], recruiterMode: Bool) -> DecisionOptionType? {
        var counts: [DecisionOptionType: Int] = [:]
        for option in options {
            let type = option.type == .genericChoice && recruiterMode ? .candidate : option.type
            counts[type, default: 0] += 1
        }
        return counts.max(by: { $0.value < $1.value })?.key
    }

    private func extractShouldOptions(from text: String) -> [DecisionOptionSnapshot] {
        guard let groups = firstRegexGroups(
            pattern: #"(?i)should\s+i\s+(.+?)\s+or\s+(.+?)(?:[?.!,]|$)"#,
            in: text
        ), groups.count >= 2 else {
            return []
        }

        return groups.prefix(2).compactMap { raw in
            let label = sentenceCase(clean(raw))
            guard !label.isEmpty else { return nil }
            return DecisionOptionSnapshot(
                label: label,
                type: inferredType(label: label, recruiterMode: false),
                description: "Option extracted from your situation.",
                aiSuggested: true
            )
        }
    }

    private func extractBetweenOptions(from text: String) -> [DecisionOptionSnapshot] {
        guard let groups = firstRegexGroups(
            pattern: #"(?i)(?:between|comparing)\s+(.+?)\s+and\s+(.+?)(?:[?.!,]|$)"#,
            in: text
        ), groups.count >= 2 else {
            return []
        }

        return groups.prefix(2).compactMap { raw in
            let label = sentenceCase(clean(raw))
            guard !label.isEmpty else { return nil }
            return DecisionOptionSnapshot(
                label: label,
                type: inferredType(label: label, recruiterMode: false),
                description: "Option extracted from your situation.",
                aiSuggested: true
            )
        }
    }

    private func extractOfferRows(from text: String) -> [DecisionOptionSnapshot] {
        guard let rows = allRegexGroups(
            pattern: #"(?i)offer\s*([A-H])\s*[—:\-]\s*([^\n\r]+)"#,
            in: text
        ) else {
            return []
        }

        return rows.compactMap { row in
            guard row.count >= 2 else { return nil }
            let title = clean(row[1])
            let label = title.isEmpty ? "Offer \(row[0].uppercased())" : "Offer \(row[0].uppercased()) — \(title)"
            return DecisionOptionSnapshot(
                label: label,
                type: .offer,
                description: "Offer extracted from your brief.",
                aiSuggested: true
            )
        }
    }

    private func extractVersusOptions(from text: String) -> [DecisionOptionSnapshot] {
        guard let groups = firstRegexGroups(
            pattern: #"(?i)([A-Za-z][A-Za-z0-9 '&.\-]{1,80})\s+vs\.?\s+([A-Za-z][A-Za-z0-9 '&.\-]{1,80})"#,
            in: text
        ), groups.count >= 2 else {
            return []
        }

        return groups.prefix(2).compactMap { raw in
            let label = sentenceCase(clean(raw))
            guard !label.isEmpty else { return nil }
            return DecisionOptionSnapshot(
                label: label,
                type: inferredType(label: label, recruiterMode: false),
                description: "Option extracted from your comparison.",
                aiSuggested: true
            )
        }
    }

    private func extractCandidateRows(from text: String) -> [DecisionOptionSnapshot] {
        let source = text.replacingOccurrences(of: "\n", with: " ")
        guard let groups = firstRegexGroups(
            pattern: #"(?i)(?:candidates?|shortlist|compare)\s*[:\-]\s*([A-Za-z][A-Za-z' .-]{1,120})"#,
            in: source
        ), let first = groups.first else {
            return []
        }

        return first
            .replacingOccurrences(of: " and ", with: ",")
            .split(separator: ",")
            .map { clean(String($0)) }
            .filter { $0.count >= 2 }
            .prefix(8)
            .map {
                DecisionOptionSnapshot(
                    label: $0,
                    type: .candidate,
                    description: "Candidate extracted from your shortlist.",
                    aiSuggested: true
                )
            }
    }

    private func extractLabeledRows(from text: String) -> [DecisionOptionSnapshot] {
        guard let rows = allRegexGroups(
            pattern: #"(?im)^\s*(?:candidate|option)\s*(?:[A-H]|\d+)\s*[—:\-]\s*([^\n\r]+)\s*$"#,
            in: text
        ) else {
            return []
        }

        return rows.compactMap { row in
            guard let raw = row.first else { return nil }
            let label = sentenceCase(clean(raw))
            guard !label.isEmpty else { return nil }
            return DecisionOptionSnapshot(
                label: label,
                type: inferredType(label: label, recruiterMode: false),
                description: "Option extracted from labeled narrative rows.",
                aiSuggested: true
            )
        }
    }

    private func optionKind(for label: String) -> OptionKind {
        let lower = label.lowercased()
        if lower.contains("current") || lower.contains("stay") || lower.contains("baseline") {
            return .baseline
        }
        let strategyWords = ["negotiate", "pilot", "trial", "hybrid", "phase", "test first", "wait", "delay", "run first"]
        if strategyWords.contains(where: lower.contains) {
            return .strategy
        }
        return .entity
    }

    private func appendOption(_ options: inout [DecisionOptionSnapshot], option: DecisionOptionSnapshot) {
        let trimmedLabel = trim(option.label)
        guard !trimmedLabel.isEmpty else { return }
        let key = comparableName(trimmedLabel)
        guard !options.contains(where: { comparableName($0.label) == key }) else { return }
        options.append(option)
    }

    private func inferredType(label: String, recruiterMode: Bool) -> DecisionOptionType {
        let lower = label.lowercased()
        if recruiterMode {
            return .candidate
        }
        if lower.contains("offer") || lower.contains("current job") || lower.contains("role") {
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

    private func isGenericPlaceholderLabel(_ label: String) -> Bool {
        let lower = label.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        if lower.isEmpty {
            return true
        }
        if lower.hasPrefix("vendor ") || lower.hasPrefix("option ") || lower.hasPrefix("candidate ") {
            return true
        }
        return false
    }

    private func comparableName(_ name: String) -> String {
        trim(name)
            .lowercased()
            .replacingOccurrences(of: "accept ", with: "")
            .replacingOccurrences(of: "choose ", with: "")
            .replacingOccurrences(of: "go with ", with: "")
            .replacingOccurrences(of: "the ", with: "")
            .replacingOccurrences(of: " ", with: "")
    }

    private func clean(_ input: String) -> String {
        input
            .replacingOccurrences(of: "  ", with: " ")
            .trimmingCharacters(in: CharacterSet(charactersIn: " .,:;!?\"'"))
    }

    private func sentenceCase(_ input: String) -> String {
        guard let first = input.first else { return input }
        return first.uppercased() + input.dropFirst()
    }

    private func trim(_ value: String) -> String {
        value.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func firstRegexGroups(pattern: String, in text: String) -> [String]? {
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return nil }
        let nsrange = NSRange(text.startIndex..<text.endIndex, in: text)
        guard let match = regex.firstMatch(in: text, range: nsrange), match.numberOfRanges > 1 else { return nil }
        return (1 ..< match.numberOfRanges).compactMap { index in
            let range = match.range(at: index)
            guard let swiftRange = Range(range, in: text) else { return nil }
            return trim(String(text[swiftRange]))
        }
    }

    private func allRegexGroups(pattern: String, in text: String) -> [[String]]? {
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return nil }
        let nsrange = NSRange(text.startIndex..<text.endIndex, in: text)
        let matches = regex.matches(in: text, range: nsrange)
        guard !matches.isEmpty else { return nil }
        return matches.map { match in
            guard match.numberOfRanges > 1 else { return [] }
            return (1 ..< match.numberOfRanges).compactMap { index in
                let range = match.range(at: index)
                guard let swiftRange = Range(range, in: text) else { return nil }
                return trim(String(text[swiftRange]))
            }
        }
    }
}

private extension String {
    var nonEmpty: String? {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
