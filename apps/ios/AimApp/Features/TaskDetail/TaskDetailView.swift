import SwiftUI

struct TaskDetailView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var store: TaskDetailStore
    @State private var showingDeleteConfirmation = false
    @State private var dueDate: Date
    @State private var showingDelay = false
    @State private var recordStore = RecordStore()
    @State private var recordPromptTask: TaskItem?
    @State private var toast: AimToastMessage?

    init(task: TaskItem, repository: BusinessRepositoryProtocol?) {
        _store = State(initialValue: TaskDetailStore(task: task, repository: repository))
        _dueDate = State(initialValue: task.dueAt ?? .now.addingTimeInterval(86_400))
        let records = RecordStore()
        records.repository = repository
        _recordStore = State(initialValue: records)
    }

    var body: some View {
        Form {
            Section {
                Label(store.task.status == .cancelled ? "不再适用" : store.task.status == .completed ? "已完成" : "待处理", systemImage: store.task.status == .completed ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(store.task.status == .completed ? Color.green : Color.aimAccent)
                Text(store.task.title)
                    .font(.title3.weight(.semibold))
                if let detail = store.task.detail {
                    Text(detail).foregroundStyle(.secondary)
                }
            }

            Section("安排") {
                if let dueAt = store.task.dueAt {
                    LabeledContent("截止", value: dueAt.formatted(date: .abbreviated, time: .omitted))
                }
                if let scheduledFor = store.task.scheduledFor {
                    LabeledContent("已安排", value: scheduledFor.formatted(date: .abbreviated, time: .shortened))
                }
                Button("延期") { showingDelay = true }
                    .disabled(!store.task.isOpen)
            }

            if let errorMessage = store.errorMessage {
                Section { Text(errorMessage).foregroundStyle(Color.aimDanger) }
            }

            Section {
                Button {
                    Task {
                        let task = store.task
                        if await store.complete() {
                            toast = AimToastMessage(
                                text: "已完成「\(task.title)」",
                                undoTitle: "记一下",
                                accessibilityIdentifier: "complete-task-record-prompt"
                            ) {
                                recordPromptTask = task
                            }
                        }
                    }
                } label: {
                    // 不用 Label：图标和文字会被当成一个整体居中，文字因此被顶到
                    // 右边约 12pt。而这个 checkmark 在完成/未完成两态是同一个，
                    // 本来就没在表达状态，删掉即可，文字才真正落在中线上。
                    Text(store.task.status == .cancelled ? "不再适用" : store.task.status == .completed ? "已完成" : "标记完成")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .disabled(!store.task.isOpen || store.isSaving)
            }

            // 加错了、重复了、不需要了：删掉，而不是标成完成——完成代表真的做了。
            Section {
                Button("删除待办", role: .destructive) { showingDeleteConfirmation = true }
                    .disabled(store.isSaving)
                    .accessibilityIdentifier("task-delete")
            }
        }
        .navigationTitle("事项详情")
        .confirmationDialog("删除这条待办？", isPresented: $showingDeleteConfirmation, titleVisibility: .visible) {
            Button("删除", role: .destructive) {
                Task {
                    if await store.delete() {
                        // 首页、时间线各自持有待办列表，由根视图统一刷新。
                        NotificationCenter.default.post(
                            name: .aimDataChanged, object: nil, userInfo: ["kinds": ["task"]]
                        )
                        dismiss()
                    }
                }
            }
        } message: { Text("删除后无法恢复。") }
#if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
#endif
        .sheet(isPresented: $showingDelay) {
            TaskDelaySheet(task: store.task, repository: store.repository) { updated in
                store.task = updated
            }
        }
        .sheet(item: $recordPromptTask) { task in
            RecordComposerView(
                store: recordStore,
                suggestedType: TaskRecordSuggestion.recordType(forTaskTitle: task.title),
                suggestedText: task.title
            ) {
                recordPromptTask = nil
            }
        }
        .aimToast($toast)
    }
}

struct TaskDelaySheet: View {
    @Environment(\.dismiss) private var dismiss
    @State private var store: TaskDetailStore
    @State private var dueDate: Date
    @State private var errorMessage: String?
    let onSaved: (TaskItem) -> Void

    init(task: TaskItem, repository: BusinessRepositoryProtocol?, onSaved: @escaping (TaskItem) -> Void) {
        _store = State(initialValue: TaskDetailStore(task: task, repository: repository))
        _dueDate = State(initialValue: task.dueAt ?? .now.addingTimeInterval(86_400))
        self.onSaved = onSaved
    }

    var body: some View {
        NavigationStack {
            Form {
                DatePicker("新的截止日期", selection: $dueDate, displayedComponents: [.date, .hourAndMinute])
                if let errorMessage {
                    Text(errorMessage).foregroundStyle(Color.aimDanger)
                }
            }
            .navigationTitle("延期事项")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { dismiss() }.disabled(store.isSaving)
                }
                ToolbarItem(placement: .confirmationAction) {
                    if store.isSaving {
                        ProgressView()
                    } else {
                        Button("保存") {
                            Task {
                                errorMessage = nil
                                if await store.delay(until: dueDate) {
                                    onSaved(store.task)
                                    dismiss()
                                } else {
                                    errorMessage = store.errorMessage ?? "没能保存新的日期，稍后再试。"
                                }
                            }
                        }
                    }
                }
            }
        }
        .presentationDetents([.medium])
    }
}
