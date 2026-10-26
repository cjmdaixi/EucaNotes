import SwiftUI

struct LibraryView: View {
    @Environment(LibraryStore.self) private var store
    @State private var columnVisibility: NavigationSplitViewVisibility = .all

    var body: some View {
        @Bindable var store = store
        NavigationSplitView(columnVisibility: $columnVisibility) {
            SidebarView()
                .navigationSplitViewColumnWidth(min: 210, ideal: 238, max: 280)
        } content: {
            NoteListView()
                .navigationSplitViewColumnWidth(min: 290, ideal: 340, max: 430)
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

    var body: some View {
        @Bindable var store = store
        List(selection: Binding<LibraryFilter?>(get: { store.filter }, set: { if let value = $0 { store.filter = value } })) {
            Section {
                Label("笔记", systemImage: "note.text")
                    .tag(LibraryFilter.all)
                    .listRowBackground(store.filter == .all ? AppTheme.sidebarSecondary : AppTheme.sidebar)
                Label("废纸篓", systemImage: "trash")
                    .tag(LibraryFilter.trash)
                    .listRowBackground(store.filter == .trash ? AppTheme.sidebarSecondary : AppTheme.sidebar)
            }
            .foregroundStyle(.white.opacity(0.88))

            Section("笔记本") {
                ForEach(store.notebooks) { notebook in
                    HStack {
                        Label(notebook.title, systemImage: "book.closed")
                        Spacer()
                        Text("\(store.notes.filter { $0.parentID == notebook.id && !$0.isInTrash }.count)")
                            .font(.caption)
                            .foregroundStyle(.white.opacity(0.38))
                    }
                    .tag(LibraryFilter.notebook(notebook.id))
                    .listRowBackground(store.filter == .notebook(notebook.id) ? AppTheme.sidebarSecondary : AppTheme.sidebar)
                }
            }

            if !store.tags.isEmpty {
                Section("标签") {
                    ForEach(store.tags) { tag in
                        Label(tag.title, systemImage: "number")
                            .tag(LibraryFilter.tag(tag.title))
                            .listRowBackground(store.filter == .tag(tag.title) ? AppTheme.sidebarSecondary : AppTheme.sidebar)
                    }
                }
            }
        }
        .listStyle(.sidebar)
        .scrollContentBackground(.hidden)
        .background(AppTheme.sidebar)
        .foregroundStyle(.white.opacity(0.82))
        .navigationTitle("SynoApps")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
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
                    Image(systemName: "person.crop.circle")
                }
                .accessibilityLabel("账户与同步")
            }
        }
        .toolbarBackground(AppTheme.sidebar, for: .navigationBar)
        .toolbarBackground(.visible, for: .navigationBar)
        .toolbarColorScheme(.dark, for: .navigationBar)
        .safeAreaInset(edge: .bottom) {
            HStack(spacing: 8) {
                Circle()
                    .fill(store.isDemo ? .orange : .green)
                    .frame(width: 7, height: 7)
                Text(store.isDemo ? "界面预览" : store.session?.account ?? "已连接")
                    .lineLimit(1)
                Spacer()
                Image(systemName: "checkmark.icloud")
            }
            .font(.caption)
            .foregroundStyle(.white.opacity(0.48))
            .padding(.horizontal, 18)
            .padding(.vertical, 12)
            .background(AppTheme.sidebar)
        }
    }
}

private struct NoteListView: View {
    @Environment(LibraryStore.self) private var store

    var body: some View {
        @Bindable var store = store
        List(selection: Binding<String?>(get: { store.selectedNoteID }, set: { store.selectNote($0) })) {
            ForEach(store.filteredNotes()) { note in
                NoteRow(note: note)
                    .tag(note.id)
                    .listRowSeparator(.visible)
                    .listRowInsets(EdgeInsets(top: 9, leading: 20, bottom: 9, trailing: 18))
            }
        }
        .listStyle(.plain)
        .navigationTitle(store.filterTitle())
        .searchable(text: $store.searchText, placement: .navigationBarDrawer(displayMode: .always), prompt: "搜索笔记")
        .toolbar {
            ToolbarItemGroup(placement: .primaryAction) {
                Button { Task { await store.sync() } } label: {
                    Image(systemName: "arrow.triangle.2.circlepath")
                }
                .accessibilityLabel("同步")
                .disabled(store.isSyncing)
                Button { Task { await store.createNote() } } label: {
                    Image(systemName: "square.and.pencil")
                }
                .accessibilityLabel("新建笔记")
                .accessibilityIdentifier("new-note-button")
                .disabled(store.notebooks.isEmpty || store.filter == .trash)
            }
        }
        .overlay {
            if store.filteredNotes().isEmpty && !store.isSyncing {
                EmptyNotesView(isTrash: store.filter == .trash)
                    .background(AppTheme.paper)
            }
        }
        .safeAreaInset(edge: .bottom) {
            HStack {
                Spacer()
                Text("\(store.filteredNotes().count) 篇笔记")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                Spacer()
            }
            .padding(.vertical, 8)
            .background(.bar)
        }
    }
}
