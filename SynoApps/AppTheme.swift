import SwiftUI

enum AppTheme {
    static let accent = Color(red: 0.91, green: 0.39, blue: 0.22)
    static let sidebar = Color(red: 0.135, green: 0.145, blue: 0.15)
    static let sidebarSecondary = Color(red: 0.18, green: 0.19, blue: 0.20)
    static let paper = Color(uiColor: .systemBackground)
    static let secondaryPaper = Color(uiColor: .secondarySystemBackground)
    static let subtleText = Color(uiColor: .secondaryLabel)
}

struct SynoMark: View {
    var size: CGFloat = 54

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: size * 0.24, style: .continuous)
                .fill(AppTheme.accent)
            Image(systemName: "note.text")
                .font(.system(size: size * 0.46, weight: .medium))
                .foregroundStyle(.white)
                .offset(y: -1)
        }
        .frame(width: size, height: size)
        .shadow(color: AppTheme.accent.opacity(0.2), radius: size * 0.15, y: size * 0.07)
        .accessibilityHidden(true)
    }
}

struct NoteRow: View {
    let note: Note

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            Text(note.displayTitle)
                .font(.headline)
                .lineLimit(2)
                .foregroundStyle(note.isInTrash ? .secondary : .primary)
            if !note.preview.isEmpty {
                Text(note.preview)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
            HStack(spacing: 8) {
                Text(note.modifiedAt.chineseRelativeDescription)
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                if !note.tags.isEmpty {
                    Text(note.tags.prefix(2).map { "#\($0)" }.joined(separator: " "))
                        .font(.caption)
                        .foregroundStyle(AppTheme.accent)
                        .lineLimit(1)
                }
                if note.isEncrypted {
                    Image(systemName: "lock.fill")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
            }
        }
        .padding(.vertical, 7)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(note.displayTitle)，\(note.preview)")
    }
}

struct EmptyNotesView: View {
    var isTrash = false

    var body: some View {
        ContentUnavailableView {
            Image(systemName: isTrash ? "trash" : "square.and.pencil")
                .font(.system(size: 38, weight: .light))
                .foregroundStyle(.tertiary)
                .padding(.bottom, 6)
            Text(isTrash ? "废纸篓是空的" : "这里还没有笔记")
                .font(.title3.weight(.semibold))
            Text(isTrash ? "删除的笔记会出现在这里。" : "新建一篇笔记，开始记录此刻的想法。")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
    }
}

private extension Date {
    var chineseRelativeDescription: String {
        let interval = max(0, -timeIntervalSinceNow)
        if interval < 60 { return "刚刚" }
        if interval < 3_600 { return "\(max(1, Int(interval / 60))) 分钟前" }
        if interval < 86_400 { return "\(Int(interval / 3_600)) 小时前" }
        if interval < 7 * 86_400 { return "\(Int(interval / 86_400)) 天前" }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        let sameYear = Calendar.current.component(.year, from: self) == Calendar.current.component(.year, from: .now)
        formatter.dateFormat = sameYear ? "M月d日" : "yyyy年M月d日"
        return formatter.string(from: self)
    }
}
