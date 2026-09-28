import SwiftUI

struct RecordDetailView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(AppSessionStore.self) private var session
    let record: RecordItem
    @Bindable var store: RecordStore
    let planStore: PlanStore
    let agentStore: AgentStore
    @State private var showingEditor = false
    @State private var showingDeleteConfirmation = false
    @State private var showingTaskSheet = false
    @State private var showingAgent = false

    private var currentRecord: RecordItem {
        store.snapshot?.records.first(where: { $0.id == record.id }) ?? record
    }

    private var canEdit: Bool { session.accountID == currentRecord.authorAccountID }

    var body: some View {
        List {
            Section {
                VStack(alignment: .leading, spacing: 12) {
                    Label(currentRecord.type.displayName, systemImage: currentRecord.type.symbolName)
                        .foregroundStyle(Color.aimAccent)
                    Text(currentRecord.displayTitle).font(.title2.weight(.semibold))
                    Text(currentRecord.occurredAt, format: .dateTime.year().month().day().hour().minute())
                        .font(.subheadline).foregroundStyle(.secondary)
                }
                .aimCard()
            }
            .listRowBackground(Color.clear)

            contentSection
            Section("记录信息") {
                LabeledContent("记录人", value: canEdit ? "我" : "家庭成员")
                Label(currentRecord.visibility.displayName, systemImage: currentRecord.visibility == .family ? "person.2" : "lock")
            }
            Section {
                Button("转为待办") { showingTaskSheet = true }
                Button("让 Agent 分析当前记录") {
                    agentStore.prepareAnalysis(
                        analysisPrompt(for: currentRecord),
                        context: AgentContext(
                            title: "记录",
                            summary: "\(currentRecord.type.displayName)：\(currentRecord.displayTitle)"
                        )
                    )
                    showingAgent = true
                }
                if canEdit {
                    Button("编辑记录") { showingEditor = true }
                    Button("删除记录", role: .destructive) { showingDeleteConfirmation = true }
                }
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle("记录详情")
        .confirmationDialog("删除这条记录？", isPresented: $showingDeleteConfirmation, titleVisibility: .visible) {
            Button("删除", role: .destructive) { Task { await delete() } }
        } message: { Text("删除后无法恢复。") }
        .sheet(isPresented: $showingEditor) {
            RecordComposerView(store: store, record: currentRecord) { showingEditor = false }
        }
        .sheet(isPresented: $showingTaskSheet) {
            RecordTaskSheet(record: currentRecord, store: store, planStore: planStore) { showingTaskSheet = false }
        }
        .fullScreenCover(isPresented: $showingAgent) {
            AgentView(store: agentStore) { showingAgent = false }
        }
    }

    @ViewBuilder
    private var contentSection: some View {
        switch currentRecord.structuredData {
        case let .symptom(data):
            Section("身体感受") {
                LabeledContent("症状", value: data.symptoms.joined(separator: "、"))
                LabeledContent("程度", value: "\(data.severity) / 5")
                if let note = data.note, !note.isEmpty { Text(note) }
            }
        case let .checkup(data):
            Section("产检信息") {
                LabeledContent("医院", value: data.hospital)
                LabeledContent("检查项目", value: data.examItems)
                LabeledContent("检查结果", value: data.result)
                LabeledContent("医生建议", value: data.doctorAdvice)
            }
        case .note:
            Section("内容") { Text(currentRecord.content ?? "没有补充内容") }
        case let .question(data):
            Section("想问医生") {
                Text(currentRecord.content ?? "")
                if let answer = data.answer, !answer.isEmpty {
                    LabeledContent("医生的回答", value: answer)
                } else {
                    Text(data.answered ? "已解答" : "还没问")
                        .foregroundStyle(.secondary)
                }
            }
        case let .checklist(data):
            Section("清单") {
                LabeledContent("条目", value: record.displayTitle)
                LabeledContent("状态", value: data.done ? "已完成" : "待完成")
            }
        case let .knowledge(data):
            Section("资料") {
                if let body = data.body { Text(body) }
                if let reason = data.reason { Text(reason) }
                ForEach(data.steps ?? [], id: \.self) { Text($0) }
            }
        case .unknown:
            Section { Text("这类记录暂不支持完整展示。") }
        }
    }

    private func analysisPrompt(for record: RecordItem) -> String {
        "请帮我理解这条孕期记录，并告诉我接下来需要留意什么：\n\n类型：\(record.type.displayName)\n发生时间：\(record.occurredAt.formatted(date: .abbreviated, time: .shortened))\n内容：\(record.displayTitle)\n\(record.displaySummary)"
    }

    private func delete() async {
        if await store.delete(recordID: record.id) { dismiss() }
    }
}

private struct RecordTaskSheet: View {
    @Environment(\.dismiss) private var dismiss
    let record: RecordItem
    @Bindable var store: RecordStore
    let planStore: PlanStore
    let onCreated: () -> Void
    @State private var title: String
    @State private var description: String = ""
    @State private var hasDueDate = false
    @State private var dueAt = Date.now

    init(record: RecordItem, store: RecordStore, planStore: PlanStore, onCreated: @escaping () -> Void) {
        self.record = record
        self.store = store
        self.planStore = planStore
        self.onCreated = onCreated
        _title = State(initialValue: "跟进：\(record.displayTitle)")
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("待办内容") {
                    TextField("待办标题", text: $title)
                    TextField("补充说明（可选）", text: $description, axis: .vertical)
                }
                Section {
                    Toggle("设置截止时间", isOn: $hasDueDate)
                    if hasDueDate { DatePicker("截止时间", selection: $dueAt, displayedComponents: [.date, .hourAndMinute]) }
                }
                if let error = store.errorMessage { Section { Text(error).foregroundStyle(.red) } }
            }
            .navigationTitle("转为待办")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("取消") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("确认创建") { Task { await create() } }
                        .disabled(title.trimmed.isEmpty || store.isSaving)
                }
            }
        }
    }

    private func create() async {
        if await store.createTask(from: record, title: title.trimmed, description: description.trimmed.nilIfEmpty, dueAt: hasDueDate ? dueAt : nil) != nil {
            await planStore.load()
            onCreated()
            dismiss()
        }
    }
}
