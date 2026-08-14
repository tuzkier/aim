import SwiftUI

struct TodayView: View {
    @Bindable var store: TodayStore

    var body: some View {
        NavigationStack {
            Group {
                if case .failed(let message) = store.state, store.snapshot == nil {
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
        }
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
                    .foregroundStyle(.aimAccent)
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
