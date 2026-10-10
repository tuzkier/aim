import SwiftUI

enum MemoryKind: String, CaseIterable, Codable, Sendable {
    case allergy, history, medication, care, preference, other, unknown

    var title: String {
        switch self {
        case .allergy: "过敏"
        case .history: "病史与孕产史"
        case .medication: "在用药物"
        case .care: "医院与产检安排"
        case .preference: "偏好"
        case .other: "其他"
        case .unknown: "待确认类别"
        }
    }

    static var supported: [MemoryKind] { allCases.filter { $0 != .unknown } }
}

struct MemoryRecordData: Codable, Equatable, Sendable {
    let kind: MemoryKind
    let text: String
}

struct MemoryForm: Equatable {
    var kind: MemoryKind = .other
    var text = ""
    var visibility: RecordVisibility = .family

    init(record: RecordItem? = nil) {
        if let record {
            visibility = record.visibility
            if case let .memory(data) = record.structuredData { kind = data.kind; text = data.text }
        }
    }

    // 与 Python 字符计数一致，不把多个 Unicode 字符组成的表情算成一个字。
    var count: Int { text.trimmed.unicodeScalars.count }
    var canSave: Bool { kind != .unknown && (1...80).contains(count) }

    func draft(record: RecordItem? = nil) -> RecordDraft {
        RecordDraft(type: .memory, occurredAt: record?.occurredAt ?? .now, visibility: visibility,
                    title: String(text.trimmed.prefix(40)), content: nil,
                    structuredData: .memory(MemoryRecordData(kind: kind, text: text.trimmed)))
    }
}

private struct MemoryEditorTarget: Identifiable {
    let id = UUID()
    let record: RecordItem?
}

struct MemoryView: View {
    @Bindable var store: RecordStore
    let agentStore: AgentStore
    @State private var editing: MemoryEditorTarget?

    private var memories: [RecordItem] {
        (store.snapshot?.records ?? []).filter { $0.type == .memory }
            .sorted { $0.updatedAt > $1.updatedAt }
    }

    var body: some View {
        List {
            Section {
                Text("AIM 会在每次对话开始时读到这些，帮你回答得更贴切。你可以随时修改或删除。")
                    .font(.footnote).foregroundStyle(Color.aimTextSecondary)
                Text("当前可见 \(memories.count) 条 · 每个家庭最多 50 条")
                    .font(.caption).foregroundStyle(Color.aimTextTertiary)
            }
            if store.isLoading && store.snapshot == nil { ProgressView("正在读取记忆") }
            if memories.isEmpty && !store.isLoading {
                Section {
                    Text("还没有记忆").accessibilityIdentifier("memory-empty")
                    Text("可以在这里添加，也可以直接告诉 AIM。")
                        .font(.footnote).foregroundStyle(Color.aimTextSecondary)
                }
            }
            ForEach(MemoryKind.allCases, id: \.self) { kind in
                let group = memories.filter { record in
                    if case let .memory(data) = record.structuredData { return data.kind == kind }
                    return kind == .unknown
                }
                if !group.isEmpty {
                    Section(kind.title) {
                        ForEach(group) { record in
                            NavigationLink {
                                MemoryDetailView(record: record, store: store, agentStore: agentStore)
                            } label: {
                                VStack(alignment: .leading, spacing: AimMetrics.space4) {
                                    Text(record.displayTitle).foregroundStyle(Color.aimTextPrimary)
                                    Label(record.visibility.displayName,
                                          systemImage: record.visibility == .private ? "lock" : "person.2")
                                        .font(.caption).foregroundStyle(Color.aimTextTertiary)
                                }
                            }
                            .accessibilityIdentifier("memory-row")
                        }
                    }
                }
            }
            if let error = store.errorMessage {
                Section {
                    Text(error).foregroundStyle(Color.aimDanger)
                    Button("重新读取") { Task { await store.load() } }
                }
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle("AIM 记得的事")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button { editing = MemoryEditorTarget(record: nil) } label: {
                    Image(systemName: "plus")
                }
                .accessibilityLabel("添加记忆")
                .accessibilityIdentifier("memory-add")
            }
        }
        .task { await store.load() }
        .refreshable { await store.load() }
        .sheet(item: $editing) { target in
            MemoryComposerView(store: store, record: target.record) { editing = nil }
        }
    }
}

struct MemoryDetailView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(AppSessionStore.self) private var session
    let record: RecordItem
    @Bindable var store: RecordStore
    let agentStore: AgentStore
    @State private var editing = false
    @State private var deleting = false
    @State private var asking = false

    private var current: RecordItem {
        store.snapshot?.records.first(where: { $0.id == record.id }) ?? record
    }

    var body: some View {
        List {
            Section {
                if case let .memory(data) = current.structuredData {
                    Label(data.kind.title, systemImage: "brain").foregroundStyle(Color.aimAccent)
                    Text(data.text).accessibilityIdentifier("memory-detail-text")
                } else { Text("暂时无法读取这条记忆") }
            }
            Section("谁可以看到") {
                Label(current.visibility.displayName,
                      systemImage: current.visibility == .private ? "lock" : "person.2")
            }
            Section {
                if current.isEditable(by: session.accountID) {
                    Button("编辑记忆") { editing = true }.accessibilityIdentifier("memory-edit")
                    Button("删除记忆", role: .destructive) { deleting = true }
                        .accessibilityIdentifier("memory-delete")
                }
                Button("就这条问 AIM") {
                    agentStore.focus(context: AgentContext(
                        title: "记忆：\(current.displayTitle)",
                        summary: "记忆编号：\(current.id.uuidString.lowercased())\n\(current.displayTitle)"))
                    asking = true
                }
                .accessibilityIdentifier("memory-ask-aim")
                if let error = store.errorMessage { Text(error).foregroundStyle(Color.aimDanger) }
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle("记忆详情")
        .confirmationDialog("删除这条记忆？", isPresented: $deleting, titleVisibility: .visible) {
            Button("删除", role: .destructive) {
                Task {
                    if await store.delete(recordID: current.id) { announceMemoryChange(); dismiss() }
                }
            }
        } message: { Text("删除后 AIM 不再读取它。删除不能撤销，以后可以重新记下。") }
        .sheet(isPresented: $editing) {
            MemoryComposerView(store: store, record: current) { editing = false }
        }
        .fullScreenCover(isPresented: $asking) { AgentView(store: agentStore) { asking = false } }
    }
}

struct MemoryComposerView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(AppSessionStore.self) private var session
    @Bindable var store: RecordStore
    let record: RecordItem?
    let onSaved: () -> Void
    @State private var form: MemoryForm

    init(store: RecordStore, record: RecordItem? = nil, onSaved: @escaping () -> Void) {
        self.store = store; self.record = record; self.onSaved = onSaved
        _form = State(initialValue: MemoryForm(record: record))
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("记什么") {
                    Picker("类别", selection: $form.kind) {
                        if form.kind == .unknown { Text("请选择类别").tag(MemoryKind.unknown) }
                        ForEach(MemoryKind.supported, id: \.self) { Text($0.title).tag($0) }
                    }
                    .accessibilityIdentifier("memory-kind")
                    TextField("写一句以后仍有用的事实", text: $form.text, axis: .vertical)
                        .accessibilityIdentifier("memory-text")
                    Text("\(form.count) / 80 字")
                        .font(.caption).foregroundStyle(form.count > 80 ? Color.aimDanger : Color.aimTextTertiary)
                }
                if record?.canChangeVisibility(by: session.accountID) ?? true {
                    Section("谁可以看到") {
                        Picker("可见范围", selection: $form.visibility) {
                            Text("家庭可见").tag(RecordVisibility.family)
                            Text("仅自己可见").tag(RecordVisibility.private)
                        }
                        .pickerStyle(.segmented)
                        .accessibilityIdentifier("memory-visibility")
                    }
                }
                if let error = store.errorMessage { Section { Text(error).foregroundStyle(Color.aimDanger) } }
            }
            .navigationTitle(record == nil ? "添加记忆" : "编辑记忆")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("取消") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("保存") { Task { await save() } }
                        .disabled(!form.canSave || store.isSaving)
                        .accessibilityIdentifier("memory-save")
                }
            }
        }
    }

    private func save() async {
        guard form.canSave else { return }
        let draft = form.draft(record: record)
        let saved: Bool
        if let record { saved = await store.update(recordID: record.id, draft: draft) }
        else { saved = await store.save(draft) }
        if saved { announceMemoryChange(); onSaved(); dismiss() }
    }
}

private func announceMemoryChange() {
    NotificationCenter.default.post(name: .aimDataChanged, object: nil, userInfo: ["kinds": ["record"]])
}
