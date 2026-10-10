import SwiftUI

// MARK: - 与上一份报告对比

/// 一项指标这次的读数，以及与上一份报告相比的变化。上一份没测这项时 `delta` 为 nil。
struct MetricDelta: Equatable, Sendable {
    let kind: CheckupMetricField
    let value: Double
    let delta: Double?
    let unit: String

    /// 「↑ 0.8 kg」「↓ 6 mmHg」「持平」。只说变了多少，不说好坏。
    var deltaText: String? {
        guard let delta else { return nil }
        guard abs(delta) >= 0.005 else { return "持平" }
        return "\(delta > 0 ? "↑" : "↓") \(CheckupMetricField.format(abs(delta))) \(unit)"
    }
}

enum CheckupComparison {
    /// 只列这次测了的指标，按白名单顺序。上一份没测的那项没得比，不当成 0。
    static func make(current: CheckupRecordData, previous: CheckupRecordData?) -> [MetricDelta] {
        CheckupMetricField.allCases.compactMap { field in
            guard let value = current.metrics[keyPath: field.keyPath] else { return nil }
            let before = previous?.metrics[keyPath: field.keyPath]
            return MetricDelta(kind: field, value: value, delta: before.map { value - $0 }, unit: field.unit)
        }
    }
}

// MARK: - 报告上的异常项

enum CheckupReport {
    /// 时间上早于这份的最近一份产检，与列表顺序无关。
    static func previous(of report: RecordItem, in records: [RecordItem]) -> CheckupRecordData? {
        records
            .filter { candidate in
                candidate.type == .checkup && candidate.id != report.id
                    && (candidate.occurredAt, candidate.createdAt) < (report.occurredAt, report.createdAt)
            }
            .max { ($0.occurredAt, $0.createdAt) < ($1.occurredAt, $1.createdAt) }
            .flatMap { record in
                if case let .checkup(data) = record.structuredData { return data }
                return nil
            }
    }

    /// 标了箭头或异常的项排在前面，其余保持化验单上的顺序。
    static func sortedItems(_ data: CheckupRecordData) -> [CheckupOtherItem] {
        data.otherItems.filter { $0.flag != nil } + data.otherItems.filter { $0.flag == nil }
    }

    static func flaggedItems(_ data: CheckupRecordData) -> [CheckupOtherItem] {
        data.otherItems.filter { $0.flag != nil }
    }

    /// 报告单上的标记原样转述，不加判断。
    static func flagLabel(_ flag: CheckupFlag) -> String {
        switch flag {
        case .high: "偏高"
        case .low: "偏低"
        case .abnormal: "异常"
        }
    }

    static func valueText(_ item: CheckupOtherItem) -> String {
        [item.value, item.unit].compactMap { $0?.trimmed.nilIfEmpty }.joined(separator: " ")
    }

    static func questionText(for item: CheckupOtherItem) -> String {
        let flag = item.flag.map(flagLabel) ?? "异常"
        return "报告里「\(item.name)」是 \(valueText(item))，标了\(flag)，需要注意什么？"
    }

    /// 这份报告里还没有对应问题的异常项。「对应」= 问题指回这份报告、且提到了这一项的名称——
    /// AIM 读报告时建的问题措辞不固定，按名称认。同名项只算一次。
    static func unaskedItems(for report: RecordItem, in records: [RecordItem]) -> [CheckupOtherItem] {
        guard case let .checkup(data) = report.structuredData else { return [] }
        let asked = records.compactMap { record -> String? in
            guard case let .question(question) = record.structuredData,
                  question.reportID == report.id else { return nil }
            return record.content
        }
        var seen = Set<String>()
        return flaggedItems(data).filter { item in
            let name = item.name.trimmed
            guard !name.isEmpty, seen.insert(name).inserted else { return false }
            return !asked.contains { $0.contains(name) }
        }
    }

    /// 「把异常项加入想问医生」：每个还没问的异常项一条问题，指回这份报告。
    static func missingQuestions(for report: RecordItem, in records: [RecordItem], now: Date) -> [RecordDraft] {
        unaskedItems(for: report, in: records).map { item in
            RecordDraft(
                type: .question, occurredAt: now,
                // 仅自己可见的报告，攒出来的问题也不该让家人看到。
                visibility: report.visibility == .private ? .private : .family,
                title: nil, content: questionText(for: item),
                structuredData: .question(QuestionRecordData(answered: false, answer: nil, reportID: report.id)))
        }
    }

    /// 问 AIM 时带上的上下文：报告日期、小写记录编号（AIM 要用它引用和读全文），再加上异常项。
    @MainActor
    static func agentContext(for report: RecordItem) -> AgentContext {
        let base = report.agentContext
        var summary = base.summary
        if case let .checkup(data) = report.structuredData {
            let flagged = flaggedItems(data).map { "\($0.name) \(valueText($0))（\(flagLabel($0.flag!))）" }
            if !flagged.isEmpty { summary += "\n异常项：" + flagged.joined(separator: "、") }
        }
        let date = report.occurredAt.formatted(.dateTime.month().day().locale(Locale(identifier: "zh_CN")))
        return AgentContext(title: "报告：\(date) 产检", summary: summary)
    }
}

// MARK: - 报告详情页

/// 产检报告详情：日期、医院、照片、指标与上次对比、其他化验项（异常排前）、结果与医嘱。
struct CheckupReportView: View {
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
    @State private var viewingImage: IdentifiedImage?
    @State private var isAddingQuestions = false
    @State private var addedQuestions: Int?

    private var current: RecordItem {
        store.snapshot?.records.first(where: { $0.id == record.id }) ?? record
    }

    private var data: CheckupRecordData {
        if case let .checkup(data) = current.structuredData { return data }
        return CheckupRecordData(hospital: nil, examItems: nil, result: nil, doctorAdvice: nil)
    }

    private var records: [RecordItem] { store.snapshot?.records ?? [current] }
    private var canEdit: Bool { current.isEditable(by: session.accountID) }

    var body: some View {
        List {
            header
            photos
            metrics
            otherItems
            texts
            Section("记录信息") {
                LabeledContent("记录人", value: session.accountID == current.authorAccountID ? "我" : "家庭成员")
                Label(current.visibility.displayName, systemImage: current.visibility == .family ? "person.2" : "lock")
            }
            actions
        }
        .listStyle(.insetGrouped)
        .navigationTitle("报告详情")
        .accessibilityIdentifier("checkup-report")
        // 从资料库进来时记录仓库可能还没加载过：对比上一份、判断问题是否已加都要靠它。
        .task { await store.load() }
        .confirmationDialog("删除这份报告？", isPresented: $showingDeleteConfirmation, titleVisibility: .visible) {
            Button("删除", role: .destructive) { Task { await delete() } }
        } message: { Text("删除后无法恢复。从这份报告加进想问医生的问题会保留。") }
        .sheet(isPresented: $showingEditor) {
            RecordComposerView(store: store, record: current) {
                showingEditor = false
                Self.announceChange()
            }
        }
        .sheet(isPresented: $showingTaskSheet) {
            RecordTaskSheet(record: current, store: store, planStore: planStore) { showingTaskSheet = false }
        }
        .fullScreenCover(isPresented: $showingAgent) {
            AgentView(store: agentStore) { showingAgent = false }
        }
        .fullScreenCover(item: $viewingImage) { item in
            AttachmentViewer(image: item.image) { viewingImage = nil }
        }
    }

    private var header: some View {
        Section {
            VStack(alignment: .leading, spacing: AimMetrics.space8) {
                Label("产检报告", systemImage: RecordType.checkup.symbolName)
                    .foregroundStyle(Color.aimAccent)
                Text(current.displayTitle).font(.title2.weight(.semibold))
                Text(current.occurredAt, format: .dateTime.year().month().day().locale(Locale(identifier: "zh_CN")))
                    .font(.subheadline).foregroundStyle(.secondary)
                if let hospital = data.hospital?.trimmed.nilIfEmpty {
                    Label(hospital, systemImage: "building.2")
                        .font(.subheadline).foregroundStyle(Color.aimTextSecondary)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .aimCard()
        }
        .listRowBackground(Color.clear)
    }

    @ViewBuilder
    private var photos: some View {
        if !current.attachmentRefs.isEmpty {
            Section("照片") {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: AimMetrics.space8) {
                        ForEach(current.attachmentRefs, id: \.self) { id in
                            AttachmentThumbnail(id: id, environment: session.environment) {
                                viewingImage = IdentifiedImage(image: $0)
                            }
                        }
                    }
                    .padding(.vertical, 4)
                }
            }
        }
    }

    @ViewBuilder
    private var metrics: some View {
        let previous = CheckupReport.previous(of: current, in: records)
        let deltas = CheckupComparison.make(current: data, previous: previous)
        if !deltas.isEmpty {
            Section {
                ForEach(deltas, id: \.kind) { delta in
                    HStack {
                        Text(delta.kind.title)
                        Spacer()
                        VStack(alignment: .trailing, spacing: 2) {
                            Text("\(CheckupMetricField.format(delta.value)) \(delta.unit)")
                                .foregroundStyle(Color.aimTextPrimary)
                            if let text = delta.deltaText {
                                Text(text).font(.caption).foregroundStyle(Color.aimTextSecondary)
                            }
                        }
                    }
                    .accessibilityElement(children: .combine)
                    .accessibilityIdentifier("report-metric-\(delta.kind.rawValue)")
                }
            } header: {
                Text("指标")
            } footer: {
                Text(previous == nil ? "这是第一份带指标的报告，下次就能看到变化。" : "箭头是与上一份报告相比的变化。")
            }
        }
    }

    @ViewBuilder
    private var otherItems: some View {
        let items = CheckupReport.sortedItems(data)
        if !items.isEmpty {
            Section("其他化验项") {
                ForEach(Array(items.enumerated()), id: \.offset) { _, item in
                    HStack(alignment: .firstTextBaseline, spacing: AimMetrics.space8) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(item.name).foregroundStyle(Color.aimTextPrimary)
                            if let reference = item.reference?.trimmed.nilIfEmpty {
                                Text("参考 \(reference)").font(.caption).foregroundStyle(Color.aimTextTertiary)
                            }
                        }
                        Spacer()
                        Text(CheckupReport.valueText(item))
                            .foregroundStyle(item.flag == nil ? Color.aimTextPrimary : Color.aimWarning)
                        if let flag = item.flag {
                            Text(CheckupReport.flagLabel(flag))
                                .font(.caption2)
                                .padding(.horizontal, AimMetrics.space8)
                                .padding(.vertical, 2)
                                .background(Color.aimWarningSoft, in: Capsule())
                                .foregroundStyle(Color.aimWarning)
                                .accessibilityIdentifier("report-flag-\(item.name)")
                        }
                    }
                }
            }
        }
    }

    @ViewBuilder
    private var texts: some View {
        let rows: [(String, String?)] = [
            ("检查项目", data.examItems), ("检查结果", data.result), ("医生建议", data.doctorAdvice),
        ]
        let filled = rows.compactMap { label, text in text?.trimmed.nilIfEmpty.map { (label, $0) } }
        if !filled.isEmpty {
            Section("结果与医嘱") {
                ForEach(filled, id: \.0) { label, text in
                    VStack(alignment: .leading, spacing: 4) {
                        Text(label).font(.caption).foregroundStyle(Color.aimTextTertiary)
                        Text(text).foregroundStyle(Color.aimTextPrimary)
                    }
                }
            }
        }
    }

    private var actions: some View {
        Section {
            if !CheckupReport.flaggedItems(data).isEmpty {
                let unasked = CheckupReport.unaskedItems(for: current, in: records)
                Button {
                    Task { await addQuestions() }
                } label: {
                    Label(
                        unasked.isEmpty ? "异常项都已加入想问医生" : "把异常项加入想问医生（\(unasked.count) 项）",
                        systemImage: unasked.isEmpty ? "checkmark.circle" : "questionmark.bubble")
                }
                .disabled(unasked.isEmpty || isAddingQuestions || store.isLoading)
                .accessibilityIdentifier("report-add-questions")
                if let addedQuestions, addedQuestions > 0 {
                    Text("已加入 \(addedQuestions) 个问题，在「想问医生」里能看到。")
                        .font(.footnote).foregroundStyle(Color.aimTextSecondary)
                }
            }
            Button {
                agentStore.focus(context: CheckupReport.agentContext(for: current))
                showingAgent = true
            } label: {
                Label("问 AIM", systemImage: "wand.and.sparkles")
            }
            .accessibilityIdentifier("report-ask-aim")
            Button("转为待办") { showingTaskSheet = true }
            if canEdit {
                Button("编辑报告") { showingEditor = true }
                    .accessibilityIdentifier("report-edit")
                Button("删除报告", role: .destructive) { showingDeleteConfirmation = true }
            }
            if let error = store.errorMessage {
                Text(error).font(.footnote).foregroundStyle(Color.aimDanger)
            }
        }
    }

    private func addQuestions() async {
        isAddingQuestions = true
        defer { isAddingQuestions = false }
        let added = await store.addQuestions(forReport: current)
        addedQuestions = added
        if added > 0 { Self.announceChange() }
    }

    private func delete() async {
        if await store.delete(recordID: record.id) {
            Self.announceChange()
            dismiss()
        }
    }

    /// 资料库、首页读的是各自的快照；在这里改了记录要告诉它们重新拉取。
    private static func announceChange() {
        NotificationCenter.default.post(name: .aimDataChanged, object: nil, userInfo: ["kinds": ["record"]])
    }
}
