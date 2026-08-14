import SwiftUI

struct PlanView: View {
    @Bindable var store: PlanStore

    var body: some View {
        NavigationStack {
            Group {
                if let snapshot = store.snapshot {
                    List {
                        Section {
                            VStack(alignment: .leading, spacing: 8) {
                                Label("这是一份会跟着孕期变化的计划", systemImage: "calendar.badge.clock")
                                    .font(.headline)
                                Text("Agent 会根据已确认的事实提出调整，真正写入前会先让你确认。")
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)
                            }
                            .aimWarmCard()
                        }
                        .listRowBackground(Color.clear)
                        .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 10, trailing: 16))

                        Section("未完成 · \(snapshot.tasks.filter(\.isOpen).count)") {
                            ForEach(snapshot.tasks.filter(\.isOpen)) { task in
                                NavigationLink {
                                    TaskDetailView(task: task, repository: store.repository)
                                } label: {
                                    TaskRow(task: task)
                                }
                            }
                        }

                        Section("已完成") {
                            ForEach(snapshot.tasks.filter { !$0.isOpen }) { task in
                                TaskRow(task: task)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                    .listStyle(.insetGrouped)
                } else if store.isLoading {
                    ProgressView("正在加载计划")
                } else {
                    ContentUnavailableView("还没有计划", systemImage: "calendar.badge.exclamationmark", description: Text(store.errorMessage ?? "生成第一份孕期计划后，这里会持续更新。"))
                }
            }
            .navigationTitle("计划")
            .background(Color.aimWarmBackground)
            .refreshable { await store.load() }
            .task {
                if store.snapshot == nil { await store.load() }
            }
        }
    }
}
