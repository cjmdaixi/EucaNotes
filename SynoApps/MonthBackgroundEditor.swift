import SwiftUI
import PhotosUI

struct MonthBackgroundEditor: View {
    @Environment(LibraryStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    let month: DiaryMonth
    @State private var selection: PhotosPickerItem?
    @State private var isSaving = false

    private let colors = [
        "68D5E8", "68B7EC", "6D8DEB", "8068E8", "AA68E8", "EC68D5",
        "EC68A5", "EC6868", "EC9568", "ECB568", "ECD568", "B5E886",
        "86E89B", "68D5B5", "68C5D5", "D5D5D5", "959595", "303030"
    ]

    private var currentHex: String? {
        guard let info = store.infoNote(monthID: month.id) else { return nil }
        return DiaryText.backgroundColorHex(in: info.content)?.trimmingCharacters(in: CharacterSet(charactersIn: "#"))
    }

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 22) {
                PhotosPicker(selection: $selection, matching: .images, photoLibrary: .shared()) {
                    HStack {
                        Text("照片")
                        Spacer()
                        if isSaving { ProgressView() }
                        else { Image(systemName: "chevron.right").foregroundStyle(.tertiary) }
                    }
                    .font(.headline)
                    .frame(minHeight: 48)
                    .contentShape(Rectangle())
                }
                .disabled(isSaving)
                .accessibilityIdentifier("month-background-photo")

                Text("颜色")
                    .font(.headline)
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 14), count: 6), spacing: 16) {
                    ForEach(colors, id: \.self) { hex in
                        Button {
                            isSaving = true
                            Task {
                                await store.setMonthBackgroundColor(monthID: month.id, hex: hex)
                                isSaving = false
                                dismiss()
                            }
                        } label: {
                            Circle()
                                .fill(AppTheme.color(hex: hex))
                                .frame(width: 42, height: 42)
                                .overlay {
                                    if currentHex == hex {
                                        Image(systemName: "checkmark")
                                            .font(.caption.bold())
                                            .foregroundStyle(.white)
                                            .shadow(radius: 2)
                                    }
                                }
                        }
                        .buttonStyle(.plain)
                        .disabled(isSaving)
                        .accessibilityLabel("使用颜色 \(hex)")
                        .accessibilityIdentifier("month-background-color-\(hex)")
                    }
                }
                Spacer()
            }
            .padding(.horizontal, 24)
            .padding(.top, 18)
            .navigationTitle("月份背景")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("关闭") { dismiss() }
                }
            }
        }
        .presentationDetents([.medium])
        .presentationDragIndicator(.visible)
        .onChange(of: selection) { item in
            guard let item else { return }
            isSaving = true
            Task {
                defer { isSaving = false; selection = nil }
                guard let data = try? await item.loadTransferable(type: Data.self),
                      let jpeg = DiaryImageCompression.jpegData(from: data) else { return }
                await store.setMonthBackgroundPhoto(monthID: month.id, jpegData: jpeg)
                dismiss()
            }
        }
    }
}
