import SwiftUI

enum DiaryHomeSection { case cards, profile }

struct HomeBottomBar: View {
    @Binding var section: DiaryHomeSection
    @Binding var showCalendar: Bool
    let isCreating: Bool
    let createAction: () -> Void

    var body: some View {
        VStack(spacing: 8) {
            if section == .cards {
                Button { showCalendar.toggle() } label: {
                    Image(systemName: "calendar")
                        .font(.title3)
                        .frame(width: 48, height: 48)
                        .background(showCalendar ? AppTheme.accent : Color(uiColor: .secondarySystemBackground), in: Circle())
                        .foregroundStyle(showCalendar ? .white : .primary)
                }
                .accessibilityLabel(showCalendar ? "切换到照片月卡" : "切换到月历")
                .accessibilityIdentifier("calendar-mode-button")
            }
            HStack {
                Button { section = .cards } label: {
                    VStack(spacing: 3) {
                        Image(systemName: "book.closed.fill")
                        Text("月卡").font(.caption2)
                    }
                    .foregroundStyle(section == .cards ? AppTheme.accent : .secondary)
                    .frame(maxWidth: .infinity)
                }
                .accessibilityLabel("月份卡片")
                .accessibilityIdentifier("home-cards-tab")
                Button(action: createAction) {
                    ZStack {
                        Circle().fill(AppTheme.accent).frame(width: 60, height: 60)
                            .shadow(color: AppTheme.accent.opacity(0.25), radius: 12, y: 5)
                        if isCreating { ProgressView().tint(.white) }
                        else { Image(systemName: "plus").font(.system(size: 25, weight: .medium)).foregroundStyle(.white) }
                    }
                }
                .disabled(isCreating)
                .accessibilityLabel("写日记")
                .accessibilityIdentifier("new-diary-button")
                Button { section = .profile } label: {
                    VStack(spacing: 3) {
                        Image(systemName: "person.fill")
                        Text("我的").font(.caption2)
                    }
                    .foregroundStyle(section == .profile ? AppTheme.accent : .secondary)
                    .frame(maxWidth: .infinity)
                }
                .accessibilityLabel("我的")
                .accessibilityIdentifier("home-profile-tab")
            }
            .padding(.horizontal, 28)
            .padding(.top, 4)
            .padding(.bottom, 6)
        }
        .background(.regularMaterial)
    }
}

struct MonthCalendarCard: View {
    @Environment(LibraryStore.self) private var store
    let month: DiaryMonth
    @Binding var path: [DiaryRoute]
    @State private var creatingDay: Int?

    private let weekdays = ["一", "二", "三", "四", "五", "六", "日"]
    private var daysInMonth: Int {
        let first = DiaryText.calendar.date(from: DateComponents(year: month.year, month: month.month)) ?? .now
        return DiaryText.calendar.range(of: .day, in: .month, for: first)?.count ?? 30
    }
    private var leadingDays: Int {
        let first = DiaryText.calendar.date(from: DateComponents(year: month.year, month: month.month)) ?? .now
        return (DiaryText.calendar.component(.weekday, from: first) + 5) % 7
    }

    var body: some View {
        VStack(spacing: 12) {
            Text(month.monthTitle)
                .font(.system(size: 36, weight: .bold, design: .serif))
                .frame(maxWidth: .infinity, alignment: .leading)
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 2), count: 7), spacing: 8) {
                ForEach(weekdays, id: \.self) { day in
                    Text(day).font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                        .frame(height: 28)
                }
                ForEach(0..<42, id: \.self) { index in
                    let day = index - leadingDays + 1
                    if day > 0 && day <= daysInMonth {
                        dayButton(day)
                    } else {
                        Color.clear.frame(height: 42)
                    }
                }
            }
            Spacer(minLength: 0)
            Text("\(store.diaryNotes(monthID: month.id).count) 篇日记")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(20)
        .background(Color(uiColor: .secondarySystemBackground), in: RoundedRectangle(cornerRadius: 30, style: .continuous))
        .shadow(color: .black.opacity(0.08), radius: 20, y: 9)
    }

    private func dayButton(_ day: Int) -> some View {
        let hasDiary = store.diaryNotes(monthID: month.id).contains { DiaryText.day(from: $0.title) == day }
        return Button {
            creatingDay = day
            Task {
                if let id = await store.createDiary(monthID: month.id, day: day) {
                    path.append(.month(month.id))
                    path.append(.note(id))
                }
                creatingDay = nil
            }
        } label: {
            ZStack {
                Circle()
                    .fill(hasDiary ? AppTheme.accent : Color(uiColor: .tertiarySystemFill))
                    .frame(width: 34, height: 34)
                if creatingDay == day { ProgressView().scaleEffect(0.55) }
                else {
                    Text("\(day)")
                        .font(.subheadline.weight(hasDiary ? .bold : .regular))
                        .foregroundStyle(hasDiary ? .white : .primary)
                }
            }
            .frame(height: 42)
        }
        .buttonStyle(.plain)
        .disabled(creatingDay != nil)
        .accessibilityLabel("\(month.month)月\(day)日，\(hasDiary ? "查看日记" : "新建日记")")
        .accessibilityIdentifier("calendar-day-\(month.year)-\(month.month)-\(day)")
    }
}

struct DiaryProfileView: View {
    @Environment(LibraryStore.self) private var store
    @Binding var path: [DiaryRoute]

    private var account: String { store.session?.account ?? "预览账户" }
    private var server: String {
        guard let host = URLComponents(string: store.session?.baseURL ?? "")?.host else { return "界面预览" }
        return host
    }
    private var days: Int { Set(store.allDiaryNotes.map { $0.parentID + $0.title }).count }
    private var favorites: Int { store.allDiaryNotes.filter { $0.isPinned || $0.diaryMetadata.favorite }.count }
    private var tags: Int { Set(store.allDiaryNotes.flatMap(\.tags)).count }
    private var thisYear: Int {
        let year = DiaryText.calendar.component(.year, from: .now)
        let ids = Set(store.diaryMonths.filter { $0.year == year }.map(\.id))
        return store.allDiaryNotes.filter { ids.contains($0.parentID) }.count
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                HStack {
                    Text("我的").font(.system(size: 30, weight: .bold, design: .serif))
                    Spacer()
                    SearchButton(path: $path)
                }
                VStack(spacing: 14) {
                    Circle()
                        .fill(AppTheme.accent.opacity(0.16))
                        .frame(width: 86, height: 86)
                        .overlay(Text(account.prefix(1)).font(.system(size: 36, weight: .bold)).foregroundStyle(AppTheme.accent))
                    Text(account).font(.title2.bold())
                    Label(server, systemImage: "checkmark.icloud")
                        .font(.caption).foregroundStyle(.secondary)
                    Menu {
                        Button { Task { await store.sync() } } label: { Label("立即同步", systemImage: "arrow.triangle.2.circlepath") }
                        Button(role: .destructive) { Task { await store.signOut() } } label: { Label(store.isDemo ? "退出预览" : "退出登录", systemImage: "rectangle.portrait.and.arrow.right") }
                    } label: {
                        Label("账户与同步", systemImage: "ellipsis")
                            .font(.subheadline)
                            .padding(.horizontal, 16).padding(.vertical, 8)
                            .background(Color(uiColor: .secondarySystemBackground), in: Capsule())
                    }
                    .accessibilityLabel("账户与同步")
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)

                HStack(spacing: 12) {
                    StatView(value: store.allDiaryNotes.count, label: "全部日记")
                    StatView(value: days, label: "记录天数")
                    StatView(value: favorites, label: "最喜欢")
                }
                VStack(spacing: 0) {
                    LabeledContent("今年的日记", value: "\(thisYear) 篇")
                    Divider().padding(.vertical, 16)
                    LabeledContent("月份记事本", value: "\(store.diaryMonths.count) 个")
                    Divider().padding(.vertical, 16)
                    LabeledContent("使用中的标签", value: "\(tags) 个")
                    Divider().padding(.vertical, 16)
                    LabeledContent("书架", value: LibraryStore.diaryShelfName)
                }
                .padding(20)
                .background(Color(uiColor: .secondarySystemBackground), in: RoundedRectangle(cornerRadius: 20))
            }
            .padding(.horizontal, 24)
            .padding(.top, 8)
            .padding(.bottom, 24)
        }
        .background(AppTheme.paper)
        .navigationBarHidden(true)
        .accessibilityIdentifier("profile-screen")
    }
}

private struct StatView: View {
    let value: Int
    let label: String
    var body: some View {
        VStack(spacing: 7) {
            Text("\(value)").font(.system(size: 30, weight: .bold, design: .rounded))
            Text(label).font(.caption).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 22)
        .background(Color(uiColor: .secondarySystemBackground), in: RoundedRectangle(cornerRadius: 18))
    }
}

struct SearchButton: View {
    @Binding var path: [DiaryRoute]
    var body: some View {
        Button { path.append(.search) } label: {
            Image(systemName: "magnifyingglass")
                .font(.title3.weight(.medium))
                .frame(width: 44, height: 44)
                .background(.regularMaterial, in: Circle())
        }
        .accessibilityLabel("搜索日记")
        .accessibilityIdentifier("diary-search-button")
    }
}

struct DiarySearchView: View {
    @Environment(LibraryStore.self) private var store
    @Binding var path: [DiaryRoute]
    @State private var query = ""
    @FocusState private var focused: Bool

    private var results: [Note] {
        let text = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return [] }
        return store.allDiaryNotes.filter { note in
            note.title.localizedCaseInsensitiveContains(text) ||
            note.diaryMetadata.headline.localizedCaseInsensitiveContains(text) ||
            note.preview.localizedCaseInsensitiveContains(text) ||
            note.diaryMetadata.location.localizedCaseInsensitiveContains(text) ||
            note.tags.contains { $0.localizedCaseInsensitiveContains(text) }
        }.sorted { $0.modifiedAt > $1.modifiedAt }
    }

    var body: some View {
        ScrollView {
            LazyVStack(spacing: 14) {
                ForEach(results) { note in
                    Button { path.append(.note(note.id)) } label: {
                        SearchResultRow(note: note)
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("search-result-\(note.id)")
                }
            }
            .padding(20)
        }
        .background(AppTheme.paper)
        .overlay {
            if results.isEmpty {
                ContentUnavailableView(
                    query.isEmpty ? "搜索所有日记" : "没有找到相关日记",
                    systemImage: "magnifyingglass",
                    description: Text(query.isEmpty ? "搜索标题、正文、标签或位置。" : "换个关键词试试。")
                )
            }
        }
        .navigationTitle("搜索")
        .navigationBarTitleDisplayMode(.inline)
        .safeAreaInset(edge: .top) {
            HStack {
                Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                TextField("标题、正文、标签或位置", text: $query)
                    .focused($focused)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .accessibilityIdentifier("diary-search-field")
            }
            .padding(12)
            .background(Color(uiColor: .secondarySystemBackground), in: RoundedRectangle(cornerRadius: 12))
            .padding(.horizontal, 20)
            .padding(.vertical, 8)
            .background(.regularMaterial)
        }
        .onAppear { focused = true }
    }
}

private struct SearchResultRow: View {
    @Environment(LibraryStore.self) private var store
    let note: Note

    var body: some View {
        HStack(spacing: 14) {
            VStack(alignment: .leading, spacing: 7) {
                Text(note.title).font(.headline)
                if !note.diaryMetadata.headline.isEmpty {
                    Text(note.diaryMetadata.headline).font(.subheadline.weight(.semibold)).lineLimit(1)
                }
                Text(note.preview).font(.caption).foregroundStyle(.secondary).lineLimit(3)
            }
            Spacer(minLength: 0)
            if let data = store.diaryImages[note.id], let image = UIImage(data: data) {
                Image(uiImage: image).resizable().scaledToFill()
                    .frame(width: 72, height: 72)
                    .clipShape(RoundedRectangle(cornerRadius: 10))
            }
        }
        .padding(16)
        .background(Color(uiColor: .secondarySystemBackground), in: RoundedRectangle(cornerRadius: 16))
        .task(id: note.id) {
            await store.loadNote(id: note.id)
            await store.loadDiaryImage(noteID: note.id)
        }
    }
}
