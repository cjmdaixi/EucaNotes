import Foundation

@main
struct SaveProbe {
    static func main() async {
        let env = ProcessInfo.processInfo.environment
        guard let account = env["DEV_ACCOUNT"], let password = env["DEV_PASSWORD"], let id = env["QC_ID"] else { return }
        let api = SynologyAPI()
        do {
            let session = try await api.login(server: id, useHTTPS: true, quickConnect: true, account: account, password: password, otp: nil, deviceID: UUID().uuidString, rememberDevice: false)
            let library = try await api.fetchLibrary(session: session)
            guard let notebook = library.notebooks.first else { return }
            let variants: [(String, [String: JSONValue])] = [
                ("title_only", [:]),
                ("content", ["content": .string("<p>probe</p>"), "brief": .string("probe")]),
                ("mtime", ["mtime": .number(Date.now.timeIntervalSince1970)]),
                ("parent", ["parent_id": .string(notebook.id)]),
                ("recycle", ["recycle": .bool(false)]),
                ("commit", ["commit_msg": .object(["device": .string("SynoApps probe")])]),
                ("empty_tag", ["tag": .array([])])
            ]
            for (name, extra) in variants {
                let note = try await api.createNote(title: "保存参数测试", notebookID: notebook.id, session: session)
                var params: [String: JSONValue] = ["object_id": .string(note.id), "ver": .string(note.version), "title": .string("保存参数测试-已修改")]
                params.merge(extra) { _, new in new }
                do {
                    _ = try await api.request(session: session, api: "SYNO.NoteStation.Note", version: 3, method: "set", params: params)
                    print(name, "PASS")
                } catch {
                    print(name, "FAIL", error.localizedDescription)
                }
                try? await api.deleteNote(note, session: session)
                if let trashed = try? await api.getNote(id: note.id, session: session) {
                    try? await api.deleteNote(trashed, session: session)
                }
            }
            await api.logout(session: session)
        } catch { print("SETUP_FAIL", error.localizedDescription) }
    }
}
