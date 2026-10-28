import Foundation

struct LibraryPayload: Sendable {
    var notebooks: [Notebook]
    var notes: [Note]
    var tags: [NoteTag]
}

nonisolated struct SynologyAPI: Sendable {
    private let decoder = JSONDecoder()

    func normalizedBaseURL(_ input: String, useHTTPS: Bool) throws -> String {
        var value = input.trimmingCharacters(in: .whitespacesAndNewlines)
        if value.isEmpty { throw SynologyError.invalidServer }
        if !value.contains("://") { value = (useHTTPS ? "https://" : "http://") + value }
        guard let components = URLComponents(string: value),
              let scheme = components.scheme?.lowercased(),
              ["http", "https"].contains(scheme),
              components.host != nil else { throw SynologyError.invalidServer }
        return value.hasSuffix("/") ? String(value.dropLast()) : value
    }

    func login(server: String, useHTTPS: Bool, quickConnect: Bool = false, account: String, password: String, otp: String?, deviceID: String?, rememberDevice: Bool) async throws -> SynologySession {
        let baseURL = quickConnect
            ? try await QuickConnectResolver().resolve(id: server, useHTTPS: useHTTPS)
            : try normalizedBaseURL(server, useHTTPS: useHTTPS)
        let info = try await request(
            baseURL: baseURL,
            path: "webapi/query.cgi",
            api: "SYNO.API.Info",
            version: 1,
            method: "query",
            params: ["query": .string("SYNO.API.Auth")],
            sid: nil,
            useGET: true
        )
        let authInfo = info["SYNO.API.Auth"]
        let path = authInfo?["path"]?.stringValue ?? "auth.cgi"
        let maxVersion = authInfo?["maxVersion"]?.intValue ?? 3
        let version = max(1, min(maxVersion, 6))
        var params: [String: JSONValue] = [
            "format": .string("sid"),
            "session": .string("notestation"),
            "account": .string(account),
            "passwd": .string(password)
        ]
        if let otp, !otp.isEmpty { params["otp_code"] = .string(otp) }
        if version >= 6 {
            if let deviceID, !deviceID.isEmpty { params["device_id"] = .string(deviceID) }
            if rememberDevice {
                params["enable_device_token"] = .string("yes")
                params["device_name"] = .string("SynoApps for iOS")
            }
        }
        let data = try await request(
            baseURL: baseURL,
            path: "webapi/" + path,
            api: "SYNO.API.Auth",
            version: version,
            method: "login",
            params: params,
            sid: nil
        )
        guard let sid = data["sid"]?.stringValue, !sid.isEmpty else { throw SynologyError.invalidResponse }
        return SynologySession(baseURL: baseURL, sid: sid, did: data["did"]?.stringValue ?? deviceID, account: account)
    }

    func fetchLibrary(session: SynologySession) async throws -> LibraryPayload {
        async let notebooksData = request(session: session, api: "SYNO.NoteStation.Notebook", version: 2, method: "list")
        // Full-library synchronization must use Note v2 without fast_result.
        // The v3 fast_result path is only an incremental supplement to the
        // official desktop client's existing offline database; by itself it
        // can return a small, predominantly recycled subset of the library.
        async let notesData = request(
            session: session,
            api: "SYNO.NoteStation.Note",
            version: 2,
            method: "list",
            params: [
                "sort_by": .string("mtime"),
                "sort_direction": .string("desc"),
                "limit": .number(1000)
            ]
        )
        // Note Station returns other people's shared/smart notes separately.
        // The official client merges this request with the owned-note list.
        async let sharedNotesData = try? request(
            session: session,
            api: "SYNO.NoteStation.Note",
            version: 3,
            method: "list",
            params: [
                "filter": .object(["not_owner": .string(session.account)]),
                "field": .object(["commit_msg": .bool(true)]),
                "smart_id": .string("*"),
                "perm_from": .string("smart"),
                "sort_by": .string("mtime"),
                "sort_direction": .string("desc"),
                "limit": .number(1000)
            ]
        )
        async let tagsData = request(session: session, api: "SYNO.NoteStation.Tag", version: 1, method: "list")
        async let sharedTagsData = try? request(
            session: session,
            api: "SYNO.NoteStation.Tag",
            version: 2,
            method: "list",
            params: ["filter": .object(["not_owner": .string(session.account)])]
        )
        let (notebookJSON, noteJSON, sharedNoteJSON, tagJSON, sharedTagJSON) = try await (notebooksData, notesData, sharedNotesData, tagsData, sharedTagsData)
        let ownedNotes = noteJSON["notes"]?.arrayValue.map(Note.init) ?? []
        let sharedNotes = sharedNoteJSON?["notes"]?.arrayValue.map(Note.init) ?? []
        let ownedTags = tagJSON["tags"]?.arrayValue.map(NoteTag.init) ?? []
        let sharedTags = sharedTagJSON?["tags"]?.arrayValue.map(NoteTag.init) ?? []
        return LibraryPayload(
            notebooks: (notebookJSON["notebooks"] ?? notebookJSON["notebook"])?.arrayValue.map(Notebook.init) ?? [],
            notes: mergeByID(ownedNotes, sharedNotes),
            tags: mergeByID(ownedTags, sharedTags)
        )
    }

    private func mergeByID<T: Identifiable>(_ owned: [T], _ shared: [T]) -> [T] {
        var ids = Set(owned.map(\.id))
        return owned + shared.filter { ids.insert($0.id).inserted }
    }

    func getNote(id: String, session: SynologySession) async throws -> Note {
        let data = try await request(session: session, api: "SYNO.NoteStation.Note", version: 3, method: "get", params: ["object_id": .string(id)])
        // Some Note Station builds return the note directly, others wrap it in data[0].
        let object = data.arrayValue.first ?? data["note"] ?? data
        guard object["object_id"] != nil else { throw SynologyError.invalidResponse }
        return Note(json: object)
    }

    func createNotebook(title: String, stack: String, session: SynologySession) async throws -> Notebook {
        // The official client creates a notebook first, then assigns its stack.
        // Assigning a new stack name also creates the bookshelf on the NAS.
        let data = try await request(
            session: session,
            api: "SYNO.NoteStation.Notebook",
            version: 2,
            method: "create",
            params: ["title": .string(title), "commit_msg": .object(["device": .string("Euca Diary for iOS")])]
        )
        guard let id = data["object_id"]?.stringValue else { throw SynologyError.invalidResponse }
        if !stack.isEmpty {
            _ = try await request(
                session: session,
                api: "SYNO.NoteStation.Notebook",
                version: 2,
                method: "set",
                params: ["object_id": .string(id), "title": .string(title), "stack": .string(stack)]
            )
        }
        let result = try await request(session: session, api: "SYNO.NoteStation.Notebook", version: 2, method: "get", params: ["object_id": .string(id)])
        let object = result["notebook"] ?? result
        guard object["object_id"] != nil else { throw SynologyError.invalidResponse }
        return Notebook(json: object)
    }

    func attachmentDownloadURL(noteID: String, fileID: String, noteVersion: String, session: SynologySession) -> String? {
        var components = URLComponents(string: session.baseURL + "/webapi/entry.cgi")
        var query = [
            URLQueryItem(name: "api", value: "SYNO.NoteStation.Note"),
            URLQueryItem(name: "version", value: "3"),
            URLQueryItem(name: "method", value: "download"),
            URLQueryItem(name: "object_id", value: noteID),
            URLQueryItem(name: "file_id", value: fileID),
            URLQueryItem(name: "format", value: "raw")
        ]
        if !noteVersion.isEmpty { query.append(URLQueryItem(name: "ver", value: noteVersion)) }
        components?.queryItems = query
        return components?.string
    }

    func imageData(source: String, session: SynologySession) async throws -> Data {
        if source.hasPrefix("data:image"), let comma = source.firstIndex(of: ",") {
            let encoded = String(source[source.index(after: comma)...])
            guard let data = Data(base64Encoded: encoded) else { throw SynologyError.invalidResponse }
            return data
        }
        var resolved = source
        if !resolved.hasPrefix("http://") && !resolved.hasPrefix("https://") {
            resolved = session.baseURL + (resolved.hasPrefix("/") ? resolved : "/" + resolved)
        }
        guard var components = URLComponents(string: resolved) else { throw SynologyError.invalidResponse }
        var query = components.queryItems ?? []
        if !query.contains(where: { $0.name == "_sid" }) { query.append(URLQueryItem(name: "_sid", value: session.sid)) }
        components.queryItems = query
        guard let url = components.url else { throw SynologyError.invalidResponse }
        var request = URLRequest(url: url)
        request.timeoutInterval = 25
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode), !data.isEmpty else {
            throw SynologyError.network("无法载入月卡背景照片。")
        }
        return data
    }

    func addPhoto(to note: Note, jpegData: Data, session: SynologySession) async throws -> Note {
        let reference = Data(UUID().uuidString.utf8).base64EncodedString()
        let fieldName = "photo_" + UUID().uuidString.replacingOccurrences(of: "-", with: "")
        var metadata = note.diaryMetadata
        metadata.photos.append("attachment://\(reference)")
        let html = try DiaryText.updatingMetadata(in: note.content, metadata: metadata)
        let fields: [String: JSONValue] = [
            "object_id": .string(note.id),
            "title": .string(note.title),
            "content": .string(html),
            "brief": .string(note.preview),
            "commit_msg": .object(["device": .string("Euca Diary for iOS"), "listable": .bool(false)]),
            "attachment": .array([.object(["action": .string("create"), "name": .string(fieldName), "format": .string("raw"), "ref": .string(reference), "rotate": .bool(true)])])
        ]
        try await multipartRequest(session: session, fields: fields, fileField: fieldName, fileData: jpegData)
        return try await getNote(id: note.id, session: session)
    }

    func setMonthBackgroundPhoto(note: Note, jpegData: Data, session: SynologySession) async throws -> Note {
        let reference = Data(UUID().uuidString.utf8).base64EncodedString()
        let fieldName = "background_" + UUID().uuidString.replacingOccurrences(of: "-", with: "")
        let embedded = "data:image/jpeg;base64," + jpegData.base64EncodedString()
        var content = DiaryText.removingImages(in: DiaryText.removingBackgroundColor(in: note.content))
        if !content.contains("背景照片：") { content = "<p>背景照片：</p>" + content }
        let html = content + "\n<p><img ref=\"\(reference)\" src=\"\(embedded)\"></p>"
        let fields: [String: JSONValue] = [
            "object_id": .string(note.id),
            "title": .string(note.title),
            "content": .string(html),
            "brief": .string(note.preview),
            "commit_msg": .object(["device": .string("Euca Diary for iOS"), "listable": .bool(false)]),
            "attachment": .array([.object(["action": .string("create"), "name": .string(fieldName), "format": .string("raw"), "ref": .string(reference), "rotate": .bool(true)])])
        ]
        try await multipartRequest(session: session, fields: fields, fileField: fieldName, fileData: jpegData)
        return try await getNote(id: note.id, session: session)
    }

    private func multipartRequest(session: SynologySession, fields: [String: JSONValue], fileField: String, fileData: Data) async throws {
        guard var components = URLComponents(string: session.baseURL + "/webapi/entry.cgi") else { throw SynologyError.invalidServer }
        components.queryItems = [
            URLQueryItem(name: "api", value: "SYNO.NoteStation.Note"),
            URLQueryItem(name: "version", value: "3"),
            URLQueryItem(name: "method", value: "set"),
            URLQueryItem(name: "_sid", value: session.sid)
        ]
        guard let url = components.url else { throw SynologyError.invalidServer }
        let boundary = "EucaDiary-" + UUID().uuidString
        var body = Data()
        for (name, value) in fields {
            body.append(Data("--\(boundary)\r\nContent-Disposition: form-data; name=\"\(name)\"\r\n\r\n".utf8))
            let encoded = try JSONEncoder().encode(value)
            body.append(encoded)
            body.append(Data("\r\n".utf8))
        }
        body.append(Data("--\(boundary)\r\nContent-Disposition: form-data; name=\"\(fileField)\"; filename=\"photo.jpg\"\r\nContent-Type: image/jpeg\r\n\r\n".utf8))
        body.append(fileData)
        body.append(Data("\r\n--\(boundary)--\r\n".utf8))
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = 60
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        request.httpBody = body
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw SynologyError.network("照片上传失败，请检查网络连接。")
        }
        let envelope = try decoder.decode(JSONValue.self, from: data)
        if envelope["success"]?.boolValue != true {
            throw SynologyError.api("SYNO.NoteStation.Note", envelope["error"]?["code"]?.intValue ?? -1)
        }
    }

    func createNote(title: String, notebookID: String, session: SynologySession) async throws -> Note {
        let content = "<p><br></p>"
        let data = try await request(
            session: session,
            api: "SYNO.NoteStation.Note",
            version: 3,
            method: "create",
            params: [
                "title": .string(title),
                "parent_id": .string(notebookID),
                "encrypt": .bool(false),
                "content": .string(content),
                "brief": .string(""),
                "commit_msg": .object(["device": .string("SynoApps for iOS"), "first_version": .bool(true), "listable": .bool(false)])
            ]
        )
        guard let id = data["object_id"]?.stringValue else { throw SynologyError.invalidResponse }
        return try await getNote(id: id, session: session)
    }

    @discardableResult
    func saveNote(_ note: Note, session: SynologySession, previousParentID: String? = nil, includeTags: Bool = false) async throws -> Note {
        // Some Note Station versions reject a valid Git hash in `ver` for
        // existing notes (error 114). The set endpoint accepts updates without
        // it, so do not force that optional field into every save request.
        var params: [String: JSONValue] = [
            "object_id": .string(note.id),
            "title": .string(note.title),
            "content": .string(note.content),
            "brief": .string(note.preview),
            "recycle": .bool(note.isInTrash),
            "commit_msg": .object(["device": .string("SynoApps for iOS")])
        ]
        if let previousParentID, previousParentID != note.parentID {
            params["parent_id"] = .string(note.parentID)
        }
        if includeTags { params["tag"] = .array(note.tags.map(JSONValue.string)) }
        _ = try await request(session: session, api: "SYNO.NoteStation.Note", version: 3, method: "set", params: params)
        return try await getNote(id: note.id, session: session)
    }

    func deleteNote(_ note: Note, session: SynologySession) async throws {
        _ = try await request(
            session: session,
            api: "SYNO.NoteStation.Note",
            version: 3,
            method: "delete",
            params: ["object_id": .string(note.id), "recycle": .bool(!note.isInTrash)]
        )
    }

    func restoreNote(id: String, session: SynologySession) async throws -> Note {
        _ = try await request(session: session, api: "SYNO.NoteStation.Note", version: 3, method: "restore", params: ["object_id": .string(id)])
        return try await getNote(id: id, session: session)
    }

    func logout(session: SynologySession) async {
        _ = try? await request(baseURL: session.baseURL, path: "webapi/auth.cgi", api: "SYNO.API.Auth", version: 1, method: "logout", params: ["session": .string("notestation")], sid: session.sid)
    }

    func request(session: SynologySession, api: String, version: Int, method: String, params: [String: JSONValue] = [:]) async throws -> JSONValue {
        try await request(baseURL: session.baseURL, path: "webapi/entry.cgi", api: api, version: version, method: method, params: params, sid: session.sid)
    }

    private func request(baseURL: String, path: String, api: String, version: Int, method: String, params: [String: JSONValue], sid: String?, useGET: Bool = false) async throws -> JSONValue {
        guard let url = URL(string: baseURL + "/" + path) else { throw SynologyError.invalidServer }
        var fields = params.mapValues(formString)
        fields["api"] = api
        fields["version"] = String(version)
        fields["method"] = method
        if let sid { fields["_sid"] = sid }
        var request = URLRequest(url: url)
        request.timeoutInterval = 25
        request.setValue("application/x-www-form-urlencoded; charset=UTF-8", forHTTPHeaderField: "Content-Type")
        request.setValue("SynoApps/1.0", forHTTPHeaderField: "User-Agent")
        let body = fields.map { key, value in
            escape(key) + "=" + escape(value)
        }.joined(separator: "&")
        if useGET {
            var components = URLComponents(url: url, resolvingAgainstBaseURL: false)
            components?.query = body
            request.url = components?.url
            request.httpMethod = "GET"
        } else {
            request.httpMethod = "POST"
            request.httpBody = Data(body.utf8)
        }
        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await URLSession.shared.data(for: request)
        } catch is CancellationError {
            throw CancellationError()
        } catch let error as URLError where error.code == .cancelled {
            throw error
        } catch {
            throw SynologyError.network("无法连接服务器：\(error.localizedDescription)")
        }
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw SynologyError.network("服务器连接失败（HTTP \((response as? HTTPURLResponse)?.statusCode ?? 0)）。")
        }
        let envelope: JSONValue
        do { envelope = try decoder.decode(JSONValue.self, from: data) }
        catch { throw SynologyError.invalidResponse }
        if envelope["success"]?.boolValue == true { return envelope["data"] ?? .object([:]) }
        let code = envelope["error"]?["code"]?.intValue ?? -1
        throw SynologyError.api(api, code)
    }

    private func formString(_ value: JSONValue) -> String {
        switch value {
        case .string(let string): return string
        case .number(let number): return number.rounded() == number ? String(Int(number)) : String(number)
        case .bool(let bool): return bool ? "true" : "false"
        case .null: return ""
        default:
            let data = try? JSONEncoder().encode(value)
            return data.flatMap { String(data: $0, encoding: .utf8) } ?? ""
        }
    }

    private func escape(_ string: String) -> String {
        var allowed = CharacterSet.alphanumerics
        allowed.insert(charactersIn: "-._~")
        return string.addingPercentEncoding(withAllowedCharacters: allowed) ?? string
    }
}
