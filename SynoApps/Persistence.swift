import Foundation
import Security

struct SessionStore: Sendable {
    private let service = "com.synoapps.notestation.session"
    private let account = "current-session"

    func save(_ session: SynologySession) throws {
        let data = try JSONEncoder().encode(session)
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
        let attributes: [String: Any] = [
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlock
        ]
        var status = SecItemUpdate(query as CFDictionary, attributes as CFDictionary)
        if status == errSecItemNotFound {
            var item = query
            item.merge(attributes) { _, new in new }
            status = SecItemAdd(item as CFDictionary, nil)
        }
        guard status == errSecSuccess else { throw SynologyError.network("无法安全保存登录会话（\(status)）。") }
    }

    func restore() -> SynologySession? {
        var query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        query[kSecAttrSynchronizable as String] = kSecAttrSynchronizableAny
        var result: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess,
              let data = result as? Data else { return nil }
        return try? JSONDecoder().decode(SynologySession.self, from: data)
    }

    func clear() {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
        SecItemDelete(query as CFDictionary)
    }
}

struct LibraryCache: Sendable {
    private struct Payload: Codable {
        var notebooks: [Notebook]
        var notes: [Note]
        var tags: [NoteTag]
    }

    func load(isDemo: Bool) -> LibraryPayload? {
        guard let data = try? Data(contentsOf: fileURL(isDemo: isDemo)),
              let payload = try? JSONDecoder().decode(Payload.self, from: data) else { return nil }
        return LibraryPayload(notebooks: payload.notebooks, notes: payload.notes, tags: payload.tags)
    }

    func save(_ payload: LibraryPayload, isDemo: Bool) {
        let url = fileURL(isDemo: isDemo)
        do {
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            let data = try JSONEncoder().encode(Payload(notebooks: payload.notebooks, notes: payload.notes, tags: payload.tags))
            try data.write(to: url, options: .atomic)
        } catch {
            // A failed cache write must never discard the in-memory note.
        }
    }

    func clear(isDemo: Bool) {
        try? FileManager.default.removeItem(at: fileURL(isDemo: isDemo))
    }

    private func fileURL(isDemo: Bool) -> URL {
        let directory = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("SynoApps", isDirectory: true)
        return directory.appendingPathComponent(isDemo ? "preview-library.json" : "library.json")
    }
}
