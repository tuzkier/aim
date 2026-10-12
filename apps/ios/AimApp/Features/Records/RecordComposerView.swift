import PhotosUI
import SwiftUI

struct RecordComposerView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(AppSessionStore.self) private var session
    @Bindable var store: RecordStore
    let record: RecordItem?
    let onSaved: () -> Void

    @State private var type: RecordType?
    @State private var occurredAt: Date
    @State private var visibility: RecordVisibility
    @State private var symptoms: Set<String>
    @State private var severity: Int
    @State private var symptomNote: String
    /// 产检报告的全部字段。编辑时用原报告回填，保存出来的与打开时一致，什么都不丢。
    @State private var checkup: CheckupForm
    /// 新建报告时选的照片（原始数据），保存时压缩上传。后端更新记录不收图片，编辑时不提供。
    @State private var photoSelection: [PhotosPickerItem] = []
    @State private var photos: [PickedPhoto] = []
    @State private var isLoadingPhotos = false
    @State private var photoError: String?
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
            _checkup = State(initialValue: CheckupForm(data: data))
        } else {
            _checkup = State(initialValue: CheckupForm(
                suggestedExamItems: source == nil && suggestedType == .checkup ? suggestedText : nil))
        }
        _title = State(initialValue: source?.title ?? (suggestedType == .note ? (suggestedText ?? "") : ""))
        _content = State(initialValue: source?.content ?? "")
    }

    var body: some View {
        NavigationStack {
            Form {
                typeSection
                // 家庭可见的记录家人也能改，但谁能看到只由记下它的人决定。
                if record?.canChangeVisibility(by: session.accountID) ?? true {
                    visibilitySection
                }
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
        // question / checklist 由资料库和 AIM 创建，胎动由计数器创建，宫缩与去医院由分娩页创建，都不在手动新建里提供。
        case .question, .checklist, .knowledge, .fetalMovement, .contraction, .hospitalTrip, .mood, .epds, .memory, .unknown: EmptyView()
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
            Section("产检信息（都可选）") {
                TextField("医院", text: $checkup.hospital)
                    .accessibilityIdentifier("checkup-hospital")
                TextField("检查项目", text: $checkup.examItems)
                    .accessibilityIdentifier("checkup-exam-items")
                TextField("检查结果", text: $checkup.result, axis: .vertical)
                    .accessibilityIdentifier("checkup-result")
                TextField("医生建议", text: $checkup.doctorAdvice, axis: .vertical)
                    .accessibilityIdentifier("checkup-advice")
            }
            Section {
                ForEach(CheckupMetricField.allCases) { field in
                    metricField(field)
                }
                if let message = checkup.metrics.validationMessage {
                    Text(message).font(.footnote).foregroundStyle(Color.aimDanger)
                }
            } header: {
                Text("指标（可选）")
            } footer: {
                // 空着表示这次没测，不是 0——当成 0 会把趋势线拉平。
                Text("填了才会进资料库的趋势图。这次没测就留空。")
            }
            otherItemsSection
            if record == nil { photosSection }
        }
    }

    private func metricField(_ field: CheckupMetricField) -> some View {
        HStack {
            Text(field.title)
            Spacer()
            TextField("未测", text: $checkup.metrics[field])
                .multilineTextAlignment(.trailing)
                .frame(maxWidth: 90)
#if os(iOS)
                .keyboardType(.decimalPad)
#endif
                .accessibilityIdentifier("checkup-metric-\(field.rawValue)")
            Text(field.unit).font(.caption).foregroundStyle(Color.aimTextTertiary)
                .frame(minWidth: 44, alignment: .leading)
        }
    }

    /// 七项之外的化验结果逐行记：名称、数值必填，单位、参考范围、标记可选。
    private var otherItemsSection: some View {
        Section {
            ForEach(Array($checkup.otherItems.enumerated()), id: \.element.id) { index, $item in
                VStack(alignment: .leading, spacing: AimMetrics.space8) {
                    HStack {
                        TextField("名称，如尿蛋白", text: $item.name)
                            .accessibilityIdentifier("checkup-other-name-\(index)")
                        Button(role: .destructive) {
                            let id = item.id
                            checkup.otherItems.removeAll { $0.id == id }
                        } label: {
                            Image(systemName: "minus.circle.fill")
                        }
                        .buttonStyle(.borderless)
                        .accessibilityLabel("删掉这一项")
                    }
                    HStack {
                        TextField("数值或结果", text: $item.value)
                            .accessibilityIdentifier("checkup-other-value-\(index)")
                        TextField("单位", text: $item.unit)
                            .frame(maxWidth: 80)
                    }
                    TextField("参考范围（可选）", text: $item.reference)
                    Picker("报告上的标记", selection: $item.flag) {
                        Text("无").tag(CheckupFlag?.none)
                        Text("偏高").tag(CheckupFlag?.some(.high))
                        Text("偏低").tag(CheckupFlag?.some(.low))
                        Text("异常").tag(CheckupFlag?.some(.abnormal))
                    }
                    .pickerStyle(.segmented)
                    .accessibilityIdentifier("checkup-other-flag-\(index)")
                    if let message = item.validationMessage {
                        Text(message).font(.footnote).foregroundStyle(Color.aimDanger)
                    }
                }
                .padding(.vertical, 4)
            }
            if checkup.otherItems.count < CheckupForm.maxOtherItems {
                Button {
                    checkup.otherItems.append(CheckupOtherItemInput())
                } label: {
                    Label("加一项化验", systemImage: "plus.circle")
                }
                .accessibilityIdentifier("checkup-other-add")
            }
        } header: {
            Text("其他化验项（可选）")
        } footer: {
            Text("照报告单抄：数值按原样填，比如「阴性」「+」。标记也照报告上的箭头选。")
        }
    }

    private var photosSection: some View {
        Section {
            if isLoadingPhotos { ProgressView("正在加载照片") }
            if let photoError { Text(photoError).font(.footnote).foregroundStyle(Color.aimDanger) }
            if !photos.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: AimMetrics.space8) {
                        ForEach(photos) { photo in
                            Image(uiImage: photo.thumbnail)
                                .resizable().scaledToFill()
                                .frame(width: 72, height: 72)
                                .clipShape(RoundedRectangle(cornerRadius: 10))
                        }
                    }
                }
            }
            PhotosPicker(
                selection: $photoSelection, maxSelectionCount: Self.maxPhotos,
                selectionBehavior: .ordered, matching: .images
            ) {
                Label(photos.isEmpty ? "选择报告照片" : "重新选择（已选 \(photos.count) 张）",
                      systemImage: "photo.on.rectangle")
            }
            .accessibilityIdentifier("checkup-photos")
            .disabled(store.isSaving)
        } header: {
            Text("照片（最多 \(Self.maxPhotos) 张）")
        } footer: {
            Text("保存后不能再改照片，选好再存。")
        }
        .onChange(of: photoSelection) { _, items in
            Task { await loadPhotos(items) }
        }
    }

    /// 与后端每条记录的附件上限一致。
    private static let maxPhotos = 4

    private func loadPhotos(_ items: [PhotosPickerItem]) async {
        isLoadingPhotos = true
        photoError = nil
        photos = []
        var loaded: [Data] = []
        for item in items {
            if let data = try? await item.loadTransferable(type: Data.self) { loaded.append(data) }
        }
        // 解码和缩略都放到主线程外，大图不卡表单。
        let picked = await Task.detached(priority: .userInitiated) {
            loaded.compactMap { data -> PickedPhoto? in
                guard let image = UIImage(data: data) else { return nil }
                let thumbnail = image.preparingThumbnail(of: CGSize(width: 144, height: 144)) ?? image
                return PickedPhoto(data: data, thumbnail: thumbnail)
            }
        }.value
        // 加载期间又改了选择，以最后一次为准。
        guard items == photoSelection else { return }
        isLoadingPhotos = false
        guard picked.count == items.count else {
            photoError = "有一张照片没能加载，请重新选择后再保存。"
            return
        }
        photos = picked
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
            checkup.canSave(photoCount: photos.count) && !isLoadingPhotos && photoError == nil
        case .note: !content.trimmed.isEmpty
        case .question, .checklist, .knowledge, .fetalMovement, .contraction, .hospitalTrip, .mood, .epds, .memory, .none, .unknown: false
        }
    }

    private func toggle(_ symptom: String) {
        if symptoms.contains(symptom) { symptoms.remove(symptom) } else { symptoms.insert(symptom) }
    }

    private func save() async {
        guard let draft = makeDraft() else { return }
        let saved: Bool
        if let record { saved = await store.update(recordID: record.id, draft: draft) }
        else { saved = await store.save(draft, photos: type == .checkup ? photos.map(\.data) : []) }
        if saved { savedCount += 1; onSaved(); dismiss() }
    }

    private func makeDraft() -> RecordDraft? {
        guard let type else { return nil }
        let data: RecordStructuredData
        switch type {
        case .symptom:
            data = .symptom(SymptomRecordData(symptoms: symptoms.sorted(), severity: severity, note: symptomNote.trimmed.nilIfEmpty))
        case .checkup:
            data = .checkup(checkup.draft)
        case .note: data = .note
        case .question, .checklist, .knowledge, .fetalMovement, .contraction, .hospitalTrip, .mood, .epds, .memory, .unknown: return nil
        }
        return RecordDraft(type: type, occurredAt: occurredAt, visibility: visibility, title: type == .note ? title.trimmed.nilIfEmpty : nil, content: type == .note ? content.trimmed.nilIfEmpty : nil, structuredData: data)
    }
}

/// 选好的一张照片：原始数据留着保存时压缩上传，缩略图给表单预览。
private struct PickedPhoto: Identifiable, @unchecked Sendable {
    let id = UUID()
    let data: Data
    let thumbnail: UIImage
}

extension String {
    var trimmed: String { trimmingCharacters(in: .whitespacesAndNewlines) }
    var nilIfEmpty: String? { isEmpty ? nil : self }
}
