import SwiftUI

struct BirthRecordForm: View {
    @Bindable var store: PostpartumStore
    let onSaved: () -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var birthDate = Date.now
    @State private var createBaby = false
    @State private var name = "宝宝"
    @State private var sex = "unknown"
    @State private var weight = ""
    @State private var confirming = false

    private var validWeight: Bool { weight.isEmpty || Int(weight).map { (1...20000).contains($0) } == true }
    var body: some View {
        NavigationStack {
            Form {
                Section("实际分娩日期") {
                    DatePicker("分娩日期", selection: $birthDate, in: ...Date.now, displayedComponents: .date)
                        .accessibilityIdentifier("birth-date")
                    Text("保存后全家切换到产后。未完成的孕期模板待办会标为不再适用，不等于已完成。")
                        .font(.footnote).foregroundStyle(.secondary)
                }
                Section("宝宝档案（可稍后建立）") {
                    Toggle("同时建立宝宝档案", isOn: $createBaby).accessibilityIdentifier("birth-create-baby")
                    if createBaby {
                        babyFields(name: $name, sex: $sex, weight: $weight)
                    }
                    Text("分娩日期和宝宝档案属于家庭，家人可见。").font(.footnote).foregroundStyle(.secondary)
                }
                if !validWeight { Text("体重请用克填写整数，也可以先留空。").foregroundStyle(Color.aimDanger) }
                if let error = store.error { Text(error).foregroundStyle(Color.aimDanger) }
            }
            .navigationTitle("记录分娩")
            .disabled(store.isSaving)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("取消") { dismiss() }.disabled(store.isSaving) }
                ToolbarItem(placement: .confirmationAction) {
                    Button(store.isSaving ? "正在保存…" : "保存分娩") { confirming = true }
                        .disabled(store.isSaving || (createBaby && !validWeight)).accessibilityIdentifier("birth-save")
                }
            }
            .confirmationDialog("确认记录分娩并切换产后？", isPresented: $confirming, titleVisibility: .visible) {
                Button("确认记录") {
                    let babies = createBaby ? [BabyDraft(name: name, birthDate: birthDate, sex: sex, birthWeightGrams: Int(weight))] : []
                    Task { if await store.recordBirth(date: birthDate, babies: babies) { onSaved() } }
                }
            }
        }
        .environment(\.locale, Locale(identifier: "zh_CN"))
        .environment(\.calendar, EmotionalSchedule.calendar)
        .environment(\.timeZone, EmotionalSchedule.calendar.timeZone)
    }
}

@ViewBuilder private func babyFields(name: Binding<String>, sex: Binding<String>, weight: Binding<String>) -> some View {
    TextField("称呼（可先用宝宝）", text: name).accessibilityIdentifier("baby-name")
        .onChange(of: name.wrappedValue) { _, value in name.wrappedValue = String(String.UnicodeScalarView(value.unicodeScalars.prefix(80))) }
    Picker("性别", selection: sex) { Text("未填写").tag("unknown"); Text("男孩").tag("male"); Text("女孩").tag("female") }
    TextField("出生体重（克，可不填）", text: weight).keyboardType(.numberPad).accessibilityIdentifier("baby-weight")
}

struct BabyProfileForm: View {
    @Bindable var store: PostpartumStore
    let existing: BabyProfile?
    let onSaved: () -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var name: String
    @State private var birthday: Date
    @State private var sex: String
    @State private var weight: String
    init(store: PostpartumStore, existing: BabyProfile? = nil, onSaved: @escaping () -> Void) {
        self.store = store; self.existing = existing; self.onSaved = onSaved
        _name = State(initialValue: existing?.name ?? "宝宝")
        _birthday = State(initialValue: existing?.birthDate ?? store.pregnancy?.birthDate ?? .now)
        _sex = State(initialValue: existing?.sex ?? "unknown")
        _weight = State(initialValue: existing?.birthWeightGrams.map(String.init) ?? "")
    }
    private var validWeight: Bool { weight.isEmpty || Int(weight).map { (1...20000).contains($0) } == true }
    var body: some View {
        NavigationStack {
            Form {
                Section("家庭的宝宝档案") {
                    babyFields(name: $name, sex: $sex, weight: $weight)
                    DatePicker("宝宝生日", selection: $birthday, in: ...Date.now, displayedComponents: .date)
                        .accessibilityIdentifier("baby-birthday")
                    Text("档案家人可见。请记录实际生日，跨日分娩时可与分娩日期分别核对。").font(.footnote).foregroundStyle(.secondary)
                }
                if !validWeight { Text("体重请用克填写整数，未确定可以留空。").foregroundStyle(Color.aimDanger) }
                if let error = store.error { Text(error).foregroundStyle(Color.aimDanger) }
            }
            .disabled(store.isSaving)
            .navigationTitle(existing == nil ? "宝宝档案" : "编辑宝宝档案")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("取消") { dismiss() }.disabled(store.isSaving) }
                ToolbarItem(placement: .confirmationAction) {
                    Button("保存档案") {
                        Task { if await store.saveBaby(BabyDraft(name: name, birthDate: birthday, sex: sex, birthWeightGrams: Int(weight)), existingID: existing?.id) { onSaved() } }
                    }.disabled(!validWeight || store.isSaving).accessibilityIdentifier("baby-profile-save")
                }
            }
        }
        .environment(\.locale, Locale(identifier: "zh_CN"))
        .environment(\.calendar, EmotionalSchedule.calendar)
        .environment(\.timeZone, EmotionalSchedule.calendar.timeZone)
    }
}

struct BabyCareForm: View {
    @Bindable var store: PostpartumStore
    let kind: BabyCareKind
    let record: RecordItem?
    let onSaved: () -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var babyID: UUID
    @State private var occurred: Date
    @State private var ended: Date
    @State private var mode: String
    @State private var volume: String
    @State private var duration: String
    @State private var side: String
    @State private var diaper: String
    @State private var note: String
    @State private var visibility: RecordVisibility

    init(store: PostpartumStore, baby: BabyProfile, kind: BabyCareKind, record: RecordItem? = nil, onSaved: @escaping () -> Void) {
        self.store = store; self.kind = kind; self.record = record; self.onSaved = onSaved
        let data = record?.babyCare
        _babyID = State(initialValue: data?.babyID ?? baby.id)
        _occurred = State(initialValue: record?.occurredAt ?? (kind == .sleep ? .now.addingTimeInterval(-3600) : .now))
        _ended = State(initialValue: data?.endedAt ?? .now)
        _mode = State(initialValue: data?.mode ?? "unknown")
        _volume = State(initialValue: data?.volumeMl.map { String($0) } ?? "")
        _duration = State(initialValue: data?.durationMinutes.map(String.init) ?? "")
        _side = State(initialValue: data?.side ?? "unknown")
        _diaper = State(initialValue: data?.diaperKind ?? "wet")
        _note = State(initialValue: record?.content ?? "")
        _visibility = State(initialValue: record?.visibility ?? .family)
    }

    private var valid: Bool {
        if kind == .sleep { return ended > occurred && ended.timeIntervalSince(occurred) <= 86400 }
        if kind == .diaper { return true }
        let amount = volume.isEmpty || Double(volume).map { $0.isFinite && (0.1...2000).contains($0) } == true
        let minutes = duration.isEmpty || Int(duration).map { (1...180).contains($0) } == true
        return (mode == "breast" || amount) && minutes
    }
    var body: some View {
        NavigationStack {
            Form {
                Section("实际发生的照护") {
                    Picker("宝宝", selection: $babyID) { ForEach(store.babies) { Text($0.name).tag($0.id) } }
                    DatePicker(kind == .sleep ? "开始时间" : "发生时间", selection: $occurred, in: ...Date.now)
                        .accessibilityIdentifier("baby-care-time")
                    if kind == .feeding { feedingFields }
                    if kind == .diaper {
                        Picker("尿布情况", selection: $diaper) {
                            Text("湿尿布").tag("wet"); Text("便尿布").tag("dirty"); Text("都有").tag("both"); Text("干的").tag("dry")
                        }.pickerStyle(.segmented).accessibilityIdentifier("baby-diaper-kind")
                    }
                    if kind == .sleep {
                        DatePicker("结束时间", selection: $ended, in: ...Date.now).accessibilityIdentifier("baby-sleep-end")
                        Text("只记已结束的睡眠，单条最长 24 小时。").font(.footnote).foregroundStyle(.secondary)
                    }
                }
                Section("补充与可见范围") {
                    TextField("备注（可不填）", text: $note, axis: .vertical)
                        .onChange(of: note) { _, value in note = String(String.UnicodeScalarView(value.unicodeScalars.prefix(500))) }
                    Picker("谁能看到", selection: $visibility) {
                        Text("家庭可见").tag(RecordVisibility.family); Text("仅自己可见").tag(RecordVisibility.private)
                    }.accessibilityIdentifier("baby-care-visibility")
                }
                if !valid { Text("请核对数量、时长或开始结束时间；不知道的数量可以留空。").foregroundStyle(Color.aimDanger) }
                if let error = store.error { Text(error).foregroundStyle(Color.aimDanger) }
            }
            .disabled(store.isSaving)
            .navigationTitle("记录\(kind.title)")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("取消") { dismiss() }.disabled(store.isSaving) }
                ToolbarItem(placement: .confirmationAction) {
                    Button("保存照护") { Task { await save() } }.disabled(!valid || store.isSaving).accessibilityIdentifier("baby-care-save")
                }
            }
        }
        .environment(\.locale, Locale(identifier: "zh_CN"))
        .environment(\.calendar, EmotionalSchedule.calendar)
        .environment(\.timeZone, EmotionalSchedule.calendar.timeZone)
    }
    private var feedingFields: some View {
        Group {
            Picker("喂养方式", selection: $mode) {
                Text("未填写").tag("unknown"); Text("母乳亲喂").tag("breast"); Text("瓶喂母乳").tag("expressed")
                Text("配方奶").tag("formula"); Text("混合喂养").tag("mixed")
            }
            if mode != "breast" { TextField("实际奶量（毫升，不知道可不填）", text: $volume).keyboardType(.decimalPad).accessibilityIdentifier("baby-feeding-volume") }
            TextField("实际时长（整数分钟，可不填）", text: $duration).keyboardType(.numberPad)
            if mode == "breast" {
                Picker("亲喂侧别", selection: $side) { Text("未填写").tag("unknown"); Text("左侧").tag("left"); Text("右侧").tag("right"); Text("两侧").tag("both") }
            }
            Text("这里只记实际情况，数量不是建议摄入量，母乳亲喂不估算毫升。").font(.footnote).foregroundStyle(.secondary)
        }
    }
    private func save() async {
        var data = BabyCareRecordData(babyID: babyID)
        let structured: RecordStructuredData
        switch kind {
        case .feeding:
            data.mode = mode; data.volumeMl = mode == "breast" ? nil : Double(volume)
            data.durationMinutes = Int(duration); data.side = mode == "breast" && side != "unknown" ? side : nil
            structured = .feeding(data)
        case .diaper: data.diaperKind = diaper; structured = .diaper(data)
        case .sleep: data.endedAt = ended; structured = .sleep(data)
        }
        let draft = RecordDraft(type: kind.recordType, occurredAt: occurred, visibility: visibility,
            title: "宝宝\(kind.title)", content: note.isEmpty ? nil : note, structuredData: structured)
        if await store.saveCare(draft, existingID: record?.id) { onSaved() }
    }
}
