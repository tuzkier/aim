import SwiftUI

struct ReminderSettingsView: View {
    @Environment(ReminderCoordinator.self) private var reminders
    @State private var draft = ReminderPreferences()
    @State private var saving = false
    @State private var status: String?
    @State private var initialized = false
    @State private var testStatus: String?

    var body: some View {
        Form {
            Section {
                Toggle("开启本地提醒", isOn: $draft.enabled).accessibilityIdentifier("reminder-enabled")
                Text(permissionText).font(.footnote).foregroundStyle(Color.aimTextSecondary)
                if let status { Text(status).font(.footnote).accessibilityIdentifier("reminder-status") }
                if let error = reminders.errorMessage { Text(error).font(.footnote).foregroundStyle(Color.aimDanger) }
                if reminders.authorization == .denied {
                    Button("打开系统通知设置") {
                        if let url = URL(string: UIApplication.openNotificationSettingsURLString) {
                            UIApplication.shared.open(url)
                        }
                    }
                }
            } footer: { Text("开启后请保存。通知不展示你的具体健康记录或待办内容。") }
            Section("提醒什么") {
                Toggle("每日胎动", isOn: $draft.fetalMovement).accessibilityIdentifier("reminder-fetal")
                DatePicker("胎动提醒时间", selection: minuteBinding(\.fetalMinute), displayedComponents: .hourAndMinute)
                    .disabled(!draft.fetalMovement)
                Text("孕 28–42 周提醒；当天已记录或正在计数时不再提醒。")
                    .font(.footnote).foregroundStyle(Color.aimTextSecondary)
                Toggle("产检与待办到期", isOn: $draft.tasks).accessibilityIdentifier("reminder-tasks")
                Text("通常提前 1 小时；不足 1 小时的事项到期时提醒。分配给家人的事项不重复提醒你。")
                    .font(.footnote).foregroundStyle(Color.aimTextSecondary)
                Toggle("每周简报", isOn: $draft.weekly).accessibilityIdentifier("reminder-weekly")
                Text("每周一 09:00，打开后查看最新的本周安排和记录。")
                    .font(.footnote).foregroundStyle(Color.aimTextSecondary)
            }
            .disabled(!draft.enabled)
            Section("免打扰") {
                Toggle("开启免打扰", isOn: $draft.quiet).accessibilityIdentifier("reminder-quiet")
                DatePicker("开始", selection: minuteBinding(\.quietStart), displayedComponents: .hourAndMinute)
                    .disabled(!draft.quiet)
                DatePicker("结束", selection: minuteBinding(\.quietEnd), displayedComponents: .hourAndMinute)
                    .disabled(!draft.quiet)
                if !draft.isValid { Text("起止时间不能相同").foregroundStyle(Color.aimDanger) }
                Text("日常提醒会避开这段时间。待办提醒提前到免打扰开始前，不推迟到截止时间之后。")
                    .font(.footnote).foregroundStyle(Color.aimTextSecondary)
            }
            .disabled(!draft.enabled)
            Section {
                Button("发送测试提醒（10 秒后）") {
                    Task { testStatus = await reminders.sendTest() ? "测试提醒将在 10 秒后送达，可切到后台等待。" : nil }
                }
                .accessibilityIdentifier("reminder-test")
                .disabled(!reminders.preferences.enabled || reminders.authorization != .allowed || saving)
                if let testStatus { Text(testStatus).font(.footnote).accessibilityIdentifier("reminder-test-status") }
                Text("已安排 \(reminders.scheduled.count) 条最近提醒")
                    .font(.footnote).accessibilityIdentifier("reminder-scheduled-count")
                Button("重新同步提醒") { Task { await reminders.refresh() } }
                    .disabled(!reminders.preferences.enabled || reminders.isUpdating)
            } footer: {
                Text("时间按北京时间。打开 App 时按最新数据更新未来 28 天的提醒；长时间不打开不会自动续排。家人在其他设备上的改动会在下次同步后更新。")
            }
        }
        .environment(\.timeZone, ReminderPlanner.calendar.timeZone)
        .environment(\.locale, Locale(identifier: "zh_CN"))
        .navigationTitle("提醒设置")
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("保存") {
                    Task {
                        saving = true
                        status = nil
                        if await reminders.save(draft) { status = "提醒设置已保存" }
                        saving = false
                    }
                }
                .disabled(!draft.isValid || saving)
                .accessibilityIdentifier("reminder-save")
            }
        }
        .onAppear {
            if !initialized { draft = reminders.preferences; initialized = true }
            Task { await reminders.refreshPermission() }
        }
    }

    private var permissionText: String {
        switch reminders.authorization {
        case .notDetermined: "保存开启设置时，会询问是否允许通知。"
        case .allowed: "系统已允许通知。"
        case .denied: "系统通知已关闭，需要在系统设置中允许。"
        }
    }
    private func minuteBinding(_ path: WritableKeyPath<ReminderPreferences, Int>) -> Binding<Date> {
        Binding(get: { ReminderPlanner.atMinute(draft[keyPath: path], on: .now) }, set: { date in
            let parts = ReminderPlanner.calendar.dateComponents([.hour, .minute], from: date)
            draft[keyPath: path] = (parts.hour ?? 0) * 60 + (parts.minute ?? 0)
        })
    }
}

struct WeeklyBriefView: View {
    let repository: BusinessRepositoryProtocol
    @State private var tasks: [TaskItem] = []
    @State private var records: [RecordItem] = []
    @State private var pregnancy: PregnancySummary?
    @State private var loading = true
    @State private var error: String?

    private var week: DateInterval { ReminderPlanner.calendar.dateInterval(of: .weekOfYear, for: .now)! }
    private var weekTasks: [TaskItem] {
        tasks.filter { ($0.dueAt ?? $0.scheduledFor).map { $0 >= week.start && $0 < week.end } == true }
            .sorted { ($0.dueAt ?? $0.scheduledFor ?? .distantFuture) < ($1.dueAt ?? $1.scheduledFor ?? .distantFuture) }
    }
    var body: some View {
        List {
            if loading { ProgressView("正在读取本周安排") }
            if let error { Section { Text(error); Button("重试") { Task { await load() } } } }
            if !loading && error == nil {
                Section {
                    if let pregnancy { Text("孕 \(pregnancy.weeks) 周 +\(pregnancy.days) 天") }
                    Text("这周安排了 \(weekTasks.count) 项待办，记录了 \(records.filter { $0.occurredAt >= week.start && $0.occurredAt < week.end }.count) 次。")
                        .accessibilityIdentifier("weekly-brief-summary")
                } footer: { Text("这是当前安排与记录的汇总，打开时读取最新数据。") }
                Section("这周的安排") {
                    if weekTasks.isEmpty { Text("这周没有已排期的待办") }
                    ForEach(weekTasks) { task in
                        NavigationLink { TaskDetailView(task: task, repository: repository) } label: {
                            VStack(alignment: .leading) {
                                Text(task.title)
                                Text(task.status == .completed ? "已完成" : "待处理")
                                    .font(.caption).foregroundStyle(Color.aimTextSecondary)
                            }
                        }
                    }
                }
                Section("这周记下的") {
                    let recent = records.filter { $0.occurredAt >= week.start && $0.occurredAt < week.end }
                    if recent.isEmpty { Text("这周还没有记录") }
                    ForEach(recent.prefix(10)) { record in
                        VStack(alignment: .leading) {
                            Text(record.type.displayName)
                            Text(record.displayTitle).font(.footnote).foregroundStyle(Color.aimTextSecondary)
                        }
                    }
                }
            }
        }
        .navigationTitle("本周简报")
        .accessibilityIdentifier("weekly-brief")
        .task { await load() }
        .refreshable { await load() }
    }
    private func load() async {
        loading = true; error = nil
        defer { loading = false }
        do {
            async let plan = repository.fetchPlan()
            async let record = repository.fetchRecords(type: nil)
            async let pregnancy = repository.fetchPregnancy()
            let data = try await (plan, record, pregnancy)
            tasks = data.0.tasks; records = data.1.records; self.pregnancy = data.2
        } catch { self.error = "本周简报暂时无法读取，请重试" }
    }
}
