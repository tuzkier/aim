import SwiftUI

extension BabyCareKind: Identifiable { var id: String { rawValue } }

struct PostpartumView: View {
    @Environment(AppSessionStore.self) private var session
    @State private var store: PostpartumStore
    let agentStore: AgentStore
    @State private var recordingBirth = false
    @State private var editingProfile = false
    @State private var profile: BabyProfile?
    @State private var logging: BabyCareKind?
    @State private var correctingDate = false
    @State private var withdrawing = false
    @State private var showingAgent = false

    init(repository: BusinessRepositoryProtocol?, pregnancy: PregnancySummary? = nil, agentStore: AgentStore) {
        _store = State(initialValue: PostpartumStore(repository: repository, pregnancy: pregnancy))
        self.agentStore = agentStore
    }

    var body: some View {
        List {
            stageSection
            if store.pregnancy?.isPostpartum == true {
                babySection
                if let baby = store.selectedBaby {
                    summarySection(baby)
                    Section("记下实际照护") {
                        ForEach(BabyCareKind.allCases) { kind in
                            Button("记录\(kind.title)") { logging = kind }.accessibilityIdentifier("postpartum-log-\(kind.rawValue)")
                        }
                    }
                    Section("最近可见记录") {
                        ForEach(Array(store.visibleRecords.prefix(20))) { record in
                            NavigationLink {
                                PostpartumCareDetail(record: record, store: store, agentStore: agentStore)
                            } label: {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(record.displayTitle)
                                    Text(record.displaySummary).font(.subheadline)
                                    Text(EmotionalSchedule.dateLabel(record.occurredAt)).font(.caption).foregroundStyle(.secondary)
                                }
                            }.accessibilityIdentifier("postpartum-care-row-\(record.type.rawValue)")
                        }
                    }
                    Section {
                        NavigationLink("疫苗与证件清单") { PostpartumChecklistView(store: store, baby: baby) }
                            .accessibilityIdentifier("postpartum-checklists")
                    }
                }
                scheduleSection
                if let account = session.accountID {
                    Section {
                        NavigationLink("照顾一下心情") {
                            EmotionalCareView(repository: store.repository, accountID: account,
                                weeks: nil, dueDate: store.pregnancy?.dueDate, birthDate: store.pregnancy?.birthDate,
                                isMother: sessionRoleIsMother, agentStore: agentStore)
                        }.accessibilityIdentifier("postpartum-emotional-care")
                    }
                }
                Section("日期核对") {
                    Button("修正分娩日期") { correctingDate = true }.accessibilityIdentifier("postpartum-correct-date")
                    Button("误记录了，撤回分娩", role: .destructive) { withdrawing = true }
                        .accessibilityIdentifier("postpartum-retract-birth")
                    Text("有照护、自评或已处理的产后安排时不能撤回，请核对并修正日期。").font(.footnote).foregroundStyle(.secondary)
                }
            }
            if let error = store.error { Section { Text(error).foregroundStyle(Color.aimDanger); Button("重试") { Task { await store.load() } } } }
        }
        .navigationTitle("产后与宝宝")
        .accessibilityIdentifier("postpartum-page")
        .task { await store.load() }
        .refreshable { await store.load() }
        .toolbar {
            Button("问 AIM") {
                let baby = store.selectedBaby
                agentStore.focus(context: AgentContext(title: "产后与宝宝", summary:
                    "当前在产后照护页。分娩日期：\(store.pregnancy?.birthDate.map(PostpartumCalendar.dateString) ?? "未记录")。" +
                    (baby.map { "当前宝宝：\($0.name)，宝宝编号：\($0.id.uuidString.lowercased())。" } ?? "")))
                showingAgent = true
            }
        }
        .fullScreenCover(isPresented: $showingAgent) { AgentView(store: agentStore) { showingAgent = false } }
        .sheet(isPresented: $recordingBirth) {
            BirthRecordForm(store: store) { recordingBirth = false; Task { await store.load() } }
        }
        .sheet(isPresented: $editingProfile) {
            BabyProfileForm(store: store, existing: profile) { editingProfile = false; Task { await store.load() } }
        }
        .sheet(item: $logging) { kind in
            if let baby = store.selectedBaby { BabyCareForm(store: store, baby: baby, kind: kind) { logging = nil; Task { await store.load() } } }
        }
        .sheet(isPresented: $correctingDate) { BirthDateCorrectionForm(store: store) { correctingDate = false; Task { await store.load() } } }
        .confirmationDialog("撤回分娩并恢复孕期？", isPresented: $withdrawing, titleVisibility: .visible) {
            Button("确认撤回分娩", role: .destructive) { Task { if await store.retractBirth() { await store.load() } } }
        } message: { Text("用于误操作。未使用的宝宝档案会归档，产后安排标为不适用，本次结束的孕期待办恢复。已有产后事实时会保留并拒绝撤回。") }
    }

    @State private var sessionRoleIsMother = false
    @ViewBuilder private var stageSection: some View {
        Section {
            if let pregnancy = store.pregnancy, pregnancy.isPostpartum {
                Text("产后 \(pregnancy.postpartumDays() ?? 0) 天").font(.title2.weight(.semibold)).accessibilityIdentifier("postpartum-days")
                Text("按出院医嘱照顾自己，实际复诊安排以医院为准。").font(.subheadline)
            } else {
                Text("准备好时，记下真实分娩日期。").font(.subheadline)
                Button("记录分娩") { recordingBirth = true }.accessibilityIdentifier("postpartum-record-birth")
            }
        }
        .task {
            if let members = try? await store.repository?.fetchFamily().members {
                sessionRoleIsMother = members.contains { $0.accountID == session.accountID && $0.role == .mother }
            }
        }
    }

    private var babySection: some View {
        Section("宝宝档案") {
            if store.babies.isEmpty { Text("可以稍后建立档案，不必现在填写。").foregroundStyle(.secondary) }
            else {
                Picker("当前宝宝", selection: $store.selectedBabyID) { ForEach(store.babies) { Text($0.name).tag(Optional($0.id)) } }
                if let baby = store.selectedBaby {
                    Text("\(baby.name) · 出生 \(baby.daysOld()) 天").accessibilityIdentifier("postpartum-baby-summary")
                    if let weight = baby.birthWeightGrams { LabeledContent("出生体重", value: "\(weight) 克") }
                    Button("编辑宝宝档案") { profile = baby; editingProfile = true }.accessibilityIdentifier("postpartum-edit-baby")
                }
            }
            Button("添加宝宝档案") { profile = nil; editingProfile = true }.accessibilityIdentifier("postpartum-add-baby")
        }
    }

    private func summarySection(_ baby: BabyProfile) -> some View {
        let summary = BabyDaySummary.calculate(records: store.records, babyID: baby.id, now: .now)
        return Section("今天的可见记录") {
            Text("喂养 \(summary.feedingCount) 次").accessibilityIdentifier("postpartum-feeding-count")
            Text(summary.knownVolumeMl.map { "已填写奶量 \(BabyCareRecordData.amount($0)) 毫升" } ?? "奶量未填写")
            if summary.unmeasuredFeeds > 0 { Text("另有 \(summary.unmeasuredFeeds) 次未填数量").font(.caption) }
            Text("尿布 \(summary.diaperCount) 次 · 湿 \(summary.wetCount) · 便 \(summary.dirtyCount)")
                .accessibilityIdentifier("postpartum-diaper-count")
            Text("睡眠记录 \(summary.sleepSeconds / 60) 分钟").accessibilityIdentifier("postpartum-sleep-total")
            Text("只统计你有权限看到的记录，不代表全天实际情况，不据此判断吃够或睡够。").font(.caption).foregroundStyle(.secondary)
        }
    }

    private var scheduleSection: some View {
        Section("产后安排") {
            ForEach(store.currentSchedule.filter { ($0.sourceID ?? "").contains(".mother.") || ($0.sourceID ?? "").contains(store.selectedBaby?.id.uuidString.lowercased() ?? "no-baby") }) { task in
                HStack {
                    Button { Task { _ = await store.complete(task) } } label: {
                        Image(systemName: task.status == .completed ? "checkmark.circle.fill" : "circle")
                    }.disabled(!task.isOpen || store.isSaving).buttonStyle(.plain)
                    NavigationLink { TaskDetailView(task: task, repository: store.repository) } label: {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(task.title)
                            if let due = task.dueAt { Text(PostpartumCalendar.dayLabel(due)).font(.caption).foregroundStyle(.secondary) }
                        }
                    }
                }
            }
            if let raw = store.content?.careSourceURL, let url = URL(string: raw) { Link("访视与复查资料来源", destination: url) }
        }
    }
}

struct BirthDateCorrectionForm: View {
    @Bindable var store: PostpartumStore
    let onSaved: () -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var date: Date
    init(store: PostpartumStore, onSaved: @escaping () -> Void) {
        self.store = store; self.onSaved = onSaved
        _date = State(initialValue: store.pregnancy?.birthDate ?? .now)
    }
    var body: some View {
        NavigationStack {
            Form {
                DatePicker("真实分娩日期", selection: $date, in: ...Date.now, displayedComponents: .date)
                    .datePickerStyle(.wheel).accessibilityIdentifier("birth-correct-date")
                Text("同步修正仍使用默认日期的安排。实际门诊预约和已记的照护时间不会自动挪动。").font(.footnote)
                if let error = store.error { Text(error).foregroundStyle(Color.aimDanger) }
            }
            .navigationTitle("修正分娩日期")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("取消") { dismiss() }.disabled(store.isSaving) }
                ToolbarItem(placement: .confirmationAction) { Button("保存日期") { Task { if await store.correctBirth(date) { onSaved() } } }.disabled(store.isSaving).accessibilityIdentifier("birth-correct-save") }
            }
        }
        .environment(\.locale, Locale(identifier: "zh_CN"))
        .environment(\.calendar, EmotionalSchedule.calendar)
        .environment(\.timeZone, EmotionalSchedule.calendar.timeZone)
    }
}

struct PostpartumChecklistView: View {
    @Bindable var store: PostpartumStore
    let baby: BabyProfile
    var body: some View {
        List {
            Section("出生后的证件核对") {
                ForEach(store.content?.documents ?? []) { item in
                    VStack(alignment: .leading, spacing: 6) { Text(item.title).font(.headline); Text(item.summary).font(.subheadline) }
                }
                if let raw = store.content?.documentsSourceURL, let url = URL(string: raw) { Link("浙江政务服务办事指南", destination: url) }
            }
            Section("常规疫苗节点 · 2026 年版") {
                Text(store.content?.vaccineNotice ?? "实际接种安排请向门诊核对。").font(.footnote)
                ForEach(store.content?.vaccines ?? []) { item in
                    VStack(alignment: .leading, spacing: 4) {
                        Text("\(item.age ?? "") · \(item.title)").font(.headline)
                        Text(item.summary).font(.subheadline)
                        if let months = item.months {
                            Text("生日对应参考节点：\(PostpartumCalendar.dayLabel(PostpartumCalendar.addingMonths(months, to: baby.birthDate)))").font(.caption).foregroundStyle(.secondary)
                        }
                    }
                }
                if let raw = store.content?.vaccineSourceURL, let url = URL(string: raw) { Link("国家免疫程序原文", destination: url) }
            }
        }
        .navigationTitle("疫苗与证件")
    }
}

struct PostpartumCareDetail: View {
    @Environment(AppSessionStore.self) private var session
    @Environment(\.dismiss) private var dismiss
    let record: RecordItem
    @Bindable var store: PostpartumStore
    let agentStore: AgentStore
    @State private var editing = false
    @State private var deleting = false
    @State private var showingAgent = false
    private var current: RecordItem { store.records.first { $0.id == record.id } ?? record }
    var body: some View {
        List {
            Section {
                Text(current.displayTitle).font(.headline); Text(current.displaySummary)
                Text(EmotionalSchedule.dateLabel(current.occurredAt)); Text(current.visibility.displayName)
                if let baby = store.babies.first(where: { $0.id == current.babyCare?.babyID }) { LabeledContent("宝宝", value: baby.name) }
                if let end = current.babyCare?.endedAt { LabeledContent("结束", value: EmotionalSchedule.dateLabel(end)) }
                if let note = current.content { Text(note) }
            }
            Section {
                Button("问 AIM") { agentStore.prepareAnalysis("请按这条实际照护记录帮助我理解：\(current.displaySummary)，不要根据数量判断吃够或睡够。", context: current.agentContext); showingAgent = true }
                if current.isEditable(by: session.accountID) {
                    Button("编辑照护记录") { editing = true }.disabled(store.babies.isEmpty || store.isSaving)
                        .accessibilityIdentifier("baby-care-edit")
                    Button("删除照护记录", role: .destructive) { deleting = true }.disabled(store.isSaving).accessibilityIdentifier("baby-care-delete")
                }
            }
            if let error = store.error { Section { Text(error).foregroundStyle(Color.aimDanger) } }
        }
        .navigationTitle("照护记录")
        .sheet(isPresented: $editing) {
            if let baby = store.babies.first(where: { $0.id == current.babyCare?.babyID }), let kind = BabyCareKind(rawValue: current.type.rawValue) {
                BabyCareForm(store: store, baby: baby, kind: kind, record: current) { editing = false }
            }
        }
        .confirmationDialog("删除这条照护记录？", isPresented: $deleting) { Button("删除", role: .destructive) { Task { if await store.deleteCare(current) { dismiss() } } } }
        .fullScreenCover(isPresented: $showingAgent) { AgentView(store: agentStore) { showingAgent = false } }
    }
}

struct PostpartumCareDetailHost: View {
    let record: RecordItem
    let agentStore: AgentStore
    @State private var store: PostpartumStore
    init(record: RecordItem, repository: BusinessRepositoryProtocol?, agentStore: AgentStore) {
        self.record = record; self.agentStore = agentStore
        _store = State(initialValue: PostpartumStore(repository: repository))
    }
    var body: some View { PostpartumCareDetail(record: record, store: store, agentStore: agentStore).task { await store.load() } }
}
