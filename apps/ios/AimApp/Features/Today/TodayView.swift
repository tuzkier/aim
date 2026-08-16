import SwiftUI

struct TodayView: View {
    @Bindable var store: TodayStore
    @Environment(AppSessionStore.self) private var session
    @State private var showingPregnancySetup = false

    var body: some View {
        NavigationStack {
            Group {
                if session.pregnancyID == nil {
                    pregnancySetupContent
                } else if case .failed(let message) = store.state, store.snapshot == nil {
                    ContentUnavailableView {
                        Label("今天还没加载", systemImage: "wifi.exclamationmark")
                    } description: {
                        Text(message)
                    } actions: {
                        Button("重试") { Task { await store.load() } }
                            .buttonStyle(.borderedProminent)
                    }
                } else {
                    todayContent
                }
            }
            .navigationTitle("今天")
            .background(Color.aimWarmBackground)
            .refreshable { await store.load() }
            .task {
                if store.snapshot == nil { await store.load() }
            }
            .sheet(isPresented: $showingPregnancySetup) {
                PregnancySetupView()
            }
        }
    }

    private var pregnancySetupContent: some View {
        VStack(spacing: 18) {
            Image(systemName: "calendar.badge.plus")
                .font(.system(size: 42))
                .foregroundStyle(Color.aimAccent)
            Text("先逛逛 Aim")
                .font(.title2.weight(.semibold))
            Text("补充预产期后，我们才能把孕周、产检提醒和每个阶段的待办安排准确。现在不填也可以。")
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
            Button("补充预产期") { showingPregnancySetup = true }
                .buttonStyle(.borderedProminent)
        }
        .padding(28)
        .aimWarmCard()
        .padding(20)
    }

    @ViewBuilder
    private var todayContent: some View {
        if let snapshot = store.snapshot {
            List {
                Section {
                    pregnancyHeader(snapshot)
                }
                .listRowBackground(Color.clear)
                .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 10, trailing: 16))

                if let priorityTask = snapshot.priorityTask {
                    Section("现在最重要") {
                        NavigationLink {
                            TaskDetailView(task: priorityTask, repository: store.repository)
                        } label: {
                            PriorityTaskRow(task: priorityTask)
                        }
                        .swipeActions(edge: .trailing) {
                            Button { Task { await store.complete(priorityTask) } } label: {
                                Label("完成", systemImage: "checkmark")
                            }
                            .tint(.green)
                        }
                    }
                }

                Section("接下来") {
                    if snapshot.upcomingTasks.isEmpty {
                        Text("这几天没有新的事项，先好好休息。")
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(snapshot.upcomingTasks) { task in
                            NavigationLink {
                                TaskDetailView(task: task, repository: store.repository)
                            } label: {
                                TaskRow(task: task)
                            }
                        }
                    }
                }

                Section {
                    Label("家庭还有 \(snapshot.familyOpenTaskCount) 项未完成事项", systemImage: "person.2.fill")
                        .foregroundStyle(.secondary)
                }
            }
            .listStyle(.insetGrouped)
        } else {
            ProgressView("正在准备今天")
        }
    }

    private func pregnancyHeader(_ snapshot: TodaySnapshot) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("孕 \(snapshot.weeks) 周 \(snapshot.days) 天")
                .font(.title2.weight(.semibold))
            Text("今天只需要照顾好一件重要的事，其余慢慢来。")
                .font(.body)
                .foregroundStyle(.secondary)
            ProgressView(value: Double(snapshot.weeks), total: 40)
                .tint(.aimAccent)
        }
        .aimWarmCard()
    }
}

struct PregnancySetupView: View {
    @Environment(AppSessionStore.self) private var session
    @Environment(\.dismiss) private var dismiss
    @State private var dateMode: PregnancyDateMode = .dueDate
    @State private var selectedDate = Calendar.current.date(byAdding: .day, value: 154, to: .now) ?? .now
    @State private var isSubmitting = false
    @State private var errorMessage: String?

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Picker("我知道的是", selection: $dateMode) {
                        ForEach(PregnancyDateMode.allCases, id: \.self) { mode in
                            Text(mode.title).tag(mode)
                        }
                    }
                    DatePicker(
                        dateMode.dateTitle,
                        selection: $selectedDate,
                        in: dateMode.dateRange,
                        displayedComponents: .date,
                    )
                    Text(dateMode.calculatedSummary(for: selectedDate))
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                } footer: {
                    Text("两种日期都按孕 40 周（280 天）换算。之后可以在孕期档案里调整。")
                }

                if let errorMessage {
                    Section { Text(errorMessage).foregroundStyle(.red) }
                }

                Section {
                    Button {
                        Task { await save() }
                    } label: {
                        if isSubmitting {
                            ProgressView().frame(maxWidth: .infinity)
                        } else {
                            Text("保存并生成计划").frame(maxWidth: .infinity)
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(isSubmitting)
                }
            }
            .navigationTitle("补充孕期信息")
            .onChange(of: dateMode) { _, mode in
                selectedDate = mode == .dueDate
                    ? Calendar.current.date(byAdding: .day, value: 154, to: .now) ?? .now
                    : Calendar.current.date(byAdding: .day, value: -126, to: .now) ?? .now
            }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("稍后") { dismiss() }
                }
            }
        }
        .presentationDetents([.medium])
    }

    private func save() async {
        guard session.familyID != nil else {
            errorMessage = "家庭信息还没有准备好，请稍后重试。"
            return
        }
        isSubmitting = true
        errorMessage = nil
        defer { isSubmitting = false }

        do {
            let repository = BusinessRepository(environment: session.environment)
            let pregnancyID = try await repository.createPregnancy(
                dueDate: dateMode.dueDate(from: selectedDate)
            )
            session.setPregnancyID(pregnancyID)
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

enum PregnancyDateMode: String, CaseIterable, Hashable {
    case dueDate
    case lastMenstrualPeriod

    var title: String {
        switch self {
        case .dueDate: return "预产期"
        case .lastMenstrualPeriod: return "末次月经"
        }
    }

    var dateTitle: String { title }

    var dateRange: ClosedRange<Date> {
        let calendar = PregnancyDateCalculator.calendar
        switch self {
        case .dueDate:
            return Date()...calendar.date(byAdding: .year, value: 1, to: .now)!
        case .lastMenstrualPeriod:
            return calendar.date(byAdding: .year, value: -1, to: .now)!...Date()
        }
    }

    func dueDate(from selectedDate: Date) -> Date {
        switch self {
        case .dueDate: return selectedDate
        case .lastMenstrualPeriod:
            return PregnancyDateCalculator.dueDate(fromLastMenstrualPeriod: selectedDate)
        }
    }

    func calculatedSummary(for selectedDate: Date) -> String {
        let calculatedDate: Date
        switch self {
        case .dueDate:
            calculatedDate = PregnancyDateCalculator.lastMenstrualPeriod(fromDueDate: selectedDate)
        case .lastMenstrualPeriod:
            calculatedDate = PregnancyDateCalculator.dueDate(fromLastMenstrualPeriod: selectedDate)
        }
        let formatter = DateFormatter()
        formatter.calendar = PregnancyDateCalculator.calendar
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.dateFormat = "yyyy年M月d日"
        return "对应的\(self == .dueDate ? "末次月经" : "预产期")：\(formatter.string(from: calculatedDate))"
    }
}

enum PregnancyDateCalculator {
    static let standardGestationDays = 280

    static var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = .current
        return calendar
    }

    static func dueDate(fromLastMenstrualPeriod date: Date) -> Date {
        calendar.date(byAdding: .day, value: standardGestationDays, to: date)!
    }

    static func lastMenstrualPeriod(fromDueDate date: Date) -> Date {
        calendar.date(byAdding: .day, value: -standardGestationDays, to: date)!
    }
}

struct TaskRow: View {
    let task: TaskItem

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: task.status == .completed ? "checkmark.circle.fill" : "circle")
                .foregroundStyle(task.status == .completed ? Color.green : Color.aimAccent)
            VStack(alignment: .leading, spacing: 4) {
                Text(task.title)
                    .font(.body.weight(.medium))
                if let dueAt = task.dueAt {
                    Text(dueAt, style: .date)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }
}

private struct PriorityTaskRow: View {
    let task: TaskItem

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Label("优先事项", systemImage: "sparkles")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Color.aimAccent)
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.tertiary)
            }
            Text(task.title)
                .font(.title3.weight(.semibold))
            if let detail = task.detail {
                Text(detail)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
        .aimWarmCard()
    }
}
