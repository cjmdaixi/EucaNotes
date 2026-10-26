import Foundation

@main
struct ExistingSmoke {
    static func main() async {
        let env = ProcessInfo.processInfo.environment
        guard let account = env["DEV_ACCOUNT"], let password = env["DEV_PASSWORD"], let id = env["QC_ID"] else { return }
        let api = SynologyAPI()
        do {
            let session = try await api.login(server: id, useHTTPS: true, quickConnect: true, account: account, password: password, otp: nil, deviceID: UUID().uuidString, rememberDevice: false)
            let library = try await api.fetchLibrary(session: session)
            guard let summary = library.notes.first(where: { $0.title == "内容也是新的" }) else {
                print("NOTE_NOT_FOUND")
                return
            }
            let original = try await api.getNote(id: summary.id, session: session)
            print("ORIGINAL version", original.version, "parent", original.parentID, "content length", original.content.count, "trash", original.isInTrash)
            do {
                _ = try await api.request(session: session, api: "SYNO.NoteStation.Note", version: 3, method: "set", params: ["object_id": .string(original.id), "title": .string(original.title)])
                print("TITLE_ONLY_PASS")
                var edited = original
                edited.content += "<p>真机保存兼容性验证</p>"
                do {
                    let saved = try await api.saveNote(edited, session: session)
                    print("FULL_SAVE_PASS", saved.version)
                    _ = try await api.saveNote(original, session: session)
                    print("ORIGINAL_CONTENT_RESTORED")
                } catch {
                    print("FULL_SAVE_FAIL", error.localizedDescription)
                    let current = try await api.getNote(id: original.id, session: session)
                    var restore = original
                    restore.version = current.version
                    _ = try? await api.saveNote(restore, session: session)
                }
            } catch { print("TITLE_ONLY_FAIL", error.localizedDescription) }
            await api.logout(session: session)
        } catch { print("SETUP_FAIL", error.localizedDescription) }
    }
}
