import SwiftUI

struct EmotionalCareView: View {
    @State private var store: EmotionalCareStore
    let weeks: Int?
    let dueDate: Date?
    var birthDate: Date? = nil
    let isMother: Bool
    let agentStore: AgentStore?
    @State private var editingMood = false
    @State private var assessing = false
    @State private var showingAgent = false

    init(repository: BusinessRepositoryProtocol?, accountID: UUID, weeks: Int?, dueDate: Date?, birthDate: Date? = nil, isMother: Bool, agentStore: AgentStore? = nil) {
        _store = State(initialValue: EmotionalCareStore(repository: repository, accountID: accountID))
        self.weeks = weeks; self.dueDate = dueDate; self.birthDate = birthDate; self.isMother = isMother
        self.agentStore = agentStore
    }

    private var period: EmotionalPeriod { EmotionalSchedule.period(weeks: weeks, birthDate: birthDate, now: .now) }

    var body: some View {
        List {
            Section("今天的心情") {
                if let mood = store.todayMood() { Text(mood.displaySummary).accessibilityIdentifier("emotion-today-mood") }
                else { Text("想记下今天的感受吗？").foregroundStyle(.secondary) }
                Button(store.todayMood() == nil ? "记下今天的心情" : "更新今天的心情") { editingMood = true }
                    .accessibilityIdentifier("emotion-record-mood")
            }
            Section("情绪自评") {
                if isMother {
                    if EmotionalSchedule.needsAssessment(records: store.records, accountID: store.accountID,
                        weeks: weeks, dueDate: dueDate, birthDate: birthDate, now: .now) {
                        Text("到了\(period.title)的提示节点。你也可以按自己的需要随时做。").font(.subheadline)
                    }
                    Button("做一次 EPDS 自评") { assessing = true }.accessibilityIdentifier("emotion-start-epds")
                    Text("看过去 7 天的感受。只是筛查，不替代专业评估。").font(.footnote).foregroundStyle(.secondary)
                } else {
                    Text("EPDS 由孕妇或产后妈妈本人填写。家人可以支持她联系专业人员，不替她选择答案。")
                }
            }
            Section { EmotionalSupportCard() }.listRowBackground(Color.clear)
            if let error = store.error {
                Section { Text(error).foregroundStyle(Color.aimDanger); Button("重试加载") { Task { await store.load() } } }
            }
            Section("我的最近记录") {
                ForEach(store.records) { record in
                    NavigationLink {
                        EmotionalRecordDetail(record: record, store: store, agentStore: agentStore)
                    } label: {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(record.displayTitle)
                            Text(record.displaySummary).font(.subheadline).foregroundStyle(.secondary)
                            Text(EmotionalSchedule.dateLabel(record.occurredAt)).font(.caption).foregroundStyle(.secondary)
                            Label(record.visibility.displayName, systemImage: record.visibility == .private ? "lock" : "person.2")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                    }
                    .accessibilityIdentifier(record.type == .epds ? "emotion-epds-history" : "emotion-mood-history")
                }
            }
        }
        .navigationTitle("照顾一下心情")
        .toolbar {
            if let agentStore {
                Button("问 AIM") {
                    agentStore.focus(context: AgentContext(title: "情绪关照", summary: "当前在心情与情绪自评页，请按当前账号的权限读取记录，不代填自评或推断诊断。"))
                    showingAgent = true
                }
            }
        }
        .fullScreenCover(isPresented: $showingAgent) {
            if let agentStore { AgentView(store: agentStore) { showingAgent = false } }
        }
        .task { await store.load() }
        .refreshable { await store.load() }
        .sheet(isPresented: $editingMood) {
            MoodComposerView(store: store, record: store.todayMood()) { editingMood = false }
        }
        .sheet(isPresented: $assessing) {
            EPDSComposerView(store: store, period: period) { assessing = false }
        }
    }
}

struct MoodComposerView: View {
    @Bindable var store: EmotionalCareStore
    let record: RecordItem?
    let onSaved: () -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var mood: Int
    @State private var tags: Set<String>
    @State private var note: String
    @State private var share: Bool

    init(store: EmotionalCareStore, record: RecordItem? = nil, onSaved: @escaping () -> Void) {
        self.store = store; self.record = record; self.onSaved = onSaved
        let data: MoodRecordData?
        if case let .mood(value) = record?.structuredData { data = value } else { data = nil }
        _mood = State(initialValue: data?.mood ?? 0)
        _tags = State(initialValue: Set(data?.tags ?? []))
        _note = State(initialValue: record?.content ?? "")
        _share = State(initialValue: record?.visibility == .family)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("现在的感受") {
                    ForEach(1...5, id: \.self) { value in
                        Button { mood = value } label: {
                            HStack { Text(MoodRecordData.labels[value - 1]); Spacer(); if mood == value { Image(systemName: "checkmark") } }
                        }
                        .accessibilityIdentifier("mood-choice-\(value)")
                    }
                }
                Section("想补充什么（可选）") {
                    ForEach(MoodRecordData.tagOptions, id: \.0) { tag in
                        Toggle(tag.1, isOn: Binding(get: { tags.contains(tag.0) }, set: { if $0 { tags.insert(tag.0) } else { tags.remove(tag.0) } }))
                    }
                    TextField("想说的话，最多 500 字", text: $note, axis: .vertical)
                        .accessibilityIdentifier("mood-note")
                        .onChange(of: note) { _, value in note = String(String.UnicodeScalarView(value.unicodeScalars.prefix(500))) }
                }
                Section("谁能看到") {
                    Toggle("家庭可见", isOn: $share).accessibilityIdentifier("emotion-share")
                    Text(share ? "家人可以看到这条心情，仍只有你能编辑或删除。" : "默认仅自己可见，不会出现在家庭动态里。")
                        .font(.footnote).foregroundStyle(.secondary)
                }
                if let error = store.error { Section { Text(error).foregroundStyle(Color.aimDanger) } }
            }
            .navigationTitle("记下心情")
            .disabled(store.isSaving)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("取消") { dismiss() }.disabled(store.isSaving) }
                ToolbarItem(placement: .confirmationAction) {
                    Button(store.isSaving ? "正在保存…" : "保存心情") { Task { await save() } }
                        .disabled(mood == 0 || store.isSaving).accessibilityIdentifier("mood-save")
                }
            }
        }
    }

    private func save() async {
        let draft = RecordDraft(type: .mood, occurredAt: record?.occurredAt ?? .now,
            visibility: share ? .family : .private, title: "今天的心情", content: note.isEmpty ? nil : note,
            structuredData: .mood(MoodRecordData(mood: mood, tags: tags.sorted())))
        if await store.save(draft, editing: record) { onSaved() }
    }
}

struct EPDSComposerView: View {
    @Bindable var store: EmotionalCareStore
    let record: RecordItem?
    let period: EmotionalPeriod
    let onSaved: () -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var answers: [Int?]
    @State private var share: Bool
    private let questionnaire: EPDSQuestionnaire?
    @State private var showingImmediateSupport = false

    init(store: EmotionalCareStore, record: RecordItem? = nil, period: EmotionalPeriod = .manual, onSaved: @escaping () -> Void) {
        self.store = store; self.record = record; self.period = period; self.onSaved = onSaved
        var data: EPDSRecordData?
        if case let .epds(value) = record?.structuredData { data = value }
        _answers = State(initialValue: data?.answers.map { Optional($0) } ?? Array(repeating: nil, count: 10))
        _share = State(initialValue: record?.visibility == .family)
        questionnaire = try? EPDSQuestionnaire.load()
    }

    private var result: EPDSResult? { questionnaire?.result(answers) }

    var body: some View {
        NavigationStack {
            Form {
                if let questionnaire {
                    Section { Text(questionnaire.instruction); Text("只是筛查，不是诊断。").font(.footnote) }
                    if let record {
                        Section { Text("编辑 \(EmotionalSchedule.dateLabel(record.occurredAt)) 的自评，请按当时的感受核对。如果想记录现在，请做一次新的自评。") }
                    }
                    ForEach(Array(questionnaire.questions.enumerated()), id: \.element.id) { index, question in
                        Section("第 \(question.id) 题 · \(question.text)") {
                            ForEach(0..<4, id: \.self) { choice in
                                Button { answers[index] = choice } label: {
                                    HStack { Text(question.options[choice]); Spacer(); if answers[index] == choice { Image(systemName: "checkmark") } }
                                }
                                .disabled(store.isSaving)
                                .accessibilityIdentifier("epds-\(question.id)-\(choice)")
                            }
                            if index == 9, questionnaire.hasItem10Concern(answers) {
                                EmotionalSupportCard(level: .immediate, assessmentDate: record?.occurredAt)
                            }
                        }
                    }
                    if let result {
                        Section("这次的筛查结果") {
                            Text("\(result.score) / 30").font(.title2).accessibilityIdentifier("epds-result")
                            EmotionalSupportCard(level: result.supportLevel, assessmentDate: record?.occurredAt)
                        }
                    } else { Section { Text("十题全部选择后才显示总分；需要支持时不用等填完。") } }
                    Section("谁能看到") {
                        Toggle("家庭可见", isOn: $share).disabled(store.isSaving).accessibilityIdentifier("emotion-share")
                        Text(share ? "家人可以看到答案和分数，仍只有你能编辑或删除。" : "默认仅自己可见，不会出现在家庭动态里。")
                            .font(.footnote).foregroundStyle(.secondary)
                    }
                    Section("来源") {
                        Text(questionnaire.attribution).font(.caption).foregroundStyle(.secondary)
                        Link("量表与使用说明", destination: URL(string: questionnaire.sourceURL)!)
                    }
                } else {
                    Section { Text(QuestionnaireError.unavailable.localizedDescription); EmotionalSupportCard() }
                }
                if let error = store.error { Section { Text(error).foregroundStyle(Color.aimDanger) } }
            }
            .navigationTitle("情绪自评")
            .onChange(of: answers[9]) { _, _ in
                if questionnaire?.hasItem10Concern(answers) == true { showingImmediateSupport = true }
            }
            .sheet(isPresented: $showingImmediateSupport) {
                NavigationStack {
                    ScrollView { EmotionalSupportCard(level: .immediate, assessmentDate: record?.occurredAt).padding() }
                        .navigationTitle("先照顾当下的安全")
                        .toolbar {
                            ToolbarItem(placement: .confirmationAction) {
                                Button("继续填写") { showingImmediateSupport = false }.accessibilityIdentifier("emotion-continue-form")
                            }
                        }
                }
                .presentationDetents([.medium, .large])
            }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("取消") { dismiss() }.disabled(store.isSaving) }
                ToolbarItem(placement: .confirmationAction) {
                    Button(store.isSaving ? "正在保存…" : "保存自评") { Task { await save() } }
                        .disabled(result == nil || store.isSaving || recordVersionUnsupported).accessibilityIdentifier("epds-save")
                }
            }
        }
    }

    private var recordVersionUnsupported: Bool {
        if case let .epds(data) = record?.structuredData { return data.version != questionnaire?.version }
        return false
    }

    private func save() async {
        guard let questionnaire, result != nil, !recordVersionUnsupported else { return }
        let data = EPDSRecordData(version: questionnaire.version, answers: answers.compactMap { $0 }, period: period)
        let draft = RecordDraft(type: .epds, occurredAt: record?.occurredAt ?? .now, visibility: share ? .family : .private,
                                title: "情绪自评（EPDS）", content: nil, structuredData: .epds(data))
        if await store.save(draft, editing: record) { onSaved() }
    }
}

struct EmotionalRecordDetail: View {
    let record: RecordItem
    @Bindable var store: EmotionalCareStore
    @Environment(\.dismiss) private var dismiss
    @State private var editing = false
    @State private var deleting = false
    var agentStore: AgentStore? = nil
    @State private var showingAgent = false

    private var current: RecordItem { store.records.first { $0.id == record.id } ?? record }
    var body: some View {
        List {
            Section {
                Text(current.displayTitle).font(.headline)
                Text(current.displaySummary)
                Text("记录于 \(EmotionalSchedule.dateLabel(current.occurredAt))").font(.subheadline)
                Text(current.visibility.displayName)
            }
            if case let .epds(data) = current.structuredData {
                Section { EmotionalSupportCard(level: data.levelForDisplay, assessmentDate: current.occurredAt) }
                Section { Text("自评覆盖过去 7 天，不代表今天的诊断。").font(.footnote) }
            }
            if let note = current.content { Section("补充") { Text(note) } }
            if let agentStore {
                Section {
                    Button("问 AIM") {
                        agentStore.prepareAnalysis("请帮我理解这条情绪记录，不据此推断诊断：\(current.displaySummary)", context: current.agentContext)
                        showingAgent = true
                    }
                }
            }
            if current.authorAccountID == store.accountID {
                Section {
                    Button("编辑记录") { editing = true }.disabled(store.isSaving)
                    Button("删除记录", role: .destructive) { deleting = true }.disabled(store.isSaving)
                }
            }
        }
        .navigationTitle("记录详情")
        .fullScreenCover(isPresented: $showingAgent) {
            if let agentStore { AgentView(store: agentStore) { showingAgent = false } }
        }
        .sheet(isPresented: $editing) {
            if current.type == .mood { MoodComposerView(store: store, record: current) { editing = false } }
            else if case let .epds(data) = current.structuredData {
                EPDSComposerView(store: store, record: current, period: data.period) { editing = false }
            }
        }
        .confirmationDialog("删除这条情绪记录？", isPresented: $deleting) {
            Button("删除", role: .destructive) { Task { if await store.delete(current) { dismiss() } } }
        }
        .overlay(alignment: .bottom) { if let error = store.error { Text(error).foregroundStyle(Color.aimDanger).padding() } }
    }
}

struct EmotionalRecordDetailHost: View {
    let record: RecordItem
    let agentStore: AgentStore?
    @State private var store: EmotionalCareStore
    init(record: RecordItem, repository: BusinessRepositoryProtocol?, accountID: UUID, agentStore: AgentStore? = nil) {
        self.record = record
        self.agentStore = agentStore
        _store = State(initialValue: EmotionalCareStore(repository: repository, accountID: accountID))
    }
    var body: some View { EmotionalRecordDetail(record: record, store: store, agentStore: agentStore) }
}
