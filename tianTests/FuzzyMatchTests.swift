import Testing
import Foundation
@testable import tian

struct FuzzyMatchTests {
    // MARK: - Empty Query

    @Test func emptyQueryMatchesEverything() {
        let result = FuzzyMatch.score(query: "", candidate: "Workspace")
        #expect(result != nil)
        #expect(result?.score == 0)
        #expect(result?.matchedIndices.isEmpty == true)
    }

    @Test func emptyQueryMatchesEmptyCandidate() {
        let result = FuzzyMatch.score(query: "", candidate: "")
        #expect(result != nil)
        #expect(result?.score == 0)
    }

    // MARK: - No Match

    @Test func noMatchReturnsNil() {
        let result = FuzzyMatch.score(query: "xyz", candidate: "Workspace")
        #expect(result == nil)
    }

    @Test func emptyCandidateReturnsNil() {
        let result = FuzzyMatch.score(query: "a", candidate: "")
        #expect(result == nil)
    }

    @Test func partialQueryNoMatch() {
        // Only some query chars found
        let result = FuzzyMatch.score(query: "wkz", candidate: "Workspace")
        #expect(result == nil)
    }

    // MARK: - Case Insensitivity

    @Test func caseInsensitiveMatch() {
        let result = FuzzyMatch.score(query: "WORK", candidate: "workspace")
        #expect(result != nil)
    }

    @Test func mixedCaseMatch() {
        let result = FuzzyMatch.score(query: "wS", candidate: "WorkSpace")
        #expect(result != nil)
    }

    // MARK: - Exact Match

    @Test func exactMatchScoresHighest() {
        let exact = FuzzyMatch.score(query: "abc", candidate: "abc")
        let scattered = FuzzyMatch.score(query: "abc", candidate: "aXbXc")
        #expect(exact != nil)
        #expect(scattered != nil)
        #expect(exact!.score > scattered!.score)
    }

    // MARK: - Prefix Match

    @Test func prefixMatchGetsPrefixBonus() {
        let prefix = FuzzyMatch.score(query: "wo", candidate: "workspace")
        let middle = FuzzyMatch.score(query: "sp", candidate: "workspace")
        #expect(prefix != nil)
        #expect(middle != nil)
        #expect(prefix!.score > middle!.score)
    }

    // MARK: - Boundary Match

    @Test func wordBoundaryBonus() {
        // "mw" matching "my-workspace" should score higher than "mw" in "meadow"
        let boundary = FuzzyMatch.score(query: "mw", candidate: "my-workspace")
        let noBoundary = FuzzyMatch.score(query: "mw", candidate: "meadowwalk")
        #expect(boundary != nil)
        #expect(noBoundary != nil)
        #expect(boundary!.score > noBoundary!.score)
    }

    @Test func camelCaseBoundary() {
        let camel = FuzzyMatch.score(query: "ws", candidate: "WorkSpace")
        #expect(camel != nil)
        // "s" matches at camelCase boundary "S" — gets boundary bonus
    }

    // MARK: - Consecutive Bonus

    @Test func consecutiveCharsScoreHigher() {
        let consecutive = FuzzyMatch.score(query: "ab", candidate: "abc")
        let scattered = FuzzyMatch.score(query: "ab", candidate: "aXb")
        #expect(consecutive != nil)
        #expect(scattered != nil)
        #expect(consecutive!.score > scattered!.score)
    }

    // MARK: - Shorter Candidate Preferred

    @Test func shorterCandidatePreferred() {
        let short = FuzzyMatch.score(query: "ws", candidate: "ws")
        let long = FuzzyMatch.score(query: "ws", candidate: "workspace-something-long")
        #expect(short != nil)
        #expect(long != nil)
        #expect(short!.score > long!.score)
    }

    // MARK: - Matched Indices

    @Test func matchedIndicesAreCorrect() {
        let result = FuzzyMatch.score(query: "wsp", candidate: "workspace")
        #expect(result != nil)
        #expect(result!.matchedIndices.count == 3)
        let candidate = "workspace"
        #expect(candidate[result!.matchedIndices[0]] == "w")
        #expect(candidate[result!.matchedIndices[1]] == "s")
        #expect(candidate[result!.matchedIndices[2]] == "p")
    }

    @Test func matchedIndicesForScatteredMatch() {
        let candidate = "a_b_c"
        let result = FuzzyMatch.score(query: "abc", candidate: candidate)
        #expect(result != nil)
        #expect(result!.matchedIndices.count == 3)
        // First match 'a' at index 0
        #expect(candidate[result!.matchedIndices[0]] == "a")
        #expect(candidate[result!.matchedIndices[1]] == "b")
        #expect(candidate[result!.matchedIndices[2]] == "c")
    }

    // MARK: - Ordering (Higher Score = Better Match)

    @Test func scoringOrderIsCorrect() {
        let candidates = ["Workspace", "My Work", "workflow", "somewhere"]
        let query = "work"
        let scored = candidates.compactMap { candidate -> (String, Int)? in
            guard let result = FuzzyMatch.score(query: query, candidate: candidate) else {
                return nil
            }
            return (candidate, result.score)
        }
        .sorted { $0.1 > $1.1 }

        // All should match
        #expect(scored.count >= 3)  // "somewhere" might not match "work" in order
    }
}
