import Foundation

struct ConstraintDetector {
    func detect(from parsed: ParsedSituation, draft: RankingDraft) -> [ConstraintFinding] {
        var findings: [ConstraintFinding] = []
        let context = parsed.combinedContext
        let lower = context.lowercased()
        let options = parsed.explicitOptions.isEmpty
            ? draft.vendors.map { DecisionOptionSnapshot(id: $0.id, label: $0.name, description: $0.notes, aiSuggested: false) }
            : parsed.explicitOptions

        if let minSalary = minimumSalary(from: lower) {
            var violatedIDs: [String] = []
            var violatedLabels: [String] = []
            for option in options {
                if let salary = salaryForOption(option, draft: draft, context: context), salary < minSalary {
                    violatedIDs.append(option.id)
                    violatedLabels.append(option.label)
                }
            }
            findings.append(
                ConstraintFinding(
                    type: .minimumSalary,
                    rule: "Minimum salary >= \(Int(minSalary))",
                    violatedOptionIDs: violatedIDs,
                    violatedOptionLabels: violatedLabels,
                    severity: violatedIDs.isEmpty ? "ok" : "hard_violation"
                )
            )
        }

        let requiresRemote = lower.contains("remote only") || lower.contains("must be remote") || lower.contains("fully remote")
        if requiresRemote {
            var violatedIDs: [String] = []
            var violatedLabels: [String] = []
            for option in options {
                let optionBlob = optionContext(option: option, draft: draft, context: context).lowercased()
                if optionBlob.contains("onsite") || optionBlob.contains("on-site") || optionBlob.contains("office 5") {
                    violatedIDs.append(option.id)
                    violatedLabels.append(option.label)
                }
            }
            findings.append(
                ConstraintFinding(
                    type: .remote,
                    rule: "Work model must be remote.",
                    violatedOptionIDs: violatedIDs,
                    violatedOptionLabels: violatedLabels,
                    severity: violatedIDs.isEmpty ? "ok" : "hard_violation"
                )
            )
        }

        if lower.contains("visa") && (lower.contains("need") || lower.contains("required") || lower.contains("must")) {
            var violatedIDs: [String] = []
            var violatedLabels: [String] = []
            for option in options {
                let optionBlob = optionContext(option: option, draft: draft, context: context).lowercased()
                if optionBlob.contains("no visa") || optionBlob.contains("no sponsorship") {
                    violatedIDs.append(option.id)
                    violatedLabels.append(option.label)
                }
            }
            findings.append(
                ConstraintFinding(
                    type: .visa,
                    rule: "Visa sponsorship is required.",
                    violatedOptionIDs: violatedIDs,
                    violatedOptionLabels: violatedLabels,
                    severity: violatedIDs.isEmpty ? "ok" : "hard_violation"
                )
            )
        }

        if let requiredLocation = requiredLocation(from: lower) {
            var violatedIDs: [String] = []
            var violatedLabels: [String] = []
            for option in options {
                let optionBlob = optionContext(option: option, draft: draft, context: context).lowercased()
                let knownLocations = ["riyadh", "jeddah", "dubai", "london", "new york", "remote"]
                let foundDifferent = knownLocations.contains { loc in
                    optionBlob.contains(loc) && loc != requiredLocation
                }
                if foundDifferent {
                    violatedIDs.append(option.id)
                    violatedLabels.append(option.label)
                }
            }
            findings.append(
                ConstraintFinding(
                    type: .location,
                    rule: "Location must be \(requiredLocation.capitalized).",
                    violatedOptionIDs: violatedIDs,
                    violatedOptionLabels: violatedLabels,
                    severity: violatedIDs.isEmpty ? "ok" : "hard_violation"
                )
            )
        }

        return findings
    }

    private func minimumSalary(from text: String) -> Double? {
        let patterns = [
            #"(?i)(?:minimum|min|at least|not below|can't go below|cannot go below)\s+(?:salary\s*)?(?:is|=|:)?\s*([0-9]{2,6}(?:[,\.\s][0-9]{3})?)"#,
            #"(?i)salary\s*(?:must be|>=|>|at least)\s*([0-9]{2,6}(?:[,\.\s][0-9]{3})?)"#
        ]
        for pattern in patterns {
            if let groups = firstRegexGroups(pattern: pattern, in: text),
               let first = groups.first,
               let value = numericValue(from: first) {
                return value
            }
        }
        return nil
    }

    private func requiredLocation(from text: String) -> String? {
        if let groups = firstRegexGroups(pattern: #"(?i)(?:must be|need to be|have to be)\s+in\s+([a-z ]{3,30})"#, in: text),
           let location = groups.first,
           !trim(location).isEmpty {
            return trim(location).lowercased()
        }
        return nil
    }

    private func salaryForOption(_ option: DecisionOptionSnapshot, draft: RankingDraft, context: String) -> Double? {
        let candidateBlobs = salaryCandidates(for: option, draft: draft, context: context)
        let patterns = [
            #"(?i)salary\s*[:=]?\s*([0-9]{2,6}(?:[,\.\s][0-9]{3})?)"#,
            #"(?i)([0-9]{2,6}(?:[,\.\s][0-9]{3})?)\s*(?:sar|usd|aed|month|monthly)"#
        ]
        for blob in candidateBlobs {
            for pattern in patterns {
                if let groups = firstRegexGroups(pattern: pattern, in: blob),
                   let first = groups.first,
                   let value = numericValue(from: first) {
                    return value
                }
            }
        }
        return nil
    }

    private func salaryCandidates(for option: DecisionOptionSnapshot, draft: RankingDraft, context: String) -> [String] {
        var candidates: [String] = []
        let optionKey = normalizeText(option.label)

        if let vendorByID = draft.vendors.first(where: { $0.id == option.id }) {
            candidates.append(vendorByID.notes)
            candidates.append("\(vendorByID.name) \(vendorByID.notes)")
        }

        let matchingVendors = draft.vendors.filter { vendor in
            let vendorKey = normalizeText(vendor.name)
            return !vendorKey.isEmpty && (vendorKey == optionKey || vendorKey.contains(optionKey) || optionKey.contains(vendorKey))
        }
        for vendor in matchingVendors {
            candidates.append(vendor.notes)
            candidates.append("\(vendor.name) \(vendor.notes)")
        }

        for rawLine in context.components(separatedBy: .newlines) {
            let line = trim(rawLine)
            guard !line.isEmpty else { continue }
            if normalizeText(line).contains(optionKey) {
                candidates.append(line)
            }
        }

        if let description = option.description, !trim(description).isEmpty {
            candidates.append(trim(description))
        }

        if candidates.isEmpty {
            candidates.append("\(option.label) \(option.description ?? "")")
        }

        return Array(NSOrderedSet(array: candidates)) as? [String] ?? candidates
    }

    private func optionContext(option: DecisionOptionSnapshot, draft: RankingDraft, context: String) -> String {
        if let vendor = draft.vendors.first(where: { $0.id == option.id }) {
            return "\(option.label)\n\(vendor.notes)\n\(context)"
        }
        return "\(option.label)\n\(option.description ?? "")\n\(context)"
    }

    private func numericValue(from raw: String) -> Double? {
        let cleaned = raw.replacingOccurrences(of: ",", with: "").replacingOccurrences(of: " ", with: "")
        return Double(cleaned)
    }

    private func normalizeText(_ raw: String) -> String {
        raw
            .lowercased()
            .replacingOccurrences(of: #"[^a-z0-9]+"#, with: "", options: .regularExpression)
    }

    private func trim(_ value: String) -> String {
        value.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func firstRegexGroups(pattern: String, in text: String) -> [String]? {
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return nil }
        let nsrange = NSRange(text.startIndex..<text.endIndex, in: text)
        guard let match = regex.firstMatch(in: text, range: nsrange), match.numberOfRanges > 1 else { return nil }
        return (1..<match.numberOfRanges).compactMap { index in
            let range = match.range(at: index)
            guard let swiftRange = Range(range, in: text) else { return nil }
            return trim(String(text[swiftRange]))
        }
    }
}
