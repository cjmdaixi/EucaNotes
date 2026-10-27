import SwiftUI

struct LibraryView: View {
    @Environment(LibraryStore.self) private var store
    @State private var path: [DiaryRoute] = []
    @State private var section: DiaryHomeSection = .cards
    @State private var showCalendar = false
    @State private var selectedMonthID: String?
    @State private var isCreating = false

    var body: some View {
        @Bindable var store = store
        NavigationStack(path: $path) {
            Group {
                if section == .cards {
                    MonthCardsView(path: $path, selectedMonthID: $selectedMonthID, showCalendar: $showCalendar)
                } else {
                    DiaryProfileView(path: $path)
                }
            }
            .padding(.bottom, 126)
            .navigationDestination(for: DiaryRoute.self) { route in
                switch route {
                case .month(let id): DiaryListView(monthID: id, path: $path)
                case .note(let id): NoteEditorView(noteID: id, diaryMode: true)
                case .search: DiarySearchView(path: $path)
                }
            }
            .overlay(alignment: .bottom) {
                HomeBottomBar(section: $section, showCalendar: $showCalendar, isCreating: isCreating, createAction: createDiary)
            }
        }
        .background(AppTheme.paper.ignoresSafeArea())
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

    private func createDiary() {
        let now = Date.now
        let year = DiaryText.calendar.component(.year, from: now)
        let month = DiaryText.calendar.component(.month, from: now)
        guard let target = store.diaryMonth(id: selectedMonthID ?? "") ?? store.diaryMonths.first(where: { $0.year == year && $0.month == month }) ?? store.diaryMonths.last else { return }
        isCreating = true
        Task {
            if let id = await store.createDiary(monthID: target.id) {
                path.append(.month(target.id))
                path.append(.note(id))
            }
            isCreating = false
        }
    }
}

private struct MonthCardsView: View {
    @Environment(LibraryStore.self) private var store
    @Binding var path: [DiaryRoute]
    @Binding var selectedMonthID: String?
    @Binding var showCalendar: Bool
    @State private var selectedYear = DiaryText.calendar.component(.year, from: .now)

    private var months: [DiaryMonth] { store.diaryMonths.filter { $0.year == selectedYear } }

    var body: some View {
        GeometryReader { proxy in
            VStack(spacing: 0) {
                HStack(spacing: 14) {
                    Image(systemName: "cloud")
                        .font(.system(size: 32, weight: .light))
                    VStack(alignment: .leading, spacing: 3) {
                        Text(Date.now.formatted(.dateTime.year().month().day().locale(Locale(identifier: "zh_CN"))))
                            .font(.headline)
                        Text(Date.now.formatted(.dateTime.weekday(.wide).locale(Locale(identifier: "zh_CN"))))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    SearchButton(path: $path)
                }
                .padding(.horizontal, 24)
                .padding(.top, 8)

                HStack {
                    Button { changeYear(-1) } label: {
                        Image(systemName: "chevron.left").frame(width: 44, height: 44)
                    }
                    .accessibilityLabel("上一年")
                    Text(String(selectedYear))
                        .font(.system(size: 31, weight: .bold, design: .rounded))
                        .monospacedDigit()
                        .frame(minWidth: 130)
                    Button { changeYear(1) } label: {
                        Image(systemName: "chevron.right").frame(width: 44, height: 44)
                    }
                    .accessibilityLabel("下一年")
                }
                .foregroundStyle(.primary)
                .padding(.top, 56)

                if months.isEmpty {
                    Spacer()
                    if store.isSyncing || store.isPreparingDiary {
                        ProgressView("正在准备桉记书架…")
                    } else {
                        ContentUnavailableView("这一年还没有日记", systemImage: "book.closed", description: Text("切换年份，或新建今天的日记。"))
                    }
                    Spacer()
                } else {
                    let cardWidth = min(330, proxy.size.width * 0.72)
                    let cardHeight = min(510, proxy.size.height * 0.61)
                    MonthCarouselView(
                        months: months,
                        contentRevision: store.notes.map(\.modifiedAt),
                        selectedMonthID: $selectedMonthID,
                        showCalendar: showCalendar,
                        path: $path,
                        store: store,
                        cardWidth: cardWidth,
                        cardHeight: cardHeight
                    )
                    .frame(height: cardHeight + 52)
                    .padding(.top, 8)
                    .padding(.bottom, -22)
                    .accessibilityIdentifier("month-card-carousel")
                }

            }
            .frame(maxWidth: 700)
            .frame(maxWidth: .infinity)
        }
        .background(AppTheme.paper)
        .navigationBarHidden(true)
        .onAppear(perform: selectCurrentMonth)
        .onChange(of: store.diaryMonths.map(\.id)) { _, _ in
            if selectedMonthID == nil {
                selectCurrentMonth()
            } else if !months.contains(where: { $0.id == selectedMonthID }) {
                selectedMonthID = months.first?.id
            }
        }
    }

    private func selectCurrentMonth() {
        let now = Date.now
        let year = DiaryText.calendar.component(.year, from: now)
        selectedYear = year
        selectedMonthID = store.diaryMonths.first { $0.year == year && $0.month == DiaryText.calendar.component(.month, from: now) }?.id ?? months.first?.id
    }

    private func changeYear(_ offset: Int) {
        selectedYear += offset
        selectedMonthID = store.diaryMonths.first { $0.year == selectedYear }?.id
    }

}

private struct MonthCarouselView: UIViewRepresentable {
    let months: [DiaryMonth]
    let contentRevision: [Date]
    @Binding var selectedMonthID: String?
    let showCalendar: Bool
    @Binding var path: [DiaryRoute]
    let store: LibraryStore
    let cardWidth: CGFloat
    let cardHeight: CGFloat

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeUIView(context: Context) -> UICollectionView {
        let layout = UICollectionViewFlowLayout()
        layout.scrollDirection = .horizontal
        layout.itemSize = CGSize(width: cardWidth, height: cardHeight)
        layout.minimumLineSpacing = 18
        let inset = max(0, (UIScreen.main.bounds.width - cardWidth) / 2)
        layout.sectionInset = UIEdgeInsets(top: 0, left: inset, bottom: 0, right: inset)
        let view = UICollectionView(frame: .zero, collectionViewLayout: layout)
        view.register(MonthHostingCell.self, forCellWithReuseIdentifier: MonthHostingCell.reuseID)
        view.dataSource = context.coordinator
        view.delegate = context.coordinator
        view.backgroundColor = .clear
        view.clipsToBounds = false
        view.showsHorizontalScrollIndicator = false
        view.decelerationRate = .fast
        view.contentInsetAdjustmentBehavior = .never
        view.accessibilityIdentifier = "month-card-carousel"
        return view
    }

    func updateUIView(_ collectionView: UICollectionView, context: Context) {
        context.coordinator.parent = self
        let itemSize = CGSize(width: cardWidth, height: cardHeight)
        if let layout = collectionView.collectionViewLayout as? UICollectionViewFlowLayout {
            let inset = max(0, (collectionView.bounds.width - itemSize.width) / 2)
            let sectionInset = UIEdgeInsets(top: 0, left: inset, bottom: 0, right: inset)
            if layout.itemSize != itemSize || layout.sectionInset != sectionInset {
                layout.itemSize = itemSize
                layout.sectionInset = sectionInset
                layout.invalidateLayout()
            }
        }
        collectionView.layoutIfNeeded()
        context.coordinator.update(collectionView, cardSize: itemSize)
    }

    @MainActor
    final class Coordinator: NSObject, UICollectionViewDataSource, UICollectionViewDelegate {
        var parent: MonthCarouselView
        private var monthIDs: [String] = []
        private var contentRevision: [Date] = []
        private var cardSize: CGSize = .zero
        private var dragStartIndex = 0
        private var lastSelected: String?
        private var needsInitialScroll = true

        init(_ parent: MonthCarouselView) {
            self.parent = parent
            self.lastSelected = parent.selectedMonthID
        }

        func update(_ collectionView: UICollectionView, cardSize size: CGSize) {
            let ids = parent.months.map(\.id)
            if ids != monthIDs || contentRevision != parent.contentRevision || size != cardSize {
                needsInitialScroll = ids != monthIDs || size != cardSize || needsInitialScroll
                monthIDs = ids
                contentRevision = parent.contentRevision
                cardSize = size
                collectionView.reloadData()
            }
            for case let cell as MonthHostingCell in collectionView.visibleCells {
                guard let indexPath = collectionView.indexPath(for: cell), parent.months.indices.contains(indexPath.item) else { continue }
                let month = parent.months[indexPath.item]
                cell.configure(
                    month: month,
                    size: cardSize,
                    count: parent.store.diaryNotes(monthID: month.id).count,
                    info: parent.store.infoNote(monthID: month.id),
                    showCalendar: parent.showCalendar,
                    path: parent.$path,
                    store: parent.store
                )
            }
            if needsInitialScroll || lastSelected != parent.selectedMonthID {
                needsInitialScroll = false
                DispatchQueue.main.async {
                    self.scrollToSelected(collectionView, animated: false)
                }
            }
        }

        func collectionView(_ collectionView: UICollectionView, numberOfItemsInSection section: Int) -> Int {
            parent.months.count
        }

        func collectionView(_ collectionView: UICollectionView, cellForItemAt indexPath: IndexPath) -> UICollectionViewCell {
            let cell = collectionView.dequeueReusableCell(withReuseIdentifier: MonthHostingCell.reuseID, for: indexPath) as! MonthHostingCell
            let month = parent.months[indexPath.item]
            cell.configure(
                month: month,
                size: cardSize,
                count: parent.store.diaryNotes(monthID: month.id).count,
                info: parent.store.infoNote(monthID: month.id),
                showCalendar: parent.showCalendar,
                path: parent.$path,
                store: parent.store
            )
            return cell
        }

        func collectionView(_ collectionView: UICollectionView, didSelectItemAt indexPath: IndexPath) {
            guard !parent.showCalendar else { return }
            parent.path.append(.month(parent.months[indexPath.item].id))
        }

        func scrollViewWillBeginDragging(_ scrollView: UIScrollView) {
            dragStartIndex = nearestIndex(scrollView)
        }

        func scrollViewWillEndDragging(_ scrollView: UIScrollView, withVelocity velocity: CGPoint, targetContentOffset: UnsafeMutablePointer<CGPoint>) {
            let step = cardSize.width + 18
            let startX = CGFloat(dragStartIndex) * step
            let delta = scrollView.contentOffset.x - startX
            let peek = max(0, (scrollView.bounds.width - cardSize.width) / 2)
            let visibleWidth = peek + abs(delta)
            var targetIndex = dragStartIndex
            if visibleWidth > cardSize.width * 2 / 3 {
                let direction = delta > 0 ? 1 : -1
                let steps = max(1, Int(visibleWidth / cardSize.width))
                targetIndex = min(max(0, dragStartIndex + direction * steps), parent.months.count - 1)
            }
            targetContentOffset.pointee.x = CGFloat(targetIndex) * step
        }

        func scrollViewDidEndDecelerating(_ scrollView: UIScrollView) {
            finishSelection(scrollView)
        }

        func scrollViewDidEndDragging(_ scrollView: UIScrollView, willDecelerate decelerate: Bool) {
            if !decelerate { finishSelection(scrollView) }
        }

        func scrollViewDidEndScrollingAnimation(_ scrollView: UIScrollView) {
            finishSelection(scrollView)
        }

        private func scrollToSelected(_ collectionView: UICollectionView, animated: Bool) {
            guard let id = parent.selectedMonthID,
                  let index = parent.months.firstIndex(where: { $0.id == id }) else { return }
            lastSelected = id
            collectionView.layoutIfNeeded()
            let offset = CGPoint(x: CGFloat(index) * (cardSize.width + 18), y: 0)
            collectionView.setContentOffset(offset, animated: animated)
        }

        private func nearestIndex(_ scrollView: UIScrollView) -> Int {
            guard !parent.months.isEmpty else { return 0 }
            let step = cardSize.width + 18
            return min(max(0, Int((scrollView.contentOffset.x / step).rounded())), parent.months.count - 1)
        }

        private func finishSelection(_ scrollView: UIScrollView) {
            guard parent.selectedMonthID != nil else { return }
            let index = nearestIndex(scrollView)
            guard parent.months.indices.contains(index) else { return }
            let id = parent.months[index].id
            lastSelected = id
            if parent.selectedMonthID != id { parent.selectedMonthID = id }
        }
    }
}

private final class MonthHostingCell: UICollectionViewCell {
    static let reuseID = "MonthHostingCell"
    private var host: UIHostingController<AnyView>?

    override init(frame: CGRect) {
        super.init(frame: frame)
        let host = UIHostingController(rootView: AnyView(EmptyView()))
        host.view.backgroundColor = .clear
        contentView.addSubview(host.view)
        host.view.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            host.view.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            host.view.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
            host.view.topAnchor.constraint(equalTo: contentView.topAnchor),
            host.view.bottomAnchor.constraint(equalTo: contentView.bottomAnchor)
        ])
        self.host = host
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    @MainActor
    func configure(month: DiaryMonth, size: CGSize, count: Int, info _: Note?, showCalendar: Bool, path: Binding<[DiaryRoute]>, store: LibraryStore) {
        let content = Group {
            if showCalendar {
                MonthCalendarCard(month: month, path: path)
            } else {
                MonthCard(month: month, count: count, path: path)
            }
        }
        .environment(store)
        .frame(width: size.width, height: size.height)
        host?.rootView = AnyView(content)
    }
}

private struct MonthCard: View {
    @Environment(LibraryStore.self) private var store
    let month: DiaryMonth
    let count: Int
    @Binding var path: [DiaryRoute]
    @State private var showBackgroundEditor = false

    private var info: Note? { store.infoNote(monthID: month.id) }
    private var writtenDays: Int {
        Set(store.diaryNotes(monthID: month.id).compactMap { DiaryText.day(from: $0.title) }).count
    }
    private var daysInMonth: Int {
        let first = DiaryText.calendar.date(from: DateComponents(year: month.year, month: month.month)) ?? .now
        return DiaryText.calendar.range(of: .day, in: .month, for: first)?.count ?? 30
    }

    var body: some View {
        ZStack(alignment: .topLeading) {
            background
            LinearGradient(colors: [.black.opacity(0.38), .clear, .clear, .black.opacity(0.4)], startPoint: .top, endPoint: .bottom)
            VStack(alignment: .leading, spacing: 0) {
                Text(month.monthTitle)
                    .font(.system(size: 52, weight: .bold, design: .serif))
                    .shadow(color: .black.opacity(0.25), radius: 5, y: 2)
                Spacer()
                HStack(spacing: 9) {
                    Capsule()
                        .fill(.white.opacity(0.62))
                        .frame(width: 62, height: 5)
                    Text("\(writtenDays) / \(daysInMonth)")
                    Spacer()
                    if store.loadingDiaryImageIDs.contains(info?.id ?? "") { ProgressView().tint(.white) }
                    Button { showBackgroundEditor = true } label: {
                        Image(systemName: "ellipsis")
                            .frame(width: 44, height: 32)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("设置月份背景")
                    .accessibilityIdentifier("month-background-button")
                }
                .font(.subheadline.weight(.semibold))
            }
            .foregroundStyle(.white)
            .padding(26)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .clipShape(RoundedRectangle(cornerRadius: 30, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 30).stroke(.white.opacity(0.22), lineWidth: 1))
        .shadow(color: .black.opacity(0.14), radius: 22, y: 10)
        .contentShape(RoundedRectangle(cornerRadius: 30))
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(month.title)，\(count) 篇日记")
        .accessibilityAddTraits(.isButton)
        .accessibilityIdentifier("month-card-\(month.year)-\(month.month)")
        .task(id: info?.id) {
            guard let info else { return }
            await store.loadDiaryImage(noteID: info.id, backgroundOnly: true)
        }
        .sheet(isPresented: $showBackgroundEditor) {
            MonthBackgroundEditor(month: month)
        }
    }

    @ViewBuilder private var background: some View {
        Group {
            if let info, let hex = DiaryText.backgroundColorHex(in: info.content) {
                AppTheme.color(hex: hex)
            } else if let info, let data = store.diaryImages[info.id], let image = UIImage(data: data) {
                Image(uiImage: image).resizable().scaledToFill()
            } else {
                Color(uiColor: .systemGray4)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .clipped()
    }
}

private struct DiaryListView: View {
    @Environment(LibraryStore.self) private var store
    let monthID: String
    @Binding var path: [DiaryRoute]
    @State private var ascending = false
    @State private var isCreating = false

    var body: some View {
        let notes = ascending ? store.diaryNotes(monthID: monthID).reversed() : Array(store.diaryNotes(monthID: monthID))
        ScrollView {
            LazyVStack(spacing: 18) {
                ForEach(Array(notes), id: \.id) { note in
                    Button { path.append(.note(note.id)) } label: {
                        DiaryRow(note: note, month: store.diaryMonth(id: monthID))
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("diary-row-\(note.id)")
                }
            }
            .padding(.horizontal, 20)
            .padding(.top, 12)
            .padding(.bottom, 30)
        }
        .background(AppTheme.paper)
        .overlay {
            if notes.isEmpty && !store.isSyncing {
                ContentUnavailableView("这个月还没有日记", systemImage: "square.and.pencil", description: Text("点右上角 +，写下今天。"))
            }
        }
        .navigationTitle(store.diaryMonth(id: monthID)?.title ?? "日记")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                HStack(spacing: 6) {
                    Button { ascending.toggle() } label: {
                        Image(systemName: ascending ? "arrow.up" : "arrow.down").frame(width: 40, height: 40)
                    }
                    .accessibilityLabel(ascending ? "最新日记在前" : "最早日记在前")
                    Button {
                        isCreating = true
                        Task {
                            if let id = await store.createDiary(monthID: monthID) { path.append(.note(id)) }
                            isCreating = false
                        }
                    } label: {
                        Image(systemName: isCreating ? "progress.view" : "plus").frame(width: 40, height: 40)
                    }
                    .disabled(isCreating)
                    .accessibilityLabel("新建日记")
                    .accessibilityIdentifier("new-month-diary-button")
                }
            }
        }
    }
}

private struct DiaryRow: View {
    @Environment(LibraryStore.self) private var store
    let note: Note
    let month: DiaryMonth?

    var body: some View {
        HStack(spacing: 0) {
            VStack(spacing: 9) {
                Text(DiaryText.day(from: note.title).map(String.init) ?? "—")
                    .font(.system(size: 44, weight: .medium, design: .serif))
                    .monospacedDigit()
                if let month {
                    Text(DiaryText.weekday(for: month, note: note))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Text(note.title)
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
            .frame(width: 104)
            .frame(maxHeight: .infinity)
            .background(Color(uiColor: .secondarySystemBackground))
            VStack(alignment: .leading) {
                if let data = store.diaryImages[note.id], let image = UIImage(data: data) {
                    Image(uiImage: image).resizable().scaledToFill()
                } else {
                    ZStack(alignment: .bottomLeading) {
                        LinearGradient(colors: [AppTheme.accent.opacity(0.12), AppTheme.accent.opacity(0.28)], startPoint: .topLeading, endPoint: .bottomTrailing)
                        VStack(alignment: .leading, spacing: 7) {
                            if !note.diaryMetadata.headline.isEmpty {
                                Text(note.diaryMetadata.headline)
                                    .font(.headline)
                                    .lineLimit(2)
                            }
                            Text(note.preview.isEmpty ? "写下这一天…" : note.preview)
                                .font(.system(size: 17, design: .serif))
                                .lineLimit(4)
                        }
                        .foregroundStyle(.primary.opacity(0.75))
                        .multilineTextAlignment(.leading)
                        .padding(18)
                    }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .clipped()
        }
        .frame(height: 174)
        .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 22).stroke(Color.primary.opacity(0.04)))
        .shadow(color: .black.opacity(0.055), radius: 12, y: 5)
        .task(id: note.id) {
            await store.loadNote(id: note.id)
            await store.loadDiaryImage(noteID: note.id)
        }
    }
}
