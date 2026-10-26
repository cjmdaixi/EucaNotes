import Foundation

@main
struct LiveSmoke {
    static func main() async {
        guard let account = ProcessInfo.processInfo.environment["DEV_ACCOUNT"],
              let password = ProcessInfo.processInfo.environment["DEV_PASSWORD"],
              let quickConnectID = ProcessInfo.processInfo.environment["QC_ID"] else {
            print("FAIL: missing test environment")
            return
        }
        let api = SynologyAPI()
        var session: SynologySession?
        var testNote: Note?
        do {
            let loggedIn = try await api.login(server: quickConnectID, useHTTPS: true, quickConnect: true, account: account, password: password, otp: nil, deviceID: UUID().uuidString, rememberDevice: false)
            session = loggedIn
            print("PASS: QuickConnect login")
            let library = try await api.fetchLibrary(session: loggedIn)
            print("LIBRARY", library.notebooks.count, library.notes.count, library.tags.count)
            guard let notebook = library.notebooks.first else {
                print("FAIL: no writable notebook available")
                return
            }
            var note = try await api.createNote(title: "SynoApps 测试笔记（可删除）", notebookID: notebook.id, session: loggedIn)
            testNote = note
            print("PASS: created test note; version length", note.version.count)
            note.title = "SynoApps 测试笔记（已编辑）"
            note.content = ProcessInfo.processInfo.environment["TEST_HTML"] ?? "<h2>端到端验证</h2><p>创建、读取、编辑、保存、恢复与删除。</p>"
            note.modifiedAt = .now
            let saved = try await api.saveNote(note, session: loggedIn)
            testNote = saved
            guard saved.title == note.title, saved.content.contains("端到端验证"), saved.version.count == 40 else {
                print("FAIL: saved content or version mismatch")
                return
            }
            print("PASS: edited and saved with version", saved.version.prefix(8))

            try await api.deleteNote(saved, session: loggedIn)
            let trashed = try await api.getNote(id: saved.id, session: loggedIn)
            testNote = trashed
            guard trashed.isInTrash else {
                print("FAIL: note did not enter trash")
                return
            }
            print("PASS: moved to trash")

            let restored = try await api.restoreNote(id: trashed.id, session: loggedIn)
            testNote = restored
            guard !restored.isInTrash else {
                print("FAIL: note did not restore")
                return
            }
            print("PASS: restored from trash")

            try await api.deleteNote(restored, session: loggedIn)
            let trashAgain = try await api.getNote(id: restored.id, session: loggedIn)
            try await api.deleteNote(trashAgain, session: loggedIn)
            testNote = nil
            print("PASS: permanently deleted test note")
            await api.logout(session: loggedIn)
            session = nil
        } catch {
            print("FAIL:", error.localizedDescription)
            if let session, let note = testNote {
                // Best-effort cleanup of only the note created by this test.
                if !note.isInTrash { try? await api.deleteNote(note, session: session) }
                if let trashed = try? await api.getNote(id: note.id, session: session) {
                    try? await api.deleteNote(trashed, session: session)
                }
                await api.logout(session: session)
            }
        }
    }
}
