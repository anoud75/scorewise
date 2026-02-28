import Foundation

enum RankingEngine {
    static func normalizedCriteria(_ criteria: [CriterionDraft]) -> [CriterionDraft] {
        guard !criteria.isEmpty else { return criteria }
        let valid = criteria.map { max(0, $0.weightPercent) }
        let total = valid.reduce(0, +)

        if total == 0 {
            let equal = 100.0 / Double(criteria.count)
            return criteria.map {
                var updated = $0
                updated.weightPercent = equal
                return updated
            }
        }

        let normalized = criteria.enumerated().map { index, criterion in
            var updated = criterion
            if index == criteria.count - 1 {
                let used = criteria.enumerated().prefix(criteria.count - 1).map { i, c in
                    max(0, c.weightPercent) / total * 100
                }.reduce(0, +)
                updated.weightPercent = max(0, 100 - used)
            } else {
                updated.weightPercent = max(0, criterion.weightPercent) / total * 100
            }
            return updated
        }
        return normalized
    }

    static func computeResult(for draft: RankingDraft) -> RankingResult {
        let normalized = normalizedCriteria(draft.criteria)
        let vendors = draft.vendors

        let results: [VendorResult] = vendors.map { vendor in
            let total = normalized.reduce(0.0) { partial, criterion in
                let cell = draft.scores.first { $0.vendorID == vendor.id && $0.criterionID == criterion.id }
                let score = min(max(cell?.score ?? 0, 0), 10)
                return partial + (criterion.weightPercent / 100.0) * score
            }
            return VendorResult(vendorID: vendor.id, vendorName: vendor.name, totalScore: total)
        }
        .sorted { $0.totalScore > $1.totalScore }

        let winner = results.first
        let second = results.dropFirst().first
        let tieDetected = {
            guard let winner, let second else { return false }
            return abs(winner.totalScore - second.totalScore) < 0.05
        }()

        let confidence = confidenceScore(from: results)
        let sensitivity = computeSensitivity(draft: draft, baseCriteria: normalized)

        return RankingResult(
            projectID: draft.id,
            rankedVendors: results,
            winnerID: winner?.vendorID,
            confidenceScore: confidence,
            tieDetected: tieDetected,
            sensitivityFindings: sensitivity
        )
    }

    static func computeSensitivity(draft: RankingDraft, baseCriteria: [CriterionDraft]) -> [SensitivityFinding] {
        let topCriteria = Array(baseCriteria.sorted { $0.weightPercent > $1.weightPercent }.prefix(3))
        guard let baseWinner = computeResultWithoutSensitivityRecursion(draft: draft, criteria: baseCriteria).winnerID else {
            return []
        }

        return topCriteria.map { criterion in
            var shifted = baseCriteria
            guard let index = shifted.firstIndex(where: { $0.id == criterion.id }) else {
                return SensitivityFinding(criterionName: criterion.name, winnerFlipped: false)
            }

            shifted[index].weightPercent *= 1.1
            shifted = normalizedCriteria(shifted)
            let shiftedWinner = computeResultWithoutSensitivityRecursion(draft: draft, criteria: shifted).winnerID
            return SensitivityFinding(criterionName: criterion.name, winnerFlipped: shiftedWinner != baseWinner)
        }
    }

    private static func computeResultWithoutSensitivityRecursion(draft: RankingDraft, criteria: [CriterionDraft]) -> RankingResult {
        let vendors = draft.vendors
        let results: [VendorResult] = vendors.map { vendor in
            let total = criteria.reduce(0.0) { partial, criterion in
                let cell = draft.scores.first { $0.vendorID == vendor.id && $0.criterionID == criterion.id }
                return partial + ((criterion.weightPercent / 100.0) * (cell?.score ?? 0))
            }
            return VendorResult(vendorID: vendor.id, vendorName: vendor.name, totalScore: total)
        }.sorted { $0.totalScore > $1.totalScore }

        let winner = results.first?.vendorID
        return RankingResult(
            projectID: draft.id,
            rankedVendors: results,
            winnerID: winner,
            confidenceScore: confidenceScore(from: results),
            tieDetected: false,
            sensitivityFindings: []
        )
    }

    private static func confidenceScore(from results: [VendorResult]) -> Double {
        guard let first = results.first else { return 0 }
        guard let second = results.dropFirst().first else { return 1 }
        let delta = max(0, first.totalScore - second.totalScore)
        return min(1.0, delta / 2.0)
    }
}
