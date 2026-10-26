import SwiftUI
import PhotosUI

struct DiaryPhotoHeader: View {
    @Environment(LibraryStore.self) private var store
    let note: Note
    @State private var selection: PhotosPickerItem?
    @State private var isUploading = false

    var body: some View {
        PhotosPicker(selection: $selection, matching: .images, photoLibrary: .shared()) {
            ZStack {
                Color(uiColor: .systemGray5)
                if let data = store.diaryImages[note.id], let image = UIImage(data: data) {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFill()
                }
                if isUploading {
                    Color.black.opacity(0.2)
                    ProgressView().tint(.white)
                } else {
                    Image(systemName: store.diaryImages[note.id] == nil ? "plus" : "photo.badge.plus")
                        .font(.system(size: 38, weight: .light))
                        .foregroundStyle(.white)
                        .frame(width: 82, height: 82)
                        .background(.black.opacity(0.2), in: RoundedRectangle(cornerRadius: 4))
                }
            }
            .frame(maxWidth: .infinity)
            .frame(height: 286)
            .clipped()
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(note.isInTrash || isUploading)
        .accessibilityLabel(store.diaryImages[note.id] == nil ? "添加照片" : "更换照片")
        .accessibilityIdentifier("diary-photo-picker")
        .task(id: note.id) { await store.loadDiaryImage(noteID: note.id) }
        .onChange(of: selection) { _, item in
            guard let item else { return }
            isUploading = true
            Task {
                defer { isUploading = false; selection = nil }
                guard let data = try? await item.loadTransferable(type: Data.self),
                      let jpeg = Self.jpegData(from: data) else {
                    isUploading = false
                    return
                }
                await store.addPhoto(id: note.id, jpegData: jpeg)
            }
        }
    }

    private static func jpegData(from data: Data) -> Data? {
        guard let image = UIImage(data: data) else { return nil }
        let maximum: CGFloat = 1600
        let scale = min(1, maximum / max(image.size.width, image.size.height))
        let size = CGSize(width: image.size.width * scale, height: image.size.height * scale)
        let rendered = UIGraphicsImageRenderer(size: size).image { _ in
            image.draw(in: CGRect(origin: .zero, size: size))
        }
        return rendered.jpegData(compressionQuality: 0.82)
    }
}

enum DiaryMetadataSection: Hashable { case mood, weather, favorite, tags, location }

struct DiaryMetadataBar: View {
    let metadata: DiaryMetadata
    let action: (DiaryMetadataSection) -> Void

    var body: some View {
        HStack(spacing: 0) {
            button("face.smiling", "心情", metadata.mood.isEmpty ? Color(uiColor: .tertiaryLabel) : AppTheme.accent, .mood)
            button(weatherIcon, "天气", metadata.weather.isEmpty ? Color(uiColor: .tertiaryLabel) : AppTheme.accent, .weather)
            button(metadata.favorite ? "heart.fill" : "heart", "最喜欢的日记", metadata.favorite ? AppTheme.accent : Color(uiColor: .tertiaryLabel), .favorite)
            button("tag", "标签", Color(uiColor: .tertiaryLabel), .tags)
            button("location", "位置", metadata.location.isEmpty ? Color(uiColor: .tertiaryLabel) : AppTheme.accent, .location)
        }
        .padding(.horizontal, 22)
        .frame(height: 64)
        .overlay(alignment: .top) { Divider().padding(.horizontal, 28) }
        .overlay(alignment: .bottom) { Divider().padding(.horizontal, 28) }
    }

    private var weatherIcon: String {
        DiaryMetadataPanel.weatherChoices.first { $0.id == metadata.weather }?.icon ?? "sun.max"
    }

    private func button(_ icon: String, _ label: String, _ color: Color, _ section: DiaryMetadataSection) -> some View {
        Button { action(section) } label: {
            Image(systemName: icon)
                .font(.system(size: 25, weight: .light))
                .foregroundStyle(color)
                .frame(maxWidth: .infinity, minHeight: 48)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
        .accessibilityIdentifier("diary-metadata-\(section)")
    }
}

struct DiaryMetadataPanel: View {
    @Environment(LibraryStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    let noteID: String
    let initialSection: DiaryMetadataSection
    @State private var tagText = ""

    static let moodChoices: [(id: String, icon: String, label: String)] = [
        ("happy", "face.smiling", "开心"), ("laugh", "face.smiling.inverse", "大笑"),
        ("love", "heart.fill", "心动"), ("calm", "face.dashed", "平静"),
        ("sad", "face.frowning", "难过"), ("angry", "bolt.fill", "生气"),
        ("tired", "moon.zzz.fill", "疲惫"), ("surprised", "exclamationmark.circle", "惊讶")
    ]
    static let weatherChoices: [(id: String, icon: String, label: String)] = [
        ("sunny", "sun.max", "晴"), ("partly-cloudy", "cloud.sun", "多云"),
        ("cloudy", "cloud", "阴"), ("rainy", "cloud.rain", "雨"),
        ("snowy", "cloud.snow", "雪"), ("thunder", "cloud.bolt", "雷雨"),
        ("windy", "wind", "风"), ("sunset", "sunset", "日落"),
        ("foggy", "cloud.fog", "雾"), ("storm", "tornado", "风暴")
    ]

    private var metadata: DiaryMetadata { store.note(id: noteID)?.diaryMetadata ?? DiaryMetadata() }

    var body: some View {
        NavigationStack {
            ScrollViewReader { proxy in
                ScrollView {
                    VStack(spacing: 0) {
                        choiceGrid(title: "心情", choices: Self.moodChoices, selected: metadata.mood, section: .mood) { value in
                            update { $0.mood = value }
                        }
                        Divider().padding(.vertical, 18)
                        choiceGrid(title: "天气", choices: Self.weatherChoices, selected: metadata.weather, section: .weather) { value in
                            update { $0.weather = value }
                        }
                        Divider().padding(.vertical, 18)
                        Toggle("最喜欢的日记", isOn: Binding(get: { metadata.favorite }, set: { value in update { $0.favorite = value } }))
                            .padding(.vertical, 16)
                            .id(DiaryMetadataSection.favorite)
                        Divider()
                        VStack(alignment: .leading, spacing: 12) {
                            Label("标签", systemImage: "tag")
                                .font(.headline)
                            TextField("用逗号分隔，例如：家庭, 旅行", text: $tagText)
                                .textInputAutocapitalization(.never)
                                .autocorrectionDisabled()
                                .padding(12)
                                .background(Color(uiColor: .secondarySystemBackground), in: RoundedRectangle(cornerRadius: 10))
                                .onChange(of: tagText) { _, _ in saveTags() }
                                .accessibilityIdentifier("diary-tags-field")
                        }
                        .padding(.vertical, 20)
                        .id(DiaryMetadataSection.tags)
                        Divider()
                        VStack(alignment: .leading, spacing: 12) {
                            Label("位置", systemImage: "location")
                                .font(.headline)
                            TextField("例如：家里、福州、咖啡馆", text: Binding(get: { metadata.location }, set: { value in update { $0.location = value } }))
                                .padding(12)
                                .background(Color(uiColor: .secondarySystemBackground), in: RoundedRectangle(cornerRadius: 10))
                                .accessibilityIdentifier("diary-location-field")
                        }
                        .padding(.vertical, 20)
                        .id(DiaryMetadataSection.location)
                    }
                    .padding(.horizontal, 24)
                    .padding(.bottom, 30)
                }
                .onAppear {
                    tagText = store.note(id: noteID)?.tags.filter { $0 != "最喜欢的日记" }.joined(separator: ", ") ?? ""
                    proxy.scrollTo(initialSection, anchor: .top)
                }
            }
            .navigationTitle("日记信息")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("完成") { dismiss() } } }
        }
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
    }

    private func choiceGrid(title: String, choices: [(id: String, icon: String, label: String)], selected: String, section: DiaryMetadataSection, action: @escaping (String) -> Void) -> some View {
        LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 4), spacing: 20) {
            ForEach(choices, id: \.id) { choice in
                Button { action(selected == choice.id ? "" : choice.id) } label: {
                    VStack(spacing: 5) {
                        Image(systemName: choice.icon).font(.system(size: 31, weight: .light))
                        Text(choice.label).font(.caption2)
                    }
                    .foregroundStyle(selected == choice.id ? AppTheme.accent : .secondary)
                    .frame(maxWidth: .infinity, minHeight: 62)
                    .background(selected == choice.id ? AppTheme.accent.opacity(0.1) : .clear, in: RoundedRectangle(cornerRadius: 10))
                }
                .buttonStyle(.plain)
                .accessibilityLabel("\(title)：\(choice.label)")
                .accessibilityIdentifier("diary-\(section)-\(choice.id)")
            }
            Button { action("") } label: {
                Text("无")
                    .font(.callout.weight(.semibold))
                    .foregroundStyle(selected.isEmpty ? AppTheme.accent : .secondary)
                    .frame(maxWidth: .infinity, minHeight: 62)
                    .overlay(RoundedRectangle(cornerRadius: 10).stroke(selected.isEmpty ? AppTheme.accent : .clear, lineWidth: 2))
            }
            .accessibilityLabel("清除\(title)")
        }
        .padding(.top, 10)
        .id(section)
    }

    private func update(_ change: (inout DiaryMetadata) -> Void) {
        var value = metadata
        change(&value)
        store.updateDiaryMetadata(id: noteID, metadata: value)
    }

    private func saveTags() {
        let tags = tagText.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
        store.updateDiaryTags(id: noteID, tags: tags)
    }
}
