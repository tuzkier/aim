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
            _hospital = State(initialValue: data.hospital)
            _examItems = State(initialValue: data.examItems)
            _result = State(initialValue: data.result)
            _doctorAdvice = State(initialValue: data.doctorAdvice)
        } else {
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
        // question / checklist 由资料库和 AIM 创建，不在手动新建里提供。
        case .question, .checklist, .knowledge, .unknown: EmptyView()
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
        Section("产检信息") {
            TextField("医院", text: $hospital)
            TextField("检查项目", text: $examItems)
            TextField("检查结果", text: $result, axis: .vertical)
            TextField("医生建议", text: $doctorAdvice, axis: .vertical)
        }
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
        case .checkup: !hospital.trimmed.isEmpty && !examItems.trimmed.isEmpty && !result.trimmed.isEmpty && !doctorAdvice.trimmed.isEmpty
        case .note: !content.trimmed.isEmpty
        case .question, .checklist, .knowledge, .none, .unknown: false
        }
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
            data = .checkup(CheckupRecordData(hospital: hospital.trimmed, examItems: examItems.trimmed, result: result.trimmed, doctorAdvice: doctorAdvice.trimmed))
        case .note: data = .note
        case .question, .checklist, .knowledge, .unknown: return nil
        }
        return RecordDraft(type: type, occurredAt: occurredAt, visibility: visibility, title: type == .note ? title.trimmed.nilIfEmpty : nil, content: type == .note ? content.trimmed.nilIfEmpty : nil, structuredData: data)
    }
}

extension String {
    var trimmed: String { trimmingCharacters(in: .whitespacesAndNewlines) }
    var nilIfEmpty: String? { isEmpty ? nil : self }
}
