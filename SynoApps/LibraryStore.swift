import Foundation
import Observation

@MainActor
@Observable
final class LibraryStore {
    private(set) var session: SynologySession?
    var notebooks: [Notebook] = []
    var notes: [Note] = []
    var tags: [NoteTag] = []
    var selectedNoteID: String?
    var filter: LibraryFilter = .all
    var searchText = ""
    var isLoggingIn = false
    var loginStatus = ""
    var requiresOTP = false
    var isSyncing = false
    var loadingNoteIDs: Set<String> = []
    var syncState: SyncState = .idle
    var errorMessage: String?
    var showError = false

    private let api = SynologyAPI()
    private let sessions = SessionStore()
    private let cache = LibraryCache()
    private var editRevisions: [String: Int] = [:]
    private var parentIDBeforeEdit: [String: String] = [:]
    private var metadataEdited: Set<String> = []
    private var syncGeneration = 0

    var isAuthenticated: Bool { session != nil }
    var isDemo: Bool { session?.isDemo == true }

    init() {
        session = sessions.restore()
        if let session, let cached = cache.load(isDemo: session.isDemo) {
            notebooks = cached.notebooks
            notes = cached.notes
            tags = cached.tags
        }
    }

    func login(server: String, useHTTPS: Bool, quickConnect: Bool, account: String, password: String, otp: String, rememberDevice: Bool) async {
        guard !account.trimmingCharacters(in: .whitespaces).isEmpty, !password.isEmpty else {
            presentError("请输入账户和密码。")
            return
        }
        isLoggingIn = true
        loginStatus = quickConnect ? "正在解析 QuickConnect…" : "正在连接服务器…"
        defer {
            isLoggingIn = false
            loginStatus = ""
        }
        do {
            let deviceID = UserDefaults.standard.string(forKey: "device-id") ?? UUID().uuidString
            UserDefaults.standard.set(deviceID, forKey: "device-id")
            let newSession = try await api.login(server: server, useHTTPS: useHTTPS, quickConnect: quickConnect, account: account, password: password, otp: requiresOTP ? otp : nil, deviceID: deviceID, rememberDevice: rememberDevice)
            session = newSession
            requiresOTP = false
            notes = []
            notebooks = []
            tags = []
            selectedNoteID = nil
            filter = .all
            // A keychain failure affects session restoration, not the already
            // authenticated connection or the user's ability to read notes.
            try? sessions.save(newSession)
            await sync()
        } catch SynologyError.api("SYNO.API.Auth", 403) {
            requiresOTP = true
        } catch {
            presentError(error.localizedDescription)
        }
    }

    func usePreview() {
        let preview = Self.previewPayload()
        session = SynologySession(baseURL: "preview.local", sid: "preview", account: "预览账户", isDemo: true)
        apply(preview)
        selectedNoteID = preview.notes.first?.id
        syncState = .saved(.now)
    }

    func signOut() async {
        guard let session else { return }
        if !session.isDemo { await api.logout(session: session) }
        sessions.clear()
        if !session.isDemo { cache.clear(isDemo: false) }
        self.session = nil
        notes = []
        notebooks = []
        tags = []
        selectedNoteID = nil
        requiresOTP = false
        syncState = .idle
    }

    func sync() async {
        guard let session else { return }
        guard !session.isDemo else {
            syncState = .saved(.now)
            return
        }
        syncGeneration += 1
        let generation = syncGeneration
        isSyncing = true
        syncState = .syncing
        defer { isSyncing = false }
        do {
            let payload = try await api.fetchLibrary(session: session)
            guard generation == syncGeneration else { return }
            // Keep a locally edited version while its save request is in flight.
            var merged = payload.notes
            for (index, remote) in merged.enumerated() {
                if let local = notes.first(where: { $0.id == remote.id }), syncState == .syncing, editRevisions[remote.id] != nil {
                    merged[index] = local
                }
            }
            apply(LibraryPayload(notebooks: payload.notebooks, notes: merged, tags: payload.tags))
            syncState = .saved(.now)
        } catch SynologyError.api(_, 105), SynologyError.api(_, 119) {
            sessions.clear()
            self.session = nil
            presentError("登录已过期，请重新登录。")
        } catch {
            syncState = .failed(error.localizedDescription)
            if notes.isEmpty { presentError(error.localizedDescription) }
        }
    }

    func selectNote(_ id: String?) {
        selectedNoteID = id
        guard let id, let note = notes.first(where: { $0.id == id }), !note.hasLoadedContent, !isDemo else { return }
        Task { await loadNote(id: id) }
    }

    func loadNote(id: String) async {
        guard let session, !session.isDemo, !loadingNoteIDs.contains(id) else { return }
        loadingNoteIDs.insert(id)
        defer { loadingNoteIDs.remove(id) }
        do {
            let loaded = try await api.getNote(id: id, session: session)
            replace(loaded)
            persistCache()
        } catch {
            if error is CancellationError || (error as? URLError)?.code == .cancelled { return }
            presentError(error.localizedDescription)
        }
    }

    func updateNote(id: String, title: String? = nil, content: String? = nil) {
        guard let index = notes.firstIndex(where: { $0.id == id }) else { return }
        if let title { notes[index].title = title }
        if let content { notes[index].content = content }
        notes[index].modifiedAt = .now
        notes[index].hasLoadedContent = true
        editRevisions[id, default: 0] += 1
        syncState = .syncing
    }

    func updateMetadata(id: String, parentID: String, tags: [String]) {
        guard let index = notes.firstIndex(where: { $0.id == id }) else { return }
        if parentIDBeforeEdit[id] == nil { parentIDBeforeEdit[id] = notes[index].parentID }
        notes[index].parentID = parentID
        notes[index].tags = tags
        notes[index].modifiedAt = .now
        metadataEdited.insert(id)
        editRevisions[id, default: 0] += 1
        syncState = .syncing
    }

    func saveNote(id: String) async {
        guard editRevisions[id] != nil else { return } // Viewing without edits is read-only.
        guard let session, let note = notes.first(where: { $0.id == id }), !note.isEncrypted else { return }
        let revision = editRevisions[id, default: 0]
        syncState = .syncing
        do {
            if session.isDemo {
                try await Task.sleep(for: .milliseconds(250))
                replace(note)
            } else {
                let saved = try await api.saveNote(note, session: session, previousParentID: parentIDBeforeEdit[id], includeTags: metadataEdited.contains(id))
                if editRevisions[id, default: 0] == revision {
                    replace(saved)
                } else if let index = notes.firstIndex(where: { $0.id == id }) {
                    notes[index].version = saved.version
                }
            }
            if editRevisions[id, default: 0] == revision {
                editRevisions.removeValue(forKey: id)
                parentIDBeforeEdit.removeValue(forKey: id)
                metadataEdited.remove(id)
            }
            syncState = .saved(.now)
            persistCache()
        } catch {
            syncState = .failed(error.localizedDescription)
            presentError(error.localizedDescription)
        }
    }

    func createNote() async {
        guard let session else { return }
        let notebookID: String?
        if case .notebook(let id) = filter { notebookID = id } else { notebookID = notebooks.first?.id }
        guard let notebookID else { presentError(SynologyError.noNotebook.localizedDescription); return }
        syncState = .syncing
        do {
            let note: Note
            if session.isDemo {
                note = Note(title: "无标题", content: "<p><br></p>", parentID: notebookID)
                try await Task.sleep(for: .milliseconds(200))
            } else {
                note = try await api.createNote(title: "无标题", notebookID: notebookID, session: session)
            }
            notes.insert(note, at: 0)
            selectedNoteID = note.id
            syncState = .saved(.now)
            persistCache()
        } catch {
            syncState = .failed(error.localizedDescription)
            presentError(error.localizedDescription)
        }
    }

    func moveToTrash(id: String) async {
        guard let session, let note = notes.first(where: { $0.id == id }) else { return }
        syncState = .syncing
        do {
            if !session.isDemo { try await api.deleteNote(note, session: session) }
            if note.isInTrash {
                notes.removeAll { $0.id == id }
            } else if let index = notes.firstIndex(where: { $0.id == id }) {
                notes[index].isInTrash = true
                notes[index].modifiedAt = .now
            }
            if selectedNoteID == id { selectedNoteID = nil }
            syncState = .saved(.now)
            persistCache()
        } catch {
            syncState = .failed(error.localizedDescription)
            presentError(error.localizedDescription)
        }
    }

    func restoreFromTrash(id: String) async {
        guard let session, let note = notes.first(where: { $0.id == id }) else { return }
        syncState = .syncing
        do {
            let restored: Note
            if session.isDemo {
                restored = note
            } else {
                restored = try await api.restoreNote(id: id, session: session)
            }
            if let index = notes.firstIndex(where: { $0.id == id }) {
                notes[index].isInTrash = false
                notes[index].version = restored.version
            }
            syncState = .saved(.now)
            persistCache()
        } catch {
            syncState = .failed(error.localizedDescription)
            presentError(error.localizedDescription)
        }
    }

    func filteredNotes() -> [Note] {
        notes.filter { note in
            let matchesFilter: Bool
            switch filter {
            case .all: matchesFilter = !note.isInTrash && !note.isArchived
            case .notebook(let id): matchesFilter = note.parentID == id && !note.isInTrash
            case .tag(let tag): matchesFilter = note.tags.contains(tag) && !note.isInTrash
            case .trash: matchesFilter = note.isInTrash
            }
            guard matchesFilter else { return false }
            let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
            return query.isEmpty || note.title.localizedCaseInsensitiveContains(query) || note.preview.localizedCaseInsensitiveContains(query) || note.tags.contains { $0.localizedCaseInsensitiveContains(query) }
        }.sorted { $0.modifiedAt > $1.modifiedAt }
    }

    func note(id: String?) -> Note? {
        guard let id else { return nil }
        return notes.first { $0.id == id }
    }

    func filterTitle() -> String {
        switch filter {
        case .all: return "笔记"
        case .trash: return "废纸篓"
        case .notebook(let id): return notebooks.first { $0.id == id }?.title ?? "笔记本"
        case .tag(let title): return "# " + title
        }
    }

    private func apply(_ payload: LibraryPayload) {
        notebooks = payload.notebooks.sorted { $0.title.localizedStandardCompare($1.title) == .orderedAscending }
        notes = payload.notes
        tags = payload.tags.sorted { $0.title.localizedStandardCompare($1.title) == .orderedAscending }
        persistCache()
    }

    private func replace(_ note: Note) {
        if let index = notes.firstIndex(where: { $0.id == note.id }) { notes[index] = note }
        else { notes.append(note) }
    }

    private func persistCache() {
        guard let session else { return }
        cache.save(LibraryPayload(notebooks: notebooks, notes: notes, tags: tags), isDemo: session.isDemo)
    }

    private func presentError(_ message: String) {
        errorMessage = message
        showError = true
    }

    private static func previewPayload() -> LibraryPayload {
        let personal = Notebook(id: "personal", title: "个人笔记", itemCount: 2)
        let work = Notebook(id: "work", title: "工作", itemCount: 1)
        let notes = [
            Note(id: "welcome", title: "欢迎使用 SynoApps", content: "<h2>你的笔记，随时在手边。</h2><p>这是一个可交互的预览笔记。连接群晖后，这里会显示 Note Station 中的真实内容。</p><h3>像书写一样简单</h3><ul><li>深色侧栏与清晰的笔记列表</li><li>标题、正文与富文本格式</li><li>离线缓存和自动保存</li></ul><blockquote>试着选择这段文字，或使用下方工具栏编辑。</blockquote>", parentID: personal.id, tags: ["指南"], modifiedAt: .now),
            Note(id: "reading", title: "阅读清单", content: "<h3>本月想读</h3><ul><li>《设计中的设计》</li><li>《献给阿尔吉侬的花束》</li><li>《纳瓦尔宝典》</li></ul><p>在通勤时记录触动自己的句子。</p>", parentID: personal.id, tags: ["阅读"], modifiedAt: .now.addingTimeInterval(-3600 * 22)),
            Note(id: "meeting", title: "产品讨论会", content: "<p><strong>目标：</strong>让记录与查找都更自然。</p><ol><li>确认首版范围</li><li>整理同步边界情况</li><li>完成真机体验验证</li></ol>", parentID: work.id, tags: ["工作"], modifiedAt: .now.addingTimeInterval(-3600 * 50))
        ]
        return LibraryPayload(notebooks: [personal, work], notes: notes, tags: [NoteTag(id: "guide", title: "指南"), NoteTag(id: "reading", title: "阅读"), NoteTag(id: "work", title: "工作")])
    }
}
