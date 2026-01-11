import UIKit

// MARK: - Drawing Mode

enum DrawingMode: String {
    case view = "view"
    case draw = "draw"
    case erase = "erase"
    case highlight = "highlight"
}

// MARK: - Drawing Stroke

struct DrawingStroke: Codable {
    let id: String
    let color: String
    let width: CGFloat
    let opacity: CGFloat
    let path: [[CGFloat]]
}

// MARK: - Per-Page Strokes Container

/// Container for strokes organized by page index
struct PageStrokes: Codable {
    var pages: [Int: [DrawingStroke]]

    init() {
        pages = [:]
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        // Decode as dictionary with string keys, convert to int
        let stringKeyedDict = try container.decode([String: [DrawingStroke]].self)
        pages = [:]
        for (key, value) in stringKeyedDict {
            if let intKey = Int(key) {
                pages[intKey] = value
            }
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        // Encode as dictionary with string keys
        var stringKeyedDict: [String: [DrawingStroke]] = [:]
        for (key, value) in pages {
            stringKeyedDict[String(key)] = value
        }
        try container.encode(stringKeyedDict)
    }

    mutating func setStrokes(_ strokes: [DrawingStroke], forPage page: Int) {
        pages[page] = strokes
    }

    func getStrokes(forPage page: Int) -> [DrawingStroke] {
        return pages[page] ?? []
    }

    mutating func addStroke(_ stroke: DrawingStroke, toPage page: Int) {
        if pages[page] == nil {
            pages[page] = []
        }
        pages[page]?.append(stroke)
    }

    mutating func removeStroke(withId id: String, fromPage page: Int) -> Bool {
        guard var pageStrokes = pages[page] else { return false }
        if let index = pageStrokes.firstIndex(where: { $0.id == id }) {
            pageStrokes.remove(at: index)
            pages[page] = pageStrokes
            return true
        }
        return false
    }

    mutating func clearStrokes(forPage page: Int) {
        pages[page] = []
    }

    mutating func clearAllStrokes() {
        pages = [:]
    }

    func getAllStrokes() -> [Int: [DrawingStroke]] {
        return pages
    }
}
