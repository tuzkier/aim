import SwiftUI

/// 改预产期时的三种填法。
enum DueDateInputMode: String, CaseIterable, Hashable {
    case dueDate
    case lastMenstrualPeriod
    case currentWeek

    var title: String {
        switch self {
        case .dueDate: "预产期"
        case .lastMenstrualPeriod: "末次月经"
        case .currentWeek: "当前孕周"
        }
    }
}

/// 改预产期面板的草稿：三种填法一律按 280 天换算成预产期。
///
/// 与建档页的 `PregnancySetupModel` 分开：建档要求「必须主动选过日期」，
/// 而这里一打开就有当前预产期作为起点。
struct DueDateDraft: Equatable {
    /// 能保存的最大孕周：42 周 0 天，与服务端一致。
    static let maxGestationDays = 42 * 7

    var mode: DueDateInputMode = .dueDate
    /// 预产期或末次月经模式下选的日期。
    var date: Date
    var weeks = 0
    var days = 0
    let today: Date

    private static var calendar: Calendar { PregnancyDateCalculator.calendar }

    init(currentDueDate: Date?, today: Date = .now) {
        let start = Self.calendar.startOfDay(for: today)
        self.today = start
        // 还没有孕期时停在「今天 + 280 天」——那是 0 周，用户一眼就知道要改。
        self.date = Self.calendar.startOfDay(
            for: currentDueDate ?? PregnancyDateCalculator.dueDate(fromLastMenstrualPeriod: start))
    }

    var dueDate: Date {
        switch mode {
        case .dueDate:
            return date
        case .lastMenstrualPeriod:
            return PregnancyDateCalculator.dueDate(fromLastMenstrualPeriod: date)
        case .currentWeek:
            let elapsed = weeks * 7 + days
            return Self.calendar.date(
                byAdding: .day, value: PregnancyDateCalculator.standardGestationDays - elapsed, to: today)!
        }
    }

    /// 今天距末次月经的天数；可能为负（还没到孕期）。
    private var elapsedDays: Int {
        let lastPeriod = PregnancyDateCalculator.lastMenstrualPeriod(fromDueDate: dueDate)
        return Self.calendar.dateComponents([.day], from: lastPeriod, to: today).day ?? 0
    }

    /// 换算出的今天的孕周；超出范围时为 nil。
    var gestation: (weeks: Int, days: Int)? {
        guard validationMessage == nil else { return nil }
        return (elapsedDays / 7, elapsedDays % 7)
    }

    var validationMessage: String? {
        if elapsedDays < 0 { return "这个日期算出来还没到孕期，请检查一下" }
        if elapsedDays > Self.maxGestationDays { return "这个日期算出来已经超过 42 周了，请检查一下" }
        return nil
    }

    /// 换模式时保持同一个预产期，只是换一种说法。
    mutating func switchMode(to newMode: DueDateInputMode) {
        let current = dueDate
        let elapsed = max(0, min(elapsedDays, Self.maxGestationDays))
        mode = newMode
        switch newMode {
        case .dueDate:
            date = current
        case .lastMenstrualPeriod:
            date = PregnancyDateCalculator.lastMenstrualPeriod(fromDueDate: current)
        case .currentWeek:
            weeks = elapsed / 7
            days = elapsed % 7
        }
    }
}

/// 改预产期面板。三种填法任选，实时显示换算结果；超出范围不能保存。
struct DueDateEditorSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Bindable var store: FamilyStore
    let currentDueDate: Date?
    @State private var draft: DueDateDraft
    @State private var isSubmitting = false
    @State private var errorMessage: String?

    init(store: FamilyStore, currentDueDate: Date?) {
        self.store = store
        self.currentDueDate = currentDueDate
        _draft = State(initialValue: DueDateDraft(currentDueDate: currentDueDate))
    }

    private var unchanged: Bool {
        guard let currentDueDate else { return false }
        return PregnancyDateCalculator.calendar.isDate(currentDueDate, inSameDayAs: draft.dueDate)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Picker("填写方式", selection: Binding(
                        get: { draft.mode },
                        set: { draft.switchMode(to: $0) }
                    )) {
                        ForEach(DueDateInputMode.allCases, id: \.self) { Text($0.title).tag($0) }
                    }
                    .pickerStyle(.segmented)
                    .accessibilityIdentifier("due-date-mode")

                    switch draft.mode {
                    case .dueDate, .lastMenstrualPeriod:
                        DatePicker(draft.mode.title, selection: $draft.date, displayedComponents: .date)
                            .datePickerStyle(.wheel)
                            .labelsHidden()
                            .environment(\.locale, Locale(identifier: "zh_CN"))
                            .frame(maxWidth: .infinity)
                    case .currentWeek:
                        HStack(spacing: 0) {
                            Picker("周", selection: $draft.weeks) {
                                ForEach(0...42, id: \.self) { Text("\($0) 周").tag($0) }
                            }
                            Picker("天", selection: $draft.days) {
                                ForEach(0...6, id: \.self) { Text("\($0) 天").tag($0) }
                            }
                        }
                        .pickerStyle(.wheel)
                        .frame(height: 160)
                    }
                } footer: {
                    Text("三种填法都按孕 40 周（280 天）换算，保存的是预产期。")
                }

                Section {
                    if let message = draft.validationMessage {
                        Text(message).foregroundStyle(Color.aimDanger)
                    } else if let gestation = draft.gestation {
                        Text("对应预产期 \(draft.dueDate.aimLongDate)，现在孕 \(gestation.weeks) 周 +\(gestation.days) 天")
                            .accessibilityIdentifier("due-date-summary")
                    }
                    if let errorMessage {
                        Text(errorMessage).foregroundStyle(Color.aimDanger)
                    }
                }
            }
            .navigationTitle("修改预产期")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { dismiss() }.disabled(isSubmitting)
                }
                ToolbarItem(placement: .confirmationAction) {
                    if isSubmitting {
                        ProgressView()
                    } else {
                        Button("保存") { Task { await save() } }
                            .disabled(draft.validationMessage != nil || unchanged)
                            .accessibilityIdentifier("due-date-save")
                    }
                }
            }
        }
        .presentationDetents([.large])
        .interactiveDismissDisabled(isSubmitting)
    }

    private func save() async {
        isSubmitting = true
        errorMessage = nil
        defer { isSubmitting = false }
        if await store.updateDueDate(draft.dueDate) {
            // 首页孕周、时间轴跟着预产期变，通知它们重新加载。
            NotificationCenter.default.post(name: .aimDataChanged, object: nil, userInfo: ["kinds": ["task"]])
            dismiss()
        } else {
            errorMessage = store.errorMessage ?? "没改成，稍后再试。"
        }
    }
}
