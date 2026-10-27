import Foundation

struct DiaryMonth: Identifiable, Hashable {
    let notebook: Notebook
    let year: Int
    let month: Int

    var id: String { notebook.id }
    var title: String { notebook.title }
    var yearTitle: String { "\(year)年" }
    var monthTitle: String { "\(month)月" }

    static func parse(_ notebook: Notebook) -> DiaryMonth? {
        guard notebook.stack == LibraryStore.diaryShelfName,
              notebook.category != "stack",
              let match = notebook.title.wholeMatch(of: /(\d{4})年(\d{1,2})月/),
              let year = Int(match.1), let month = Int(match.2),
              (1...12).contains(month) else { return nil }
        return DiaryMonth(notebook: notebook, year: year, month: month)
    }
}

enum DiaryText {
    static let calendar = Calendar.current

    static func notebookTitle(for date: Date = .now) -> String {
        "\(calendar.component(.year, from: date))年\(calendar.component(.month, from: date))月"
    }

    static func noteTitle(for date: Date = .now) -> String {
        "\(calendar.component(.month, from: date))月\(calendar.component(.day, from: date))日"
    }

    static func day(from title: String) -> Int? {
        guard let match = title.wholeMatch(of: /(\d{1,2})月(\d{1,2})日/) else { return nil }
        return Int(match.2)
    }

    static func weekday(for month: DiaryMonth, note: Note) -> String {
        guard let day = day(from: note.title),
              let date = calendar.date(from: DateComponents(year: month.year, month: month.month, day: day)) else { return "" }
        return date.formatted(.dateTime.weekday(.abbreviated).locale(Locale(identifier: "zh_CN")))
    }

    static func imageSource(in html: String, after marker: String? = nil) -> String? {
        imageSources(in: html, after: marker).first
    }

    static func imageSources(in html: String, after marker: String? = nil) -> [String] {
        let source: String
        if let marker, let range = html.range(of: marker) {
            source = String(html[range.upperBound...])
        } else {
            source = html
        }
        let expression = try? NSRegularExpression(pattern: "<img[^>]+>")
        let matches = expression?.matches(in: source, range: NSRange(source.startIndex..., in: source)) ?? []
        var results: [String] = []
        for match in matches {
            guard let img = Range(match.range, in: source) else { continue }
            let tag = source[img]
            guard let src = tag.range(of: "src\\s*=\\s*([\"'])(.*?)\\1", options: .regularExpression),
                  let quoteStart = tag[src].first(where: { $0 == "\"" || $0 == "'" }) else { continue }
            let value = tag[src].drop(while: { $0 != quoteStart }).dropFirst()
            guard let end = value.firstIndex(of: quoteStart) else { continue }
            let result = String(value[..<end])
                .replacingOccurrences(of: "&amp;", with: "&")
                .replacingOccurrences(of: "&quot;", with: "\"")
                .trimmingCharacters(in: .whitespacesAndNewlines)
            if !result.isEmpty { results.append(result) }
        }
        return results
    }

    static func removingImages(in html: String) -> String {
        guard let expression = try? NSRegularExpression(pattern: "<img[^>]+>") else { return html }
        let range = NSRange(html.startIndex..., in: html)
        return expression.stringByReplacingMatches(in: html, range: range, withTemplate: "")
    }
}

enum DiaryRoute: Hashable {
    case month(String)
    case note(String)
    case search
}
