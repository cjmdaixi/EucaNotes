import SwiftUI

struct NoteEditorView: View {
    @Environment(LibraryStore.self) private var store
    let noteID: String
    @State private var title = ""
    @State private var bridge = RichTextEditorBridge()
    @State private var saveTask: Task<Void, Never>?
    @State private var confirmDelete = false
    @State private var showInfo = false
    @State private var showLink = false
    @State private var linkURL = "https://"

    var body: some View {
        Group {
            if let note = store.note(id: noteID) {
                if note.isEncrypted {
                    ContentUnavailableView("这篇笔记已加密", systemImage: "lock.fill", description: Text("当前版本不会尝试解密笔记内容。"))
                } else {
                    editor(note)
                }
            }
        }
        .background(AppTheme.paper)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .principal) {
                Label(store.syncState.title, systemImage: statusIcon)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .labelStyle(.titleAndIcon)
            }
            ToolbarItemGroup(placement: .primaryAction) {
                if let note = store.note(id: noteID), !note.isInTrash {
                    ShareLink(item: note.displayTitle + "\n\n" + note.preview) {
                        Image(systemName: "square.and.arrow.up")
                    }
                    .accessibilityLabel("分享笔记")
                }
                Menu {
                    Button { showInfo = true } label: { Label("笔记信息", systemImage: "info.circle") }
                    if store.note(id: noteID)?.isInTrash == true {
                        Button { Task { await store.restoreFromTrash(id: noteID) } } label: { Label("恢复笔记", systemImage: "arrow.uturn.backward") }
                    }
                    Divider()
                    Button(role: .destructive) { confirmDelete = true } label: {
                        Label(store.note(id: noteID)?.isInTrash == true ? "永久删除" : "移到废纸篓", systemImage: "trash")
                    }
                } label: { Image(systemName: "ellipsis.circle") }
                .accessibilityLabel("更多操作")
            }
        }
        .confirmationDialog(store.note(id: noteID)?.isInTrash == true ? "永久删除这篇笔记？此操作无法撤销。" : "将这篇笔记移到废纸篓？", isPresented: $confirmDelete, titleVisibility: .visible) {
            Button(store.note(id: noteID)?.isInTrash == true ? "永久删除" : "移到废纸篓", role: .destructive) {
                Task { await store.moveToTrash(id: noteID) }
            }
            Button("取消", role: .cancel) {}
        }
        .sheet(isPresented: $showInfo) {
            if let note = store.note(id: noteID) { NoteInfoView(note: note) }
        }
        .sheet(isPresented: $showLink) {
            NavigationStack {
                Form {
                    TextField("链接地址", text: $linkURL)
                        .keyboardType(.URL)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                }
                .navigationTitle("插入链接")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) { Button("取消") { showLink = false } }
                    ToolbarItem(placement: .confirmationAction) {
                        Button("插入") {
                            bridge.perform?("createLink", linkURL)
                            showLink = false
                        }.disabled(URL(string: linkURL) == nil)
                    }
                }
            }
            .presentationDetents([.medium])
        }
        .task(id: noteID) {
            title = store.note(id: noteID)?.title ?? ""
            // selectNote owns the independent request lifetime; starting another
            // view-scoped request here can cancel it during navigation.
        }
        .onDisappear {
            saveTask?.cancel()
            Task { await store.saveNote(id: noteID) }
        }
    }

    private func editor(_ note: Note) -> some View {
        VStack(spacing: 0) {
            TextField("无标题", text: $title, axis: .vertical)
                .font(.system(size: 30, weight: .bold))
                .lineLimit(1...3)
                .padding(.horizontal, 24)
                .padding(.top, 14)
                .padding(.bottom, 4)
                .disabled(note.isInTrash)
                .accessibilityIdentifier("note-title-field")
                .onChange(of: title) { _, newTitle in
                    guard newTitle != store.note(id: noteID)?.title else { return }
                    store.updateNote(id: noteID, title: newTitle)
                    scheduleSave()
                }
            if store.loadingNoteIDs.contains(noteID) {
                ProgressView("正在载入笔记…")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                RichTextEditor(noteID: noteID, content: note.content, bridge: bridge) { html in
                    guard html != store.note(id: noteID)?.content else { return }
                    store.updateNote(id: noteID, content: html)
                    scheduleSave()
                }
                .disabled(note.isInTrash)
                .overlay {
                    if note.isInTrash {
                        AppTheme.paper.opacity(0.86)
                        ContentUnavailableView("笔记在废纸篓中", systemImage: "trash", description: Text("恢复后才能继续编辑。"))
                    }
                }
            }
        }
        .safeAreaInset(edge: .bottom) {
            if !note.isInTrash { FormattingBar(bridge: bridge, showLink: $showLink) }
        }
    }

    private var statusIcon: String {
        switch store.syncState {
        case .idle, .saved: return "checkmark.icloud"
        case .syncing: return "arrow.triangle.2.circlepath.icloud"
        case .failed: return "exclamationmark.icloud"
        }
    }

    private func scheduleSave() {
        saveTask?.cancel()
        saveTask = Task {
            try? await Task.sleep(for: .milliseconds(900))
            guard !Task.isCancelled else { return }
            await store.saveNote(id: noteID)
        }
    }
}

private struct FormattingBar: View {
    let bridge: RichTextEditorBridge
    @Binding var showLink: Bool

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 3) {
                Menu {
                    Button("正文") { bridge.perform?("paragraph", nil) }
                    Button("二级标题") { bridge.perform?("h2", nil) }
                    Button("三级标题") { bridge.perform?("h3", nil) }
                } label: { icon("textformat.size", label: "段落样式") }
                divider
                button("bold", "粗体", "bold")
                button("italic", "斜体", "italic")
                button("underline", "下划线", "underline")
                divider
                button("list.bullet", "无序列表", "insertUnorderedList")
                button("list.number", "有序列表", "insertOrderedList")
                button("checklist", "待办事项", "task")
                button("text.quote", "引用", "formatBlock", value: "blockquote")
                button("chevron.left.forwardslash.chevron.right", "代码块", "code")
                Button { showLink = true } label: { icon("link", label: "插入链接") }
                    .accessibilityLabel("插入链接")
                divider
                button("arrow.uturn.backward", "撤销", "undo")
                button("arrow.uturn.forward", "重做", "redo")
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 7)
        }
        .background(.bar)
        .overlay(alignment: .top) { Divider() }
    }

    private var divider: some View {
        Divider().frame(height: 22).padding(.horizontal, 4)
    }

    private func button(_ iconName: String, _ label: String, _ command: String, value: String? = nil) -> some View {
        Button { bridge.perform?(command, value) } label: { icon(iconName, label: label) }
            .accessibilityLabel(label)
    }

    private func icon(_ name: String, label: String) -> some View {
        Image(systemName: name)
            .font(.system(size: 16, weight: .medium))
            .frame(width: 38, height: 36)
            .contentShape(Rectangle())
            .accessibilityLabel(label)
    }
}

private struct NoteInfoView: View {
    @Environment(LibraryStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    let note: Note
    @State private var tagText = ""
    @State private var notebookID = ""

    var body: some View {
        NavigationStack {
            Form {
                Section("所属笔记本") {
                    Picker("笔记本", selection: $notebookID) {
                        ForEach(store.notebooks) { notebook in
                            Text(notebook.title).tag(notebook.id)
                        }
                    }
                }
                Section("标签") {
                    TextField("用逗号分隔，例如：工作, 灵感", text: $tagText, axis: .vertical)
                }
                Section("信息") {
                    LabeledContent("创建时间", value: note.createdAt.formatted(date: .long, time: .shortened))
                    LabeledContent("修改时间", value: note.modifiedAt.formatted(date: .long, time: .shortened))
                    LabeledContent("版本", value: "\(note.version)")
                }
            }
            .navigationTitle("笔记信息")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("完成") {
                        store.updateMetadata(id: note.id, parentID: notebookID, tags: tagText.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty })
                        dismiss()
                        Task { await store.saveNote(id: note.id) }
                    }
                }
            }
            .onAppear { tagText = note.tags.joined(separator: ", "); notebookID = note.parentID }
        }
    }
}
