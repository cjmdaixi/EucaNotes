import Foundation

@MainActor
extension LibraryStore {
    static let diaryShelfName = "桉记"

    var diaryMonths: [DiaryMonth] {
        notebooks.compactMap(DiaryMonth.parse).sorted {
            ($0.year, $0.month) < ($1.year, $1.month)
        }
    }

    var allDiaryNotes: [Note] {
        let monthIDs = Set(diaryMonths.map(\.id))
        return notes.filter { monthIDs.contains($0.parentID) && $0.title != "信息" && !$0.isInTrash && !$0.isArchived }
    }

    func diaryMonth(id: String) -> DiaryMonth? {
        diaryMonths.first { $0.id == id }
    }

    func infoNote(monthID: String) -> Note? {
        notes.first { $0.parentID == monthID && $0.title == "信息" && !$0.isInTrash }
    }

    func diaryNotes(monthID: String) -> [Note] {
        notes.filter {
            $0.parentID == monthID && $0.title != "信息" && !$0.isInTrash && !$0.isArchived
        }.sorted {
            let left = DiaryText.day(from: $0.title)
            let right = DiaryText.day(from: $1.title)
            if left != right { return (left ?? 0) > (right ?? 0) }
            return $0.modifiedAt > $1.modifiedAt
        }
    }
}
