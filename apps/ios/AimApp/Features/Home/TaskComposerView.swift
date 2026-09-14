import SwiftUI

struct TaskDraft: Equatable {
    let title: String
    let detail: String?
    let dueAt: Date?
    let assignedMemberID: UUID?
}

/// `+` 菜单里的「新建待办」。快速添加只填标题；要定时间、要指派给谁，来这里。
struct TaskComposerView: View {
    @Environment(\.dismiss) private var dismiss
    let members: [FamilyMember]
    /// 返回 nil 表示成功；否则是要在表单里显示的错误文案。
    let save: (TaskDraft) async -> String?

    @State private var title = ""
    @State private var detail = ""
    @State private var hasDueDate = true
    @State private var dueAt: Date
    @State private var assignedMemberID: UUID?
    @State private var isSaving = false
    @State private var errorMessage: String?

    init(members: [FamilyMember], now: Date = .now, save: @escaping (TaskDraft) async -> String?) {
        self.members = members
        self.save = save
        _dueAt = State(initialValue: Self.defaultDueDate(now: now))
    }

    /// 默认今天 20:00；已经过了 20:00 就明天 20:00——给的是一个还来得及做的时刻。
    static func defaultDueDate(now: Date, calendar: Calendar = PregnancyDateCalculator.calendar) -> Date {
        let todayEight = calendar.date(bySettingHour: 20, minute: 0, second: 0, of: calendar.startOfDay(for: now)) ?? now
        if now < todayEight { return todayEight }
        return calendar.date(byAdding: .day, value: 1, to: todayEight) ?? todayEight
    }

    private var trimmedTitle: String { title.trimmingCharacters(in: .whitespacesAndNewlines) }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("要做什么", text: $title)
                        .accessibilityIdentifier("task-composer-title")
                    TextField("补充说明（可选）", text: $detail, axis: .vertical)
                        .lineLimit(1...4)
                }

                Section("安排") {
                    Toggle("设置截止时间", isOn: $hasDueDate)
                    if hasDueDate {
                        DatePicker("截止", selection: $dueAt, displayedComponents: [.date, .hourAndMinute])
                    }
                    Picker("负责人", selection: $assignedMemberID) {
                        Text("未指派").tag(UUID?.none)
                        ForEach(members) { member in
                            Text(member.displayName).tag(UUID?.some(member.accountID))
                        }
                    }
                }

                if let errorMessage {
                    Section { Text(errorMessage).foregroundStyle(Color.aimDanger) }
                }
            }
            .navigationTitle("新建待办")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { dismiss() }.disabled(isSaving)
                }
                ToolbarItem(placement: .confirmationAction) {
                    if isSaving {
                        ProgressView()
                    } else {
                        Button("保存") { Task { await submit() } }
                            .disabled(trimmedTitle.isEmpty)
                            .accessibilityIdentifier("task-composer-save")
                    }
                }
            }
        }
        .presentationDetents([.medium, .large])
    }

    private func submit() async {
        isSaving = true
        errorMessage = nil
        defer { isSaving = false }
        let trimmedDetail = detail.trimmingCharacters(in: .whitespacesAndNewlines)
        let draft = TaskDraft(
            title: trimmedTitle,
            detail: trimmedDetail.isEmpty ? nil : trimmedDetail,
            dueAt: hasDueDate ? dueAt : nil,
            assignedMemberID: assignedMemberID)
        if let failure = await save(draft) {
            errorMessage = failure
        } else {
            dismiss()
        }
    }
}
