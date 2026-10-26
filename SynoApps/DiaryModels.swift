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
        let source: String
        if let marker, let range = html.range(of: marker) {
            source = String(html[range.upperBound...])
        } else {
            source = html
        }
        guard let img = source.range(of: "<img[^>]+>", options: .regularExpression),
              let src = source[img].range(of: "src\\s*=\\s*([\"'])(.*?)\\1", options: .regularExpression),
              let quoteStart = source[src].first(where: { $0 == "\"" || $0 == "'" }) else { return nil }
        let value = source[src].drop(while: { $0 != quoteStart }).dropFirst()
        guard let end = value.firstIndex(of: quoteStart) else { return nil }
        return String(value[..<end])
            .replacingOccurrences(of: "&amp;", with: "&")
            .replacingOccurrences(of: "&quot;", with: "\"")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

enum DiaryRoute: Hashable {
    case month(String)
    case note(String)
}
