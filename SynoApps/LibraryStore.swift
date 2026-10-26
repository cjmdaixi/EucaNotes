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
    var diaryImages: [String: Data] = [:]
    var loadingDiaryImageIDs: Set<String> = []
    var isPreparingDiary = false

    private let api = SynologyAPI()
    private let sessions = SessionStore()
    private let cache = LibraryCache()
    private var editRevisions: [String: Int] = [:]
    private var parentIDBeforeEdit: [String: String] = [:]
    private var metadataEdited: Set<String> = []
    private var syncGeneration = 0
    private var diaryPreparationTask: Task<Void, Error>?

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
            try await ensureDiaryLibrary(session: session)
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

    private func ensureDiaryLibrary(session: SynologySession) async throws {
        if let diaryPreparationTask { return try await diaryPreparationTask.value }
        let task = Task { try await prepareDiaryLibrary(session: session) }
        diaryPreparationTask = task
        defer { diaryPreparationTask = nil }
        try await task.value
    }

    private func prepareDiaryLibrary(session: SynologySession) async throws {
        isPreparingDiary = true
        defer { isPreparingDiary = false }
        if !diaryMonths.contains(where: { $0.title == DiaryText.notebookTitle() }) {
            let month = try await api.createNotebook(title: DiaryText.notebookTitle(), stack: Self.diaryShelfName, session: session)
            notebooks.append(month)
        }
        for month in diaryMonths where infoNote(monthID: month.id) == nil {
            var info = try await api.createNote(title: "信息", notebookID: month.id, session: session)
            info.content = "<p>背景照片：</p>"
            if !session.isDemo { info = try await api.saveNote(info, session: session) }
            notes.append(info)
        }
        persistCache()
    }

    func loadDiaryImage(noteID: String, backgroundOnly: Bool = false) async {
        guard diaryImages[noteID] == nil, !loadingDiaryImageIDs.contains(noteID), !isDemo else { return }
        loadingDiaryImageIDs.insert(noteID)
        defer { loadingDiaryImageIDs.remove(noteID) }
        if note(id: noteID)?.hasLoadedContent == false { await loadNote(id: noteID) }
        guard let session, let note = note(id: noteID),
              let source = DiaryText.imageSource(in: note.content, after: backgroundOnly ? "背景照片：" : nil),
              !source.isEmpty else { return }
        do {
            diaryImages[noteID] = try await api.imageData(source: source, session: session)
        } catch {
            if !Task.isCancelled { diaryImages.removeValue(forKey: noteID) }
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

    func createDiary(monthID: String) async -> String? {
        guard let session, diaryMonths.contains(where: { $0.id == monthID }) else { return nil }
        let title: String
        if let month = diaryMonth(id: monthID) {
            let now = Date.now
            let currentYear = DiaryText.calendar.component(.year, from: now)
            let currentMonth = DiaryText.calendar.component(.month, from: now)
            let currentDay = DiaryText.calendar.component(.day, from: now)
            let firstDay = DiaryText.calendar.date(from: DateComponents(year: month.year, month: month.month)) ?? now
            let dayRange = DiaryText.calendar.range(of: .day, in: .month, for: firstDay)?.count ?? 31
            let day = (month.year == currentYear && month.month == currentMonth) ? currentDay : min(currentDay, dayRange)
            title = "\(month.month)月\(day)日"
        } else {
            title = DiaryText.noteTitle()
        }
        if let existing = diaryNotes(monthID: monthID).first(where: { $0.title == title }) {
            selectedNoteID = existing.id
            return existing.id
        }
        syncState = .syncing
        do {
            let note: Note
            if session.isDemo {
                note = Note(title: title, content: "<p><br></p>", parentID: monthID)
                try await Task.sleep(for: .milliseconds(200))
            } else {
                note = try await api.createNote(title: title, notebookID: monthID, session: session)
            }
            notes.insert(note, at: 0)
            selectedNoteID = note.id
            syncState = .saved(.now)
            persistCache()
            return note.id
        } catch {
            syncState = .failed(error.localizedDescription)
            presentError(error.localizedDescription)
            return nil
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
        }.sorted {
            if $0.isPinned != $1.isPinned { return $0.isPinned && !$1.isPinned }
            return $0.modifiedAt > $1.modifiedAt
        }
    }

    func togglePin(id: String) {
        guard let index = notes.firstIndex(where: { $0.id == id }) else { return }
        notes[index].isPinned.toggle()
        persistCache()
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
        let current = Notebook(id: "current-month", title: DiaryText.notebookTitle(), stack: diaryShelfName)
        let previous = Notebook(id: "previous-month", title: "2026年9月", stack: diaryShelfName)
        let notes = [
            Note(id: "current-info", title: "信息", content: "<p>背景照片：</p>", parentID: current.id),
            Note(id: "previous-info", title: "信息", content: "<p>背景照片：</p>", parentID: previous.id),
            Note(id: "today", title: DiaryText.noteTitle(), content: "<h2>把今天留在桉记</h2><p>傍晚的风穿过树叶，光落在窗台上。那些平常的小事，也值得认真记下来。</p>", parentID: current.id),
            Note(id: "earlier", title: "10月3日", content: "<p>沿着老街慢慢走，发现了一家安静的小店。读了几页书，喝完一杯热茶。</p>", parentID: current.id, modifiedAt: .now.addingTimeInterval(-3600 * 48)),
            Note(id: "autumn", title: "9月28日", content: "<p>九月末，天气终于有了一点秋天的意思。</p>", parentID: previous.id)
        ]
        return LibraryPayload(notebooks: [current, previous], notes: notes, tags: [])
    }
}
