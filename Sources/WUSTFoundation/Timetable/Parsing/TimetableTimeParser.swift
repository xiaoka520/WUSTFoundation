import Foundation

struct TimetableTimeParser {
    func parseNumberList(
        from text: String,
        upperBound: Int
    ) throws -> [Int] {
        guard upperBound > 0,
              !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw TimetableError.invalidNumberList
        }
        var result = Set<Int>()
        let segments = text.split(
            separator: ",",
            omittingEmptySubsequences: false
        )
        for segment in segments {
            let part = segment.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !part.isEmpty else {
                throw TimetableError.invalidNumberList
            }
            let bounds = part.split(
                separator: "-",
                omittingEmptySubsequences: false
            )

            switch bounds.count {
            case 1:
                let valueText = bounds[0].trimmingCharacters(
                    in: .whitespacesAndNewlines
                )
                guard !valueText.isEmpty,
                    valueText.allSatisfy({ character in character.isNumber })
                else {
                    throw TimetableError.invalidNumberList
                }
                guard let value = Int(valueText), value >= 1,
                    value <= upperBound
                else {
                    throw TimetableError.invalidNumberList
                }
                result.insert(value)
            case 2:
                let startText = bounds[0].trimmingCharacters(
                    in: .whitespacesAndNewlines
                )
                let endText = bounds[1].trimmingCharacters(
                    in: .whitespacesAndNewlines
                )
                guard !startText.isEmpty,
                      !endText.isEmpty,
                      startText.allSatisfy({ character in character.isNumber }),
                      endText.allSatisfy({ character in character.isNumber }) else {
                    throw TimetableError.invalidNumberList
                }
                guard let start = Int(startText),
                      let end = Int(endText),
                      start >= 1,
                      start <= end,
                      end <= upperBound else {
                    throw TimetableError.invalidNumberList
                }
                result.formUnion(start...end)
            default:
                throw TimetableError.invalidNumberList
            }
        }
        return result.sorted()
    }

    func parse(
        from text: String,
        maxWeek: Int,
        maxSection: Int
    ) throws -> (weeks: [Int], sections: [Int]) {
        let cleanedText = text.trimmingCharacters(in: .whitespacesAndNewlines)
        let parts = cleanedText.components(separatedBy: "(周)[")
        guard parts.count == 2, parts[1].hasSuffix("节]") else {
            throw TimetableError.invalidTimeFormat
        }
        let weekText = parts[0]
        let sectionText = String(parts[1].dropLast(2))
        let weeks = try parseNumberList(from: weekText, upperBound: maxWeek)
        let sections = try parseNumberList(from: sectionText, upperBound: maxSection)
        return (weeks: weeks, sections: sections)
    }
}
