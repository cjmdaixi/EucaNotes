import Foundation

struct DiaryMetadata: Codable, Equatable, Sendable {
    var headline = ""
    var mood = ""
    var weather = ""
    var location = ""
    var favorite = false
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

    static func hasMetadata(in html: String) -> Bool {
        guard let marker = html.range(of: "<!-- \(metadataMarker)") else { return false }
        return html[marker.upperBound...].range(of: " -->") != nil
    }

    static func contentWithoutMetadata(in html: String) -> String {
        guard let marker = html.range(of: "<!-- \(metadataMarker)"),
              let end = html[marker.upperBound...].range(of: " -->") else { return html }
        return html.replacingCharacters(in: marker.lowerBound..<end.upperBound, with: "")
    }
}

extension Note {
    var diaryMetadata: DiaryMetadata { DiaryText.metadata(in: content) }
}
