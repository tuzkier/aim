import SwiftUI

struct RecordsView: View {
    @Environment(AppSessionStore.self) private var session
    @Bindable var store: RecordStore
    let planStore: PlanStore
    @State private var selectedType: RecordType?
    @State private var showingComposer = false
    @State private var showingPregnancySetup = false

    var body: some View {
        NavigationStack {
            Group {
                if session.pregnancyID == nil {
                    pregnancySetupContent
                } else if let snapshot = store.snapshot {
                    recordsList(snapshot.records)
                } else if store.isLoading {
                    ProgressView("正在加载记录")
                } else if let errorMessage = store.errorMessage {
                    ContentUnavailableView {
                        Label("记录加载失败", systemImage: "wifi.exclamationmark")
                    } description: {
                        Text(errorMessage)
                    } actions: {
                        Button("重试") { Task { await store.load(type: selectedType) } }
                            .buttonStyle(.borderedProminent)
                    }
                } else {
                    ContentUnavailableView {
                        Label("还没有记录", systemImage: "note.text")
                    } description: {
                        Text(store.errorMessage ?? "把身体感受、产检结果和想记下的事放在这里。")
                    } actions: {
                        Button("新增记录") { showingComposer = true }
                            .buttonStyle(.borderedProminent)
                    }
                }
            }
            .navigationTitle("记录")
            .background(Color.aimCanvas)
            .toolbar {
                if session.pregnancyID != nil {
                    ToolbarItem(placement: .primaryAction) {
                        Button("新增记录", systemImage: "plus") { showingComposer = true }
                    }
                }
            }
            .refreshable {
                guard session.pregnancyID != nil else { return }
                await store.load(type: selectedType)
            }
            .task(id: session.pregnancyID) {
                guard session.pregnancyID != nil else { return }
                if store.snapshot == nil { await store.load(type: selectedType) }
            }
            .onChange(of: selectedType) { _, type in
                guard session.pregnancyID != nil else { return }
                Task { await store.load(type: type) }
            }
            .sheet(isPresented: $showingComposer) {
                RecordComposerView(store: store) { showingComposer = false }
            }
            .sheet(isPresented: $showingPregnancySetup) {
                PregnancySetupView()
            }
        }
    }

    private var pregnancySetupContent: some View {
        ContentUnavailableView {
            Label("先补充孕期信息", systemImage: "calendar.badge.plus")
        } description: {
            Text("有了预产期或末次月经，Aim 才能把记录放进正确的孕期时间线。")
        } actions: {
            Button("补充孕期信息") { showingPregnancySetup = true }
                .buttonStyle(.borderedProminent)
        }
    }

    private func recordsList(_ records: [RecordItem]) -> some View {
        List {
            Section {
                Picker("记录类型", selection: $selectedType) {
                    Text("全部").tag(RecordType?.none)
                    Text("身体感受").tag(RecordType?.some(.symptom))
                    Text("产检").tag(RecordType?.some(.checkup))
                    Text("随手记").tag(RecordType?.some(.note))
                }
                .pickerStyle(.segmented)
            }
            .listRowBackground(Color.clear)

            if let errorMessage = store.errorMessage {
                Section {
                    HStack(alignment: .firstTextBaseline, spacing: 12) {
                        Label("刷新记录失败", systemImage: "wifi.exclamationmark")
                            .foregroundStyle(.secondary)
                        Spacer()
                        Button("重试") { Task { await store.load(type: selectedType) } }
                            .buttonStyle(.bordered)
                    }
                    Text(errorMessage)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }

            if records.isEmpty {
                Section {
                    ContentUnavailableView("这一类还没有记录", systemImage: "note.text", description: Text("可以先记下一次身体感受或产检结果。"))
                    Button("新增记录") { showingComposer = true }
                }
                .listRowBackground(Color.clear)
            } else {
                Section("按发生时间") {
                    ForEach(records) { record in
                        NavigationLink {
                            RecordDetailView(record: record, store: store, planStore: planStore)
                        } label: {
                            RecordRow(record: record)
                        }
                        .accessibilityIdentifier("record-row-\(record.type.rawValue)")
                    }
                }
            }
        }
        .listStyle(.insetGrouped)
    }
}

struct RecordRow: View {
    let record: RecordItem

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: record.type.symbolName)
                .foregroundStyle(Color.aimAccent)
                .frame(width: 24)
            VStack(alignment: .leading, spacing: 4) {
                Text(record.displayTitle)
                    .font(.body.weight(.medium))
                Text(record.displaySummary)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                HStack(spacing: 6) {
                    Text(record.occurredAt, format: .dateTime.month(.abbreviated).day().hour().minute())
                    Text("·")
                    Label(record.visibility.displayName, systemImage: record.visibility == .family ? "person.2" : "lock")
                }
                .font(.caption)
                .foregroundStyle(.tertiary)
            }
        }
    }
}

extension RecordType {
    var displayName: String {
        switch self {
        case .symptom: "身体感受"
        case .checkup: "产检"
        case .note: "随手记"
        case .unknown: "记录"
        }
    }

    var symbolName: String {
        switch self {
        case .symptom: "heart.text.square"
        case .checkup: "cross.case"
        case .note: "note.text"
        case .unknown: "doc"
        }
    }
}

extension RecordVisibility {
    var displayName: String {
        switch self {
        case .family: "家庭可见"
        case .private: "仅自己可见"
        case .unknown: "未知范围"
        }
    }
}

extension RecordItem {
    var displayTitle: String {
        switch structuredData {
        case let .symptom(data): data.symptoms.joined(separator: "、")
        case let .checkup(data): data.examItems
        case .note: title?.isEmpty == false ? title! : "随手记"
        case .unknown: type.displayName
        }
    }

    var displaySummary: String {
        switch structuredData {
        case let .symptom(data):
            let note = data.note?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            return "程度 \(data.severity)" + (note.isEmpty ? "" : " · \(note)")
        case let .checkup(data): return data.result
        case .note: return content?.isEmpty == false ? content! : "没有补充内容"
        case .unknown: return "暂不支持展示这类记录"
        }
    }
}
