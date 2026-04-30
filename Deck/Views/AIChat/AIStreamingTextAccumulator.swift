import Foundation

struct AIStreamingTextAccumulator: Sendable, Equatable {
    private(set) var characterCount: Int = 0
    private(set) var lineBreakCount: Int = 0

    private var materializedFullText: String = ""
    private let maxCommittedSegments: Int

    init(maxCommittedSegments: Int = 64) {
        self.maxCommittedSegments = max(1, maxCommittedSegments)
    }

    /// Diagnostic/testing view of newline-stable chunks.
    ///
    /// Runtime rendering reads `fullText` directly. Keeping this as a computed
    /// view avoids duplicating the full assistant response in both segmented and
    /// materialized storage during long streams.
    var committedSegments: [String] {
        guard !materializedFullText.isEmpty else { return [] }

        var segments: [String] = []
        var start = materializedFullText.startIndex
        var cursor = materializedFullText.startIndex

        while cursor < materializedFullText.endIndex {
            let character = materializedFullText[cursor]
            cursor = materializedFullText.index(after: cursor)

            if character == "\n" {
                segments.append(String(materializedFullText[start..<cursor]))
                start = cursor
            }
        }

        return compactedSegments(segments)
    }

    /// Diagnostic/testing view of the currently unfinished line.
    var tail: String {
        guard !materializedFullText.isEmpty else { return "" }
        guard let lastNewline = materializedFullText.lastIndex(of: "\n") else {
            return materializedFullText
        }
        let start = materializedFullText.index(after: lastNewline)
        guard start < materializedFullText.endIndex else { return "" }
        return String(materializedFullText[start...])
    }

    var hasContent: Bool {
        !materializedFullText.isEmpty
    }

    var fullText: String {
        materializedFullText
    }

    mutating func clear() {
        characterCount = 0
        lineBreakCount = 0
        materializedFullText.removeAll(keepingCapacity: false)
    }

    mutating func append(_ text: String) {
        guard !text.isEmpty else { return }
        characterCount += text.count
        lineBreakCount += text.count(where: { $0 == "\n" })
        materializedFullText.append(contentsOf: text)
    }

    private func compactedSegments(_ segments: [String]) -> [String] {
        guard segments.count > maxCommittedSegments else { return segments }

        let overflowCount = segments.count - maxCommittedSegments + 1
        var compacted = Array(segments.dropFirst(overflowCount))
        compacted.insert(segments.prefix(overflowCount).joined(), at: 0)
        return compacted
    }
}
