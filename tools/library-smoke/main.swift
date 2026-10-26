import Foundation

@main
struct LibrarySmoke {
    static func main() async {
        let session = SynologySession(baseURL: "http://127.0.0.1:18765", sid: "smoke", account: "smoke")
        do {
            let payload = try await SynologyAPI().fetchLibrary(session: session)
            let target = payload.notes.filter { $0.parentID == "dragon-diary" }
            print("TOTAL_NOTES", payload.notes.count)
            print("TARGET_NOTES", target.count)
            print("TARGET_BOOK", payload.notebooks.first { $0.id == "dragon-diary" }?.title ?? "missing")
            guard payload.notes.count == 24, target.count == 23 else {
                print("FAIL: shared notes were not merged correctly")
                return
            }
            print("PASS: owned and shared notes merged with the expected parent_id")
        } catch {
            print("FAIL: \(error.localizedDescription)")
        }
    }
}
