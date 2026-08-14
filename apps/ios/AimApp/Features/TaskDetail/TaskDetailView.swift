import SwiftUI

struct TaskDetailView: View {
    @State private var store: TaskDetailStore
    @State private var dueDate: Date
    @State private var showingDelay = false

    init(task: TaskItem, repository: BusinessRepositoryProtocol?) {
        _store = State(initialValue: TaskDetailStore(task: task, repository: repository))
        _dueDate = State(initialValue: task.dueAt ?? .now.addingTimeInterval(86_400))
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
                Section { Text(errorMessage).foregroundStyle(.red) }
            }

            Section {
                Button {
                    Task {
                        _ = await store.complete()
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
            NavigationStack {
                Form { DatePicker("新的截止日期", selection: $dueDate, displayedComponents: [.date, .hourAndMinute]) }
                    .navigationTitle("延期事项")
                    .toolbar {
                        ToolbarItem(placement: .cancellationAction) { Button("取消") { showingDelay = false } }
                        ToolbarItem(placement: .confirmationAction) {
                            Button("保存") {
                                Task {
                                    if await store.delay(until: dueDate) { showingDelay = false }
                                }
                            }
                        }
                    }
            }
            .presentationDetents([.medium])
        }
    }
}
