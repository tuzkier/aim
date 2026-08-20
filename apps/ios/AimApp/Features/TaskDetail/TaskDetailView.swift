import SwiftUI

struct TaskDetailView: View {
    @State private var store: TaskDetailStore
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
                Label(store.task.status == .completed ? "已完成" : "待处理", systemImage: store.task.status == .completed ? "checkmark.circle.fill" : "circle")
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
                    .disabled(store.task.status == .completed)
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
                    Label(store.task.status == .completed ? "已完成" : "标记完成", systemImage: "checkmark")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .disabled(store.task.status == .completed || store.isSaving)
            }
        }
        .navigationTitle("事项详情")
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
