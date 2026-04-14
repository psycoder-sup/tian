import Foundation

/// Fuzzy string matching with scoring for the workspace switcher.
/// Matches query characters in order against a candidate string,
/// awarding bonuses for consecutive runs, word boundaries, and prefix matches.
struct FuzzyMatch {
    struct Result {
        let score: Int
        let matchedIndices: [String.Index]
    }

    // MARK: - Scoring Constants

    private static let baseMatchScore = 1
    private static let consecutiveBonus = 5
    private static let boundaryBonus = 10
    private static let prefixBonus = 15
    private static let unmatchedPenalty = -1

    /// Scores how well `query` fuzzy-matches `candidate`.
    /// Returns nil if the query characters cannot be found in order within the candidate.
    /// An empty query matches everything with score 0.
    static func score(query: String, candidate: String) -> Result? {
        let queryChars = Array(query.lowercased())
        let candidateStr = candidate.lowercased()
        let candidateChars = Array(candidateStr)

        if queryChars.isEmpty {
            return Result(score: 0, matchedIndices: [])
        }

        if candidateChars.isEmpty {
            return nil
        }

        var matchedIndices: [String.Index] = []
        var totalScore = 0
        var queryIndex = 0
        var previousMatchCandidateIndex: Int? = nil

        // Pre-compute arrays once (avoid repeated allocation inside the loop)
        let originalChars = Array(candidate)
        let stringIndices = Array(candidate.indices)

        for candidateIndex in 0..<candidateChars.count {
            guard queryIndex < queryChars.count else { break }

            if candidateChars[candidateIndex] == queryChars[queryIndex] {
                var charScore = baseMatchScore

                // Prefix bonus: query starts matching at the beginning of candidate
                if candidateIndex == 0 && queryIndex == 0 {
                    charScore += prefixBonus
                }

                // Boundary bonus: match at start of a word
                if candidateIndex > 0 {
                    let prev = candidateChars[candidateIndex - 1]
                    if prev == " " || prev == "-" || prev == "_" || prev == "/" || prev == "." {
                        charScore += boundaryBonus
                    }
                    // CamelCase boundary
                    if originalChars[candidateIndex].isUppercase && originalChars[candidateIndex - 1].isLowercase {
                        charScore += boundaryBonus
                    }
                }

                // Consecutive bonus: immediately follows the previous match
                if let prevIndex = previousMatchCandidateIndex, candidateIndex == prevIndex + 1 {
                    charScore += consecutiveBonus
                }

                totalScore += charScore
                matchedIndices.append(stringIndices[candidateIndex])
                previousMatchCandidateIndex = candidateIndex
                queryIndex += 1
            }
        }

        // All query characters must be matched
        guard queryIndex == queryChars.count else { return nil }

        // Penalize long candidates to prefer tighter matches
        let unmatched = candidateChars.count - queryChars.count
        totalScore += unmatched * unmatchedPenalty

        return Result(score: totalScore, matchedIndices: matchedIndices)
    }
}
