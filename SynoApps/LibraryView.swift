import SwiftUI

struct LibraryView: View {
    @Environment(LibraryStore.self) private var store
    @State private var columnVisibility: NavigationSplitViewVisibility = .all
    @State private var showSidebar = false

    var body: some View {
        @Bindable var store = store
        NavigationSplitView(columnVisibility: $columnVisibility) {
            SidebarView()
                .navigationSplitViewColumnWidth(min: 230, ideal: 270, max: 310)
        } content: {
            NoteListView(showSidebar: $showSidebar)
                .navigationSplitViewColumnWidth(min: 290, ideal: 350, max: 440)
        } detail: {
            if let note = store.note(id: store.selectedNoteID) {
                NoteEditorView(noteID: note.id)
                    .id(note.id)
            } else {
                VStack(spacing: 18) {
                    Image(systemName: "note.text")
                        .font(.system(size: 54, weight: .thin))
                        .foregroundStyle(.quaternary)
                    Text("选择一篇笔记")
                        .font(.title3.weight(.medium))
                        .foregroundStyle(.secondary)
                    Text("或新建一篇，让想法落在这里")
                        .font(.subheadline)
                        .foregroundStyle(.tertiary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(AppTheme.paper)
            }
        }
        .navigationSplitViewStyle(.balanced)
        .tint(AppTheme.accent)
        .overlay {
            if showSidebar {
                GeometryReader { proxy in
                    ZStack(alignment: .leading) {
                        Color.black.opacity(0.18)
                            .ignoresSafeArea()
                            .onTapGesture { showSidebar = false }
                        SidebarView(onSelect: { showSidebar = false })
                            .frame(width: min(320, proxy.size.width * 0.82))
                            .background(AppTheme.sidebar)
                            .transition(.move(edge: .leading))
                    }
                }
                .zIndex(20)
            }
        }
        .animation(.easeInOut(duration: 0.22), value: showSidebar)
        .task(id: store.session?.sid) {
            if !store.isDemo { await store.sync() }
        }
        .alert("操作未完成", isPresented: $store.showError) {
            Button("好", role: .cancel) {}
        } message: {
            Text(store.errorMessage ?? "请稍后重试。")
        }
    }
}

private struct SidebarView: View {
    @Environment(LibraryStore.self) private var store
    var onSelect: (() -> Void)? = nil

    var body: some View {
        @Bindable var store = store
        List(selection: Binding<LibraryFilter?>(get: { store.filter }, set: { value in
            if let value {
                store.filter = value
                onSelect?()
            }
        })) {
            Section {
                SidebarRow(title: "笔记", icon: "note.text", selected: store.filter == .all)
                    .tag(LibraryFilter.all)
                SidebarRow(title: "废纸篓", icon: "trash", selected: store.filter == .trash)
                    .tag(LibraryFilter.trash)
            }

            Section("笔记本") {
                ForEach(store.notebooks) { notebook in
                    SidebarRow(
                        title: notebook.title,
                        icon: "book.closed",
                        count: store.notes.filter { $0.parentID == notebook.id && !$0.isInTrash }.count,
                        selected: store.filter == .notebook(notebook.id),
                        showsChevron: true
                    )
                    .tag(LibraryFilter.notebook(notebook.id))
                }
            }

            if !store.tags.isEmpty {
                Section("标签") {
                    ForEach(store.tags) { tag in
                        SidebarRow(title: tag.title, icon: "number", selected: store.filter == .tag(tag.title))
                            .tag(LibraryFilter.tag(tag.title))
                    }
                }
            }
        }
        .listStyle(.sidebar)
        .scrollContentBackground(.hidden)
        .background(AppTheme.sidebar)
        .foregroundStyle(.primary)
        .toolbar(.hidden, for: .navigationBar)
        .safeAreaInset(edge: .top) {
            HStack {
                Spacer()
                Menu {
                    Button { Task { await store.sync() } } label: {
                        Label("立即同步", systemImage: "arrow.triangle.2.circlepath")
                    }
                    .disabled(store.isSyncing)
                    Divider()
                    Button(role: .destructive) {
                        Task { await store.signOut() }
                    } label: {
                        Label(store.isDemo ? "退出预览" : "退出登录", systemImage: "rectangle.portrait.and.arrow.right")
                    }
                } label: {
                    Image(systemName: "ellipsis")
                        .font(.title2.weight(.medium))
                        .frame(width: 48, height: 44)
                        .contentShape(Rectangle())
                }
                .accessibilityLabel("账户与同步")
            }
            .padding(.horizontal, 12)
            .padding(.top, 4)
            .background(AppTheme.sidebar)
        }
        .safeAreaInset(edge: .bottom) {
            HStack(spacing: 8) {
                Circle()
                    .fill(store.isDemo ? AppTheme.accent : .green)
                    .frame(width: 7, height: 7)
                Text(store.isDemo ? "界面预览" : store.session?.account ?? "已连接")
                    .lineLimit(1)
                Spacer()
                Image(systemName: "checkmark.icloud")
            }
            .font(.caption)
            .foregroundStyle(.secondary)
            .padding(.horizontal, 20)
            .padding(.vertical, 12)
            .background(AppTheme.sidebar)
        }
    }
}

private struct SidebarRow: View {
    let title: String
    let icon: String
    var count: Int? = nil
    var selected: Bool
    var showsChevron = false

    var body: some View {
        HStack(spacing: 13) {
            Image(systemName: icon)
                .font(.body.weight(.medium))
                .foregroundStyle(AppTheme.accent)
                .frame(width: 20)
            Text(title)
                .font(.body)
                .lineLimit(1)
            Spacer()
            if let count {
                Text("\(count)")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
            if showsChevron {
                Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(AppTheme.accent)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 9)
        .background(selected ? AppTheme.sidebarSecondary : .clear, in: RoundedRectangle(cornerRadius: 9, style: .continuous))
        .contentShape(Rectangle())
        .listRowBackground(Color.clear)
        .listRowInsets(EdgeInsets(top: 2, leading: 10, bottom: 2, trailing: 8))
        .listRowSeparator(.hidden)
    }
}

private struct NoteListView: View {
    @Environment(LibraryStore.self) private var store
    @Binding var showSidebar: Bool
    @State private var isSearchPresented = false
    @State private var notePendingDeletion: Note?
    @FocusState private var searchFocused: Bool

    var body: some View {
        @Bindable var store = store
        List(selection: Binding<String?>(get: { store.selectedNoteID }, set: { store.selectNote($0) })) {
            ForEach(store.filteredNotes()) { note in
                NoteRow(note: note)
                    .tag(note.id)
                    .listRowSeparator(.visible)
                    .listRowInsets(EdgeInsets(top: 10, leading: 20, bottom: 10, trailing: 18))
                    .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                        Button(role: .destructive) { notePendingDeletion = note } label: {
                            Image(systemName: "trash")
                        }
                        .tint(AppTheme.accent)
                        Button { store.togglePin(id: note.id) } label: {
                            Image(systemName: note.isPinned ? "pin.slash" : "pin")
                        }
                        .tint(AppTheme.accent.opacity(0.45))
                    }
            }
        }
        .listStyle(.plain)
        .background(AppTheme.paper)
        .navigationBarBackButtonHidden(true)
        .toolbar {
            ToolbarItem(placement: .navigationBarLeading) {
                Button { showSidebar = true } label: {
                    Image(systemName: "line.3.horizontal")
                        .font(.title3.weight(.medium))
                        .foregroundStyle(.primary)
                        .frame(width: 42, height: 42)
                        .background(.regularMaterial, in: Circle())
                }
                .accessibilityLabel("打开侧栏")
            }
            ToolbarItem(placement: .principal) {
                Menu {
                    Button("全部笔记") { store.filter = .all }
                    Button("废纸篓") { store.filter = .trash }
                    Divider()
                    ForEach(store.notebooks) { notebook in
                        Button(notebook.title) { store.filter = .notebook(notebook.id) }
                    }
                } label: {
                    HStack(spacing: 4) {
                        Text(store.filterTitle())
                            .font(.headline)
                            .foregroundStyle(.primary)
                        Image(systemName: "chevron.down")
                            .font(.caption.weight(.semibold))
                    }
                }
                .accessibilityLabel("选择笔记本")
            }
            ToolbarItem(placement: .primaryAction) {
                Button {
                    isSearchPresented = true
                    searchFocused = true
                } label: {
                    Image(systemName: "magnifyingglass")
                        .font(.title3.weight(.medium))
                        .foregroundStyle(.primary)
                        .frame(width: 42, height: 42)
                        .background(.regularMaterial, in: Circle())
                }
                .accessibilityLabel("搜索笔记")
            }
        }
        .safeAreaInset(edge: .top) {
            if isSearchPresented {
                HStack(spacing: 10) {
                    Image(systemName: "magnifyingglass")
                        .foregroundStyle(.secondary)
                    TextField("搜索笔记", text: $store.searchText)
                        .focused($searchFocused)
                        .submitLabel(.search)
                        .accessibilityIdentifier("note-search-field")
                    Button("取消") {
                        isSearchPresented = false
                        store.searchText = ""
                    }
                    .foregroundStyle(.primary)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 9)
                .background(.regularMaterial)
            }
        }
        .overlay {
            if store.filteredNotes().isEmpty && !store.isSyncing {
                EmptyNotesView(isTrash: store.filter == .trash)
                    .background(AppTheme.paper)
            }
        }
        .overlay(alignment: .bottomTrailing) {
            if store.filter != .trash {
                Button { Task { await store.createNote() } } label: {
                    Image(systemName: "square.and.pencil")
                        .font(.system(size: 23, weight: .medium))
                        .foregroundStyle(.white)
                        .frame(width: 58, height: 58)
                        .background(AppTheme.accent, in: Circle())
                        .shadow(color: AppTheme.accent.opacity(0.32), radius: 12, y: 5)
                }
                .disabled(store.notebooks.isEmpty)
                .accessibilityLabel("新建笔记")
                .accessibilityIdentifier("new-note-button")
                .padding(.trailing, 20)
                .padding(.bottom, 20)
            }
        }
        .confirmationDialog("将这篇笔记移到废纸篓？", isPresented: Binding(get: { notePendingDeletion != nil }, set: { if !$0 { notePendingDeletion = nil } }), titleVisibility: .visible) {
            Button("移到废纸篓", role: .destructive) {
                if let note = notePendingDeletion {
                    Task { await store.moveToTrash(id: note.id) }
                }
                notePendingDeletion = nil
            }
            Button("取消", role: .cancel) { notePendingDeletion = nil }
        }
    }
}
