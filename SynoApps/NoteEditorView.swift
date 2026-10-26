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
    @State private var showFormatPanel = false
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
            ToolbarItemGroup(placement: .primaryAction) {
                HStack(spacing: 0) {
                    Button { showInfo = true } label: {
                        Image(systemName: "info.circle")
                            .font(.title3)
                            .frame(width: 42, height: 42)
                    }
                    .accessibilityLabel("笔记信息")
                    Menu {
                        Label(store.syncState.title, systemImage: "checkmark.icloud")
                            .disabled(true)
                        if let note = store.note(id: noteID), !note.isInTrash {
                            ShareLink(item: note.displayTitle + "\n\n" + note.preview) {
                                Label("共享", systemImage: "square.and.arrow.up")
                            }
                        }
                        if store.note(id: noteID)?.isInTrash == true {
                            Button { Task { await store.restoreFromTrash(id: noteID) } } label: {
                                Label("恢复笔记", systemImage: "arrow.uturn.backward")
                            }
                        }
                        Divider()
                        Button(role: .destructive) { confirmDelete = true } label: {
                            Label(store.note(id: noteID)?.isInTrash == true ? "永久删除" : "移到废纸篓", systemImage: "trash")
                        }
                    } label: {
                        Image(systemName: "ellipsis")
                            .font(.title3)
                            .frame(width: 42, height: 42)
                    }
                    .accessibilityLabel("更多操作")
                }
                .background(.regularMaterial, in: Capsule())
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
        }
        .onDisappear {
            saveTask?.cancel()
            Task { await store.saveNote(id: noteID) }
        }
    }

    private func editor(_ note: Note) -> some View {
        VStack(spacing: 0) {
            TextField("未命名新笔记", text: $title, axis: .vertical)
                .font(.system(size: 30, weight: .bold))
                .lineLimit(1...3)
                .padding(.horizontal, 22)
                .padding(.top, 12)
                .padding(.bottom, 6)
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
            if !note.isInTrash {
                FormattingBar(
                    bridge: bridge,
                    showLink: $showLink,
                    showInfo: $showInfo,
                    isExpanded: $showFormatPanel
                )
            }
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
    @Binding var showInfo: Bool
    @Binding var isExpanded: Bool

    private let columns = Array(repeating: GridItem(.flexible(), spacing: 7), count: 6)

    var body: some View {
        VStack(spacing: 10) {
            if isExpanded { formatGrid }
            HStack(spacing: 0) {
                commandButton("arrow.uturn.backward", "撤销", "undo")
                commandButton("arrow.uturn.forward", "重做", "redo")
                Button { showInfo = true } label: {
                    Image(systemName: "number")
                        .font(.title3)
                        .frame(width: 46, height: 44)
                }
                .accessibilityLabel("标签")
                Button {
                    UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
                } label: {
                    Image(systemName: "keyboard.chevron.compact.down")
                        .font(.title3)
                        .frame(width: 46, height: 44)
                }
                .accessibilityLabel("收起键盘")
                Button { showInfo = true } label: {
                    Image(systemName: "doc.text.magnifyingglass")
                        .font(.title3)
                        .frame(width: 46, height: 44)
                }
                .accessibilityLabel("笔记信息")
                Button { isExpanded.toggle() } label: {
                    Text(isExpanded ? "ABC" : "B I U")
                        .font(.system(size: 17, weight: .semibold))
                        .frame(width: 58, height: 44)
                }
                .accessibilityLabel(isExpanded ? "收起格式面板" : "展开格式面板")
            }
            .padding(.horizontal, 5)
            .background(.regularMaterial, in: Capsule())
            .shadow(color: .black.opacity(0.08), radius: 12, y: 4)
        }
        .foregroundStyle(.primary)
        .padding(.horizontal, 12)
        .padding(.bottom, 8)
    }

    private var formatGrid: some View {
        LazyVGrid(columns: columns, spacing: 7) {
            commandButton("textformat.size", "二级标题", "h2")
            commandButton("bold", "粗体", "bold")
            commandButton("italic", "斜体", "italic")
            commandButton("underline", "下划线", "underline")
            commandButton("strikethrough", "删除线", "strikeThrough")
            commandButton("text.quote", "引用", "formatBlock", value: "blockquote")
            commandButton("list.bullet", "无序列表", "insertUnorderedList")
            commandButton("list.number", "有序列表", "insertOrderedList")
            commandButton("checklist", "待办事项", "task")
            commandButton("chevron.left.forwardslash.chevron.right", "代码块", "code")
            Button { showLink = true } label: {
                Image(systemName: "link")
                    .font(.title3)
                    .frame(maxWidth: .infinity, minHeight: 48)
                    .background(Color(uiColor: .secondarySystemBackground), in: RoundedRectangle(cornerRadius: 8))
            }
            .accessibilityLabel("插入链接")
            commandButton("textformat", "正文", "paragraph")
        }
        .padding(8)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .shadow(color: .black.opacity(0.08), radius: 12, y: 4)
    }

    private func commandButton(_ icon: String, _ label: String, _ command: String, value: String? = nil) -> some View {
        Button { bridge.perform?(command, value) } label: {
            Image(systemName: icon)
                .font(.title3)
                .frame(maxWidth: .infinity, minHeight: 48)
                .background(Color(uiColor: .secondarySystemBackground), in: RoundedRectangle(cornerRadius: 8))
        }
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
                    LabeledContent("版本", value: note.version)
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
