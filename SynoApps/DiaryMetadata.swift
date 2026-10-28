import Foundation

struct DiaryMetadata: Codable, Equatable, Sendable {
    var headline = ""
    var mood = ""
    var weather = ""
    var location = ""
    var favorite = false
    var photos: [String] = []

    private enum CodingKeys: String, CodingKey { case headline, mood, weather, location, favorite, photos }

    init() {}

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        headline = try container.decodeIfPresent(String.self, forKey: .headline) ?? ""
        mood = try container.decodeIfPresent(String.self, forKey: .mood) ?? ""
        weather = try container.decodeIfPresent(String.self, forKey: .weather) ?? ""
        location = try container.decodeIfPresent(String.self, forKey: .location) ?? ""
        favorite = try container.decodeIfPresent(Bool.self, forKey: .favorite) ?? false
        photos = try container.decodeIfPresent([String].self, forKey: .photos) ?? []
    }
}

extension DiaryText {
    private static let metadataMarker = "euca-diary-metadata:"

    static func metadata(in html: String) -> DiaryMetadata {
        guard let marker = html.range(of: "<!-- \(metadataMarker)"),
              let end = html[marker.upperBound...].range(of: " -->") else { return DiaryMetadata() }
        let encoded = String(html[marker.upperBound..<end.lowerBound])
        guard let data = Data(base64Encoded: encoded),
              let metadata = try? JSONDecoder().decode(DiaryMetadata.self, from: data) else { return DiaryMetadata() }
        return metadata
    }

    static func updatingMetadata(in html: String, metadata: DiaryMetadata) throws -> String {
        let data = try JSONEncoder().encode(metadata)
        let comment = "<!-- \(metadataMarker)\(data.base64EncodedString()) -->"
        if let marker = html.range(of: "<!-- \(metadataMarker)"),
           let end = html[marker.upperBound...].range(of: " -->") {
            return html.replacingCharacters(in: marker.lowerBound..<end.upperBound, with: comment)
        }
        return html + "\n" + comment
    }

    static func preservingMetadata(in html: String, with newContent: String) -> String {
        guard let marker = html.range(of: "<!-- \(metadataMarker)"),
              let end = html[marker.upperBound...].range(of: " -->") else { return newContent }
        let comment = String(html[marker.lowerBound..<end.upperBound])
        return contentWithoutMetadata(in: newContent) + "\n" + comment
    }

    static func hasMetadata(in html: String) -> Bool {
        guard let marker = html.range(of: "<!-- \(metadataMarker)") else { return false }
        return html[marker.upperBound...].range(of: " -->") != nil
    }

    static func contentWithoutMetadata(in html: String) -> String {
        guard let marker = html.range(of: "<!-- \(metadataMarker)"),
              let end = html[marker.upperBound...].range(of: " -->") else { return html }
        return html.replacingCharacters(in: marker.lowerBound..<end.upperBound, with: "")
    }

    static func backgroundColorHex(in html: String) -> String? {
        guard let range = html.range(of: "背景纯色：(#[0-9A-Fa-f]{6})", options: .regularExpression),
              let hex = html[range].split(separator: "：").last else { return nil }
        return String(hex)
    }

    static func removingBackgroundColor(in html: String) -> String {
        html.replacingOccurrences(of: "<p>背景纯色：#[0-9A-Fa-f]{6}</p>\\n?", with: "", options: .regularExpression)
    }

    static func settingBackgroundColor(in html: String, hex: String?) -> String {
        let stripped = removingBackgroundColor(in: html)
        guard let hex else { return stripped }
        let normalizedHex = hex.hasPrefix("#") ? hex : "#\(hex)"
        return "<p>背景纯色：\(normalizedHex)</p>\n" + stripped
    }
}

extension Note {
    var diaryMetadata: DiaryMetadata { DiaryText.metadata(in: content) }
}
