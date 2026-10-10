import SwiftUI

struct RecordComposerView: View {
    @Environment(\.dismiss) private var dismiss
    @Bindable var store: RecordStore
    let record: RecordItem?
    let onSaved: () -> Void

    @State private var type: RecordType?
    @State private var occurredAt: Date
    @State private var visibility: RecordVisibility
    @State private var symptoms: Set<String>
    @State private var severity: Int
    @State private var symptomNote: String
    @State private var hospital: String
    @State private var examItems: String
    @State private var result: String
    @State private var doctorAdvice: String
    @State private var metrics: CheckupMetricInput
    /// 编辑时的原报告。表单只管四段文字和三项指标，其余字段（其他指标、其他化验项）
    /// 保存时从这里原样带回去，否则编辑一次就丢了。
    private let originalCheckup: CheckupRecordData?
    @State private var title: String
    @State private var content: String
    @State private var savedCount = 0

    private let symptomOptions = ["恶心", "乏力", "头晕"]

    init(
        store: RecordStore,
        record: RecordItem? = nil,
        suggestedType: RecordType? = nil,
        suggestedText: String? = nil,
        onSaved: @escaping () -> Void
    ) {
        self.store = store
        self.record = record
        self.onSaved = onSaved
        let source = record
        _type = State(initialValue: source?.type ?? suggestedType)
        _occurredAt = State(initialValue: source?.occurredAt ?? .now)
        _visibility = State(initialValue: source?.visibility == .unknown ? .family : (source?.visibility ?? .family))
        if case let .symptom(data) = source?.structuredData {
            _symptoms = State(initialValue: Set(data.symptoms))
            _severity = State(initialValue: data.severity)
            _symptomNote = State(initialValue: data.note ?? "")
        } else {
            _symptoms = State(initialValue: [])
            _severity = State(initialValue: 1)
            _symptomNote = State(initialValue: "")
        }
        if case let .checkup(data) = source?.structuredData {
            originalCheckup = data
            _hospital = State(initialValue: data.hospital ?? "")
            _examItems = State(initialValue: data.examItems ?? "")
            _result = State(initialValue: data.result ?? "")
            _doctorAdvice = State(initialValue: data.doctorAdvice ?? "")
            _metrics = State(initialValue: CheckupMetricInput(
                weight: data.metrics.weightKg.map { Self.text($0) } ?? "",
                systolic: data.metrics.systolic.map { Self.text($0) } ?? "",
                diastolic: data.metrics.diastolic.map { Self.text($0) } ?? ""
            ))
        } else {
            originalCheckup = nil
            _metrics = State(initialValue: CheckupMetricInput())
            _hospital = State(initialValue: "")
            _examItems = State(initialValue: source == nil && suggestedType == .checkup ? (suggestedText ?? "") : "")
            _result = State(initialValue: "")
            _doctorAdvice = State(initialValue: "")
        }
        _title = State(initialValue: source?.title ?? (suggestedType == .note ? (suggestedText ?? "") : ""))
        _content = State(initialValue: source?.content ?? "")
    }

    var body: some View {
        NavigationStack {
            Form {
                typeSection
                visibilitySection
                if let type { details(for: type) }
                if let errorMessage = store.errorMessage { Section { Text(errorMessage).foregroundStyle(.red) } }
            }
            .navigationTitle(record == nil ? "新增记录" : "编辑记录")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("取消") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("保存记录") { Task { await save() } }
                        .disabled(!canSave || store.isSaving)
                }
            }
        }
        .presentationDetents([.large])
        .sensoryFeedback(.success, trigger: savedCount)
    }

    private var typeSection: some View {
        Section("记录什么") {
            ForEach([RecordType.symptom, .checkup, .note], id: \.self) { candidate in
                Button {
                    guard record == nil else { return }
                    type = candidate
                } label: {
                    HStack {
                        Label(candidate.displayName, systemImage: candidate.symbolName)
                        Spacer()
                        if type == candidate { Image(systemName: "checkmark").foregroundStyle(Color.aimAccent) }
                    }
                }
                .foregroundStyle(.primary)
                .disabled(record != nil && candidate != type)
                .accessibilityIdentifier("record-type-\(candidate.rawValue)")
            }
            if type == .symptom {
                symptomSelector
                severitySelector
            }
        }
    }

    @ViewBuilder
    private func details(for type: RecordType) -> some View {
        switch type {
        case .symptom:
            occurredAtSection
            symptomNoteSection
        case .checkup:
            checkupFields
            occurredAtSection
        case .note:
            noteFields
            occurredAtSection
        // question / checklist 由资料库和 AIM 创建，胎动由计数器创建，都不在手动新建里提供。
        case .question, .checklist, .knowledge, .fetalMovement, .unknown: EmptyView()
        }
    }

    private var occurredAtSection: some View {
        Section("发生时间") { DatePicker("时间", selection: $occurredAt, displayedComponents: [.date, .hourAndMinute]) }
    }

    private var symptomSelector: some View {
        HStack(spacing: 8) {
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 3), spacing: 8) {
                ForEach(symptomOptions, id: \.self) { symptom in
                    Button(symptom) { toggle(symptom) }
                        .buttonStyle(.bordered)
                        .tint(symptoms.contains(symptom) ? Color.aimAccent : .secondary)
                        .accessibilityIdentifier("record-symptom-\(symptom)")
                        .accessibilityAddTraits(symptoms.contains(symptom) ? .isSelected : [])
                }
            }
        }
    }

    private var symptomNoteSection: some View {
        Section("补充说明") {
            TextField("可选补充", text: $symptomNote, axis: .vertical)
        }
    }

    private var severitySelector: some View {
        HStack(spacing: 8) {
            Text("程度")
            Spacer()
            ForEach(1...5, id: \.self) { value in
                Button("\(value)") { severity = value }
                    .buttonStyle(.bordered)
                    .tint(severity == value ? Color.aimAccent : .secondary)
                    .accessibilityLabel("程度 \(value)")
                    .accessibilityIdentifier("record-severity-\(value)")
                    .accessibilityAddTraits(severity == value ? .isSelected : [])
            }
        }
    }

    private var checkupFields: some View {
        Group {
            Section("产检信息") {
                TextField("医院", text: $hospital)
                    .accessibilityIdentifier("checkup-hospital")
                TextField("检查项目", text: $examItems)
                    .accessibilityIdentifier("checkup-exam-items")
                TextField("检查结果", text: $result, axis: .vertical)
                    .accessibilityIdentifier("checkup-result")
                TextField("医生建议", text: $doctorAdvice, axis: .vertical)
                    .accessibilityIdentifier("checkup-advice")
            }
            Section {
                metricField("体重", unit: "kg", text: $metrics.weight, id: "weight")
                metricField("收缩压", unit: "mmHg", text: $metrics.systolic, id: "systolic")
                metricField("舒张压", unit: "mmHg", text: $metrics.diastolic, id: "diastolic")
                if let message = metrics.validationMessage {
                    Text(message).font(.footnote).foregroundStyle(Color.aimDanger)
                }
            } header: {
                Text("指标（可选）")
            } footer: {
                // 空着表示这次没测，不是 0——当成 0 会把趋势线拉平。
                Text("填了才会进资料库的趋势图。这次没测就留空。")
            }
        }
    }

    private func metricField(
        _ label: String, unit: String, text: Binding<String>, id: String
    ) -> some View {
        HStack {
            Text(label)
            Spacer()
            TextField("未测", text: text)
                .multilineTextAlignment(.trailing)
                .frame(maxWidth: 90)
#if os(iOS)
                .keyboardType(.decimalPad)
#endif
                .accessibilityIdentifier("checkup-metric-\(id)")
            Text(unit).font(.caption).foregroundStyle(Color.aimTextTertiary)
        }
    }

    /// 62.0 显示成 "62" 而不是 "62.0"，回填时看着自然。
    private static func text(_ value: Double) -> String {
        value == value.rounded() ? String(Int(value)) : String(value)
    }

    private var noteFields: some View {
        Section("随手记") {
            TextField("标题", text: $title)
            TextField("写下想记住的事", text: $content, axis: .vertical)
        }
    }

    private var visibilitySection: some View {
        Section("谁可以看到") {
            Picker("可见范围", selection: $visibility) {
                Text("家庭可见").tag(RecordVisibility.family)
                Text("仅自己可见").tag(RecordVisibility.private)
            }
            .pickerStyle(.segmented)
            Text(visibility == .family ? "家庭成员可以看到这条记录。" : "只有你的账号可以看到这条记录。")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
    }

    private var canSave: Bool {
        switch type {
        case .symptom: !symptoms.isEmpty
        case .checkup:
            // 四段文字都可选，但总得记下点什么。
            !checkupDraft.isBlank
                // 指标填错了不让存——后端也会拒，不如当场说清楚。
                && metrics.validationMessage == nil
        case .note: !content.trimmed.isEmpty
        case .question, .checklist, .knowledge, .fetalMovement, .none, .unknown: false
        }
    }

    private var checkupDraft: CheckupRecordData {
        .composed(
            from: originalCheckup, hospital: hospital, examItems: examItems,
            result: result, doctorAdvice: doctorAdvice, metrics: metrics)
    }

    private func toggle(_ symptom: String) {
        if symptoms.contains(symptom) { symptoms.remove(symptom) } else { symptoms.insert(symptom) }
    }

    private func save() async {
        guard let draft = makeDraft() else { return }
        let saved: Bool
        if let record { saved = await store.update(recordID: record.id, draft: draft) }
        else { saved = await store.save(draft) }
        if saved { savedCount += 1; onSaved(); dismiss() }
    }

    private func makeDraft() -> RecordDraft? {
        guard let type else { return nil }
        let data: RecordStructuredData
        switch type {
        case .symptom:
            data = .symptom(SymptomRecordData(symptoms: symptoms.sorted(), severity: severity, note: symptomNote.trimmed.nilIfEmpty))
        case .checkup:
            data = .checkup(checkupDraft)
        case .note: data = .note
        case .question, .checklist, .knowledge, .fetalMovement, .unknown: return nil
        }
        return RecordDraft(type: type, occurredAt: occurredAt, visibility: visibility, title: type == .note ? title.trimmed.nilIfEmpty : nil, content: type == .note ? content.trimmed.nilIfEmpty : nil, structuredData: data)
    }
}

extension String {
    var trimmed: String { trimmingCharacters(in: .whitespacesAndNewlines) }
    var nilIfEmpty: String? { isEmpty ? nil : self }
}
