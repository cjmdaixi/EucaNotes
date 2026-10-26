import Foundation

@main
struct QuickConnectSmoke {
    static func main() async {
        let resolver = QuickConnectResolver()
        do {
            _ = try await resolver.resolve(id: "invalid id with spaces", useHTTPS: true)
            print("FAIL: malformed ID was accepted")
        } catch QuickConnectError.invalidID {
            print("PASS: malformed ID rejected locally")
        } catch {
            print("FAIL: unexpected malformed-ID error: \(error)")
        }

        let missingID = "synoapps-missing-9f3c7a2b"
        do {
            let host = try await resolver.resolve(id: missingID, useHTTPS: true)
            print("UNEXPECTED: missing ID resolved to \(host)")
        } catch QuickConnectError.notFound {
            print("PASS: QuickConnect lookup completed and missing ID returned notFound")
        } catch {
            print("LOOKUP_INCOMPLETE: \(error.localizedDescription)")
        }
    }
}
