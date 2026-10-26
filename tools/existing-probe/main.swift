import Foundation

@main
struct ExistingProbe {
    static func main() async {
        let env = ProcessInfo.processInfo.environment
        guard let account = env["DEV_ACCOUNT"], let password = env["DEV_PASSWORD"], let id = env["QC_ID"] else { return }
        let api = SynologyAPI()
        do {
            let session = try await api.login(server: id, useHTTPS: true, quickConnect: true, account: account, password: password, otp: nil, deviceID: UUID().uuidString, rememberDevice: false)
            let library = try await api.fetchLibrary(session: session)
            guard let summary = library.notes.first(where: { $0.title == "内容也是新的" }) else { return }
            var note = try await api.getNote(id: summary.id, session: session)
            let variants: [(String, Bool, [String: JSONValue])] = [
                ("title", true, ["title": .string(note.title)]),
                ("content", true, ["content": .string(note.content), "brief": .string(note.brief)]),
                ("recycle", true, ["recycle": .bool(note.isInTrash)]),
                ("commit", true, ["commit_msg": .object(["device": .string("SynoApps probe")])]),
                ("parent", true, ["parent_id": .string(note.parentID)]),
                ("all", true, ["title": .string(note.title), "content": .string(note.content), "brief": .string(note.preview), "recycle": .bool(note.isInTrash), "commit_msg": .object(["device": .string("SynoApps probe")])]),
                ("no_ver", false, ["title": .string(note.title)]),
                ("no_conflict_check", true, ["title": .string(note.title), "check_conflict": .bool(false)]),
                ("no_ver_no_conflict_check", false, ["title": .string(note.title), "check_conflict": .bool(false)])
            ]
            for (name, includeVersion, extra) in variants {
                var params: [String: JSONValue] = ["object_id": .string(note.id)]
                if includeVersion { params["ver"] = .string(note.version) }
                params.merge(extra) { _, new in new }
                do {
                    _ = try await api.request(session: session, api: "SYNO.NoteStation.Note", version: 3, method: "set", params: params)
                    print(name, "PASS")
                    note = try await api.getNote(id: note.id, session: session)
                } catch { print(name, "FAIL", error.localizedDescription) }
            }
            await api.logout(session: session)
        } catch { print("SETUP_FAIL", error.localizedDescription) }
    }
}
