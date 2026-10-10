import SwiftUI

/// 分类详情。第一步只有三个分类有真实数据：身体感受、产检、危险信号；
/// 其余给出说明而不是空白页——空白页会让人以为坏了。
struct LibraryCategoryDetail: View {
    let category: LibraryCategoryID
    @Bindable var store: LibraryStore
    let agentStore: AgentStore

    @State private var showingAgent = false
    @State private var newQuestion = ""
    @State private var composingEntry: KnowledgeComposerTarget?
    @State private var showingConsultation = false
    @State private var checkedSignals: Set<String> = []
    @State private var selectedMetric: MetricKind?
    @State private var nutritionSection: NutritionSection = .recipes
    @State private var selectedPurpose: String?

    var body: some View {
        Group {
            switch category {
            case .safety: safetyList
            case .symptoms: symptomPatterns
            case .checkups: checkupOverview
            case .questions: questionList
            case .paperwork: checklist(collection: "hangzhou")
            case .preparation: checklist(collection: "preparation")
            case .nutrition: nutritionView
            case .fetalMovement: FetalMovementView(agentStore: agentStore)
            default: comingSoon
            }
        }
        // 录入界面挂在内层：同一个视图上同时挂 sheet 与 fullScreenCover 时，
        // 只有一个会生效，实测录入界面被 Agent 的 fullScreenCover 吞掉。
        .sheet(item: $composingEntry) { target in
            switch target {
            case .new:
                KnowledgeComposerView(store: store, category: category)
            case let .existing(entry):
                KnowledgeComposerView(store: store, entry: entry)
            }
        }
        .background(Color.aimCanvas)
        .navigationTitle(category.title)
#if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
#endif
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    agentStore.focus(context: category.agentContext(from: store.snapshot))
                    showingAgent = true
                } label: {
                    Image(systemName: "wand.and.sparkles")
                }
                .accessibilityLabel("AIM")
            }
        }
        .fullScreenCover(isPresented: $showingAgent) {
            AgentView(store: agentStore) { showingAgent = false }
        }
    }

    /// 只列当前孕周适用的，紧急项排在最前。
    private var visibleSafetyRules: [SafetyRule] {
        SafetyCheck.rules(store.safetyRules, forWeek: store.currentWeek)
    }

    private func pruneHiddenSignals() {
        checkedSignals = SafetyCheck.visibleSelection(
            checkedSignals, in: store.safetyRules, forWeek: store.currentWeek)
    }

    /// 危险信号做成自查而不是阅读材料：真出血的时候没人有心情通读一屏文字。
    /// 勾出正在经历的情况，直接给结论。
    private var safetyList: some View {
        List {
            Section {
                Text("勾出你正在经历的情况")
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(Color.aimTextPrimary)
            } footer: {
                Text("这里不做诊断，只把已写明的处理建议对应出来。拿不准就直接联系医院。")
            }
            .listRowBackground(Color.aimSurface)

            ForEach(visibleSafetyRules) { rule in
                Button {
                    if checkedSignals.contains(rule.id) {
                        checkedSignals.remove(rule.id)
                    } else {
                        checkedSignals.insert(rule.id)
                    }
                } label: {
                    HStack(alignment: .top, spacing: AimMetrics.space8) {
                        Image(systemName: checkedSignals.contains(rule.id)
                              ? "checkmark.square.fill" : "square")
                            .foregroundStyle(checkedSignals.contains(rule.id)
                                             ? Color.aimDanger : Color.aimTextTertiary)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(rule.condition)
                                .foregroundStyle(Color.aimTextPrimary)
                                .fixedSize(horizontal: false, vertical: true)
                            if rule.isUrgent {
                                severityTag("紧急", color: .aimDanger, background: .aimDangerSoft)
                            } else if rule.isSameDay {
                                severityTag("尽快", color: .aimWarning, background: .aimWarningSoft)
                            }
                        }
                    }
                }
                .accessibilityIdentifier("safety-signal-\(rule.id)")
                .listRowBackground(Color.aimSurface)
            }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .accessibilityIdentifier("library-safety-list")
        // 孕周或条目变了，看不见的勾选要清掉，不能在用户看不到的地方左右结论。
        .onChange(of: store.currentWeek) { pruneHiddenSignals() }
        .onChange(of: store.safetyRules) { pruneHiddenSignals() }
        .safeAreaInset(edge: .bottom) {
            if let verdict = SafetyCheck.verdict(
                for: checkedSignals, in: store.safetyRules, forWeek: store.currentWeek) {
                safetyVerdict(verdict)
            }
        }
    }

    private func severityTag(_ text: String, color: Color, background: Color) -> some View {
        Text(text)
            .font(.caption2)
            .padding(.horizontal, AimMetrics.space8)
            .padding(.vertical, 1)
            .background(background, in: Capsule())
            .foregroundStyle(color)
    }

    @ViewBuilder
    private func safetyVerdict(_ verdict: SafetyCheck.Verdict) -> some View {
        // 三档各有颜色：立即就医用危险色，当天联系用提醒色，下次产检保持中性。
        let (tint, background): (Color, Color) = switch verdict.level {
        case .now: (.aimDanger, .aimDangerSoft)
        case .soon: (.aimWarning, .aimWarningSoft)
        case .mention: (.aimTextPrimary, .aimSurfaceSunken)
        }
        VStack(alignment: .leading, spacing: AimMetrics.space8) {
            Text(verdict.headline)
                .font(.headline)
                .foregroundStyle(tint)
                .fixedSize(horizontal: false, vertical: true)
            ForEach(verdict.actions, id: \.self) { action in
                Text("· " + action)
                    .font(.footnote)
                    .foregroundStyle(Color.aimTextSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if verdict.level == .now {
                // 紧急时不该还要用户自己去翻通讯录。
                Link(destination: URL(string: "tel://120")!) {
                    Label("拨打 120", systemImage: "phone.fill")
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, AimMetrics.space8)
                        .background(Color.aimDanger, in: RoundedRectangle(
                            cornerRadius: AimMetrics.radiusButton, style: .continuous))
                        .foregroundStyle(Color.aimTextOnDanger)
                }
                .accessibilityIdentifier("safety-call")
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(AimMetrics.space16)
        .background(background)
        .accessibilityIdentifier("safety-verdict")
    }

    /// 产检是时间序列。上面切指标看趋势，下面才是历次记录。
    private var checkupOverview: some View {
        let records = store.records(in: .checkups)
        let kinds = MetricKind.available(in: records)
        let kind = selectedMetric ?? kinds.first
        return List {
            if kinds.isEmpty {
                Section {
                    Text("记录产检时填上体重或血压，这里就会出现趋势。")
                        .font(.footnote)
                        .foregroundStyle(Color.aimTextSecondary)
                }
                .listRowBackground(Color.aimSurface)
            } else if let kind, let trend = kind.trend(in: records) {
                Section {
                    if kinds.count > 1 {
                        Picker("指标", selection: Binding(
                            get: { kind }, set: { selectedMetric = $0 })) {
                            ForEach(kinds) { Text($0.title).tag($0) }
                        }
                        .pickerStyle(.segmented)
                        .accessibilityIdentifier("checkup-metric-picker")
                    }
                    MetricChart(trend: trend, title: kind.title)
                }
                .listRowBackground(Color.aimSurface)
            }

            Section("历次记录") {
                ForEach(records) { record in
                    VStack(alignment: .leading, spacing: AimMetrics.space4) {
                        Text(recordTitle(record))
                            .font(.subheadline.weight(.medium))
                            .foregroundStyle(Color.aimTextPrimary)
                        Text(record.occurredAt, style: .date)
                            .font(.caption)
                            .foregroundStyle(Color.aimTextTertiary)
                    }
                    .listRowBackground(Color.aimSurface)
                }
            }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .accessibilityIdentifier("library-checkup-overview")
    }

    /// 身体感受看的是规律，不是流水账：什么反复出现、最近还在不在发生。
    private var symptomPatterns: some View {
        let records = store.records(in: .symptoms)
        let patterns = SymptomPattern.make(from: records)
        return Group {
            if patterns.isEmpty {
                AimEmptyState(
                    title: "还没有记录身体感受",
                    message: "在时间线里记录，或者直接让 AIM 帮你记下来。",
                    actionTitle: "问问 AIM"
                ) {
                    agentStore.focus(context: category.agentContext(from: store.snapshot))
                    showingAgent = true
                }
            } else {
                List {
                    Section("反复出现") {
                        ForEach(patterns) { pattern in
                            HStack(spacing: AimMetrics.space12) {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(pattern.label)
                                        .font(.subheadline.weight(.medium))
                                        .foregroundStyle(Color.aimTextPrimary)
                                    Text(pattern.daysSinceLast == 0
                                         ? "今天还有" : "最近一次 \(pattern.daysSinceLast) 天前")
                                        .font(.caption)
                                        .foregroundStyle(Color.aimTextTertiary)
                                }
                                Spacer()
                                VStack(alignment: .trailing, spacing: 2) {
                                    Text("\(pattern.count) 次")
                                        .font(.subheadline.weight(.medium))
                                        .foregroundStyle(Color.aimAccent)
                                    Text("最重 \(pattern.worstSeverity)/5")
                                        .font(.caption2)
                                        .foregroundStyle(Color.aimTextTertiary)
                                }
                            }
                            .listRowBackground(Color.aimSurface)
                        }
                    }
                }
                .listStyle(.plain)
                .scrollContentBackground(.hidden)
                .accessibilityIdentifier("library-symptom-patterns")
            }
        }
    }

    private var recordList: some View {
        let records = store.records(in: category)
        return Group {
            if records.isEmpty {
                AimEmptyState(
                    title: "还没有内容",
                    message: "在时间线里记录，或者直接让 AIM 帮你记下来。",
                    actionTitle: "问问 AIM"
                ) {
                    agentStore.focus(context: category.agentContext(from: store.snapshot))
                    showingAgent = true
                }
            } else {
                List {
                    ForEach(records) { record in
                        VStack(alignment: .leading, spacing: AimMetrics.space4) {
                            Text(recordTitle(record))
                                .font(.subheadline.weight(.medium))
                                .foregroundStyle(Color.aimTextPrimary)
                            Text(record.occurredAt, style: .date)
                                .font(.caption)
                                .foregroundStyle(Color.aimTextTertiary)
                        }
                        .padding(.vertical, AimMetrics.space4)
                        .listRowBackground(Color.aimSurface)
                    }
                }
                .listStyle(.plain)
                .scrollContentBackground(.hidden)
                .accessibilityIdentifier("library-record-list")
            }
        }
    }

    private var questionList: some View {
        let questions = store.snapshot.records
            .filter { $0.type == .question }
            .sorted { $0.occurredAt > $1.occurredAt }
        return List {
            if let list = ConsultationList.make(from: store.snapshot) {
                Section {
                    Button { showingConsultation = true } label: {
                        HStack(spacing: AimMetrics.space8) {
                            Image(systemName: "list.clipboard").foregroundStyle(Color.aimAccent)
                            VStack(alignment: .leading, spacing: 1) {
                                Text("生成问诊清单")
                                    .font(.subheadline.weight(.medium))
                                    .foregroundStyle(Color.aimTextPrimary)
                                Text("\(list.questions.count) 个问题，产检时一次带走")
                                    .font(.caption)
                                    .foregroundStyle(Color.aimTextTertiary)
                            }
                            Spacer()
                            Image(systemName: "chevron.right")
                                .font(.caption).foregroundStyle(Color.aimTextTertiary)
                        }
                    }
                    .accessibilityIdentifier("library-consultation-list")
                    .listRowBackground(Color.aimAccentSoft)
                }
            }
            Section { addRows }
            Section {
                HStack(spacing: AimMetrics.space8) {
                    TextField("想问医生什么？", text: $newQuestion, axis: .vertical)
                        .accessibilityIdentifier("library-question-field")
                    Button {
                        let text = newQuestion
                        newQuestion = ""
                        Task { await store.addQuestion(text) }
                    } label: {
                        Image(systemName: "arrow.up.circle.fill")
                            .font(.title3)
                            .foregroundStyle(Color.aimAccent)
                    }
                    .buttonStyle(.plain)
                    .disabled(newQuestion.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    .accessibilityIdentifier("library-question-add")
                }
                .listRowBackground(Color.aimSurface)
            } footer: {
                Text("攒下来的问题，下次产检一次带走。")
            }

            ForEach(questions) { record in
                let answered: Bool = {
                    guard case let .question(data) = record.structuredData else { return false }
                    return data.answered
                }()
                Button {
                    guard !answered else { return }
                    Task { await store.markQuestionAnswered(record, answer: nil) }
                } label: {
                    HStack(alignment: .top, spacing: AimMetrics.space8) {
                        Image(systemName: answered ? "checkmark.circle.fill" : "circle")
                            .foregroundStyle(answered ? Color.aimSuccess : Color.aimTextTertiary)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(record.content ?? "")
                                .foregroundStyle(answered ? Color.aimTextTertiary : Color.aimTextPrimary)
                                .strikethrough(answered)
                            if case let .question(data) = record.structuredData,
                               let answer = data.answer, !answer.isEmpty {
                                Text(answer)
                                    .font(.footnote)
                                    .foregroundStyle(Color.aimTextSecondary)
                            }
                        }
                    }
                }
                .buttonStyle(.plain)
                .listRowBackground(Color.aimSurface)
            }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .accessibilityIdentifier("library-question-list")
        .sheet(isPresented: $showingConsultation) {
            if let list = ConsultationList.make(from: store.snapshot) {
                ConsultationListView(list: list, store: store)
            }
        }
    }

    private func checklist(collection: String) -> some View {
        let items = store.collections[collection]?.items ?? []
        // 有分组就按组收拾——真装包时是按「证件、妈妈的、宝宝的」来的，
        // 不是按清单顺序。
        let groups = Dictionary(grouping: items) { $0.group ?? "其他" }
        let groupNames = groups.keys.sorted { lhs, rhs in
            let order = ["证件": 0, "妈妈": 1, "宝宝": 2, "陪产家属": 3]
            return (order[lhs] ?? 9) < (order[rhs] ?? 9)
        }
        let hasGroups = items.contains { $0.group != nil }
        // 静态清单只是起点，攒下来的条目才是这个分类长出来的东西。
        // 此前这条分支只渲染 collections[collection]，于是两个「加一条」入口都在、
        // 条目也确实存进了服务端，详情页却什么都不显示。
        let entries = category.entries(in: store.snapshot)
        return List {
            Section { addRows }

            if !entries.isEmpty {
                Section("我记下的") {
                    ForEach(entries) { entry in
                        knowledgeRow(entry)
                    }
                }
            }
            if hasGroups {
                ForEach(groupNames, id: \.self) { name in
                    Section(name) {
                        ForEach(groups[name] ?? []) { item in
                            checklistRow(collection: collection, item: item)
                        }
                    }
                }
            }
            ForEach(hasGroups ? [] : items) { item in
                checklistRow(collection: collection, item: item)
            }

            if let source = store.collections[collection] {
                Section {
                    // 政策与清单必须能追溯来源，见 ADR-0008 安全基线。
                    Text("来源：\(source.source)")
                        .font(.caption)
                        .foregroundStyle(Color.aimTextTertiary)
                }
                .listRowBackground(Color.aimSurface)
            }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .accessibilityIdentifier("library-checklist-\(collection)")
    }

    /// 只读参考内容。饮食提示不是清单——没有「做完」这个状态，
    /// 所以不给勾选框，避免暗示它是待办。
    /// 资料库是积累下来的内容，两条加入路径并列：自己录、让 AIM 录。
    @ViewBuilder
    private var addRows: some View {
        if supportsKnowledge {
            Button { composingEntry = KnowledgeComposerTarget.new } label: {
                HStack(spacing: AimMetrics.space8) {
                    Image(systemName: "square.and.pencil").foregroundStyle(Color.aimAccent)
                    Text("自己记一条")
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(Color.aimTextPrimary)
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.caption).foregroundStyle(Color.aimTextTertiary)
                }
            }
            .accessibilityIdentifier("library-add-manually")
            .listRowBackground(Color.aimSurface)
        }
        addWithAgentRow
    }

    /// 只有承载知识条目的分类才提供手动录入。危险信号是只读的安全兜底，
    /// 不该让用户往里写。
    private var supportsKnowledge: Bool { category != .safety }

    /// 让 AIM 往当前分类里添加内容。
    private var addWithAgentRow: some View {
        Button {
            agentStore.focus(context: category.askContext(from: store.snapshot))
            showingAgent = true
        } label: {
            HStack(spacing: AimMetrics.space8) {
                Image(systemName: "wand.and.sparkles").foregroundStyle(Color.aimAccent)
                VStack(alignment: .leading, spacing: 1) {
                    Text("让 AIM 加一条")
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(Color.aimTextPrimary)
                    Text(addHint)
                        .font(.caption)
                        .foregroundStyle(Color.aimTextTertiary)
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.caption)
                    .foregroundStyle(Color.aimTextTertiary)
            }
        }
        .accessibilityIdentifier("library-add-with-agent")
        .listRowBackground(Color.aimSurface)
    }

    private var addHint: String {
        switch category {
        case .nutrition: "「记一道补铁的菜」「螃蟹能吃吗」"
        case .paperwork: "「杭州建卡要带什么」"
        case .preparation: "「待产包还缺什么」"
        case .checkups: "「这次产检结果帮我记一下」"
        case .symptoms: "「今天腰酸」"
        case .questions: "「帮我记个想问医生的问题」"
        case .safety: "问问什么情况需要立刻就医"
        case .fetalMovement: "「最近胎动正常吗」"
        }
    }

    /// 「吃什么」是两个场景：菜谱回答「做什么」，饮食提示回答「注意什么」。
    /// 找菜做饭和查能不能吃是两件事，混在一个列表里两个都不好用。
    private var nutritionView: some View {
        let entries = category.entries(in: store.snapshot)
        let purposes = NutritionSection.purposes(in: entries)
        let shown = nutritionSection.entries(
            from: entries,
            purpose: nutritionSection == .recipes ? selectedPurpose : nil)
        return List {
            Section {
                Picker("分区", selection: $nutritionSection) {
                    ForEach(NutritionSection.allCases) { Text($0.title).tag($0) }
                }
                .pickerStyle(.segmented)
                .accessibilityIdentifier("nutrition-section-picker")
            }
            .listRowBackground(Color.aimSurface)

            // 用途标签是找菜谱的入口——攒到二三十条时，标题没法找。
            if nutritionSection == .recipes, !purposes.isEmpty {
                Section {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: AimMetrics.space8) {
                            purposeChip(nil, label: "全部")
                            ForEach(purposes, id: \.self) { purposeChip($0, label: $0) }
                        }
                        .padding(.vertical, 2)
                    }
                }
                .listRowBackground(Color.aimSurface)
            }

            Section { addRows }

            if shown.isEmpty {
                Section {
                    Text(nutritionSection.emptyHint)
                        .font(.footnote)
                        .foregroundStyle(Color.aimTextSecondary)
                }
                .listRowBackground(Color.aimSurface)
            } else {
                Section(nutritionSection == .recipes ? "我收的菜谱" : "我记下的提示") {
                    ForEach(shown) { entry in
                        knowledgeRow(entry)
                    }
                }
            }

            // 自带的饮食参考优先来自孕期百科的「饮食营养」主题；百科还没发布时
            // （生产不加载草稿），回退到已审核的 nutrition 集合。
            if nutritionSection == .advice {
                let diet = store.encyclopedia.entries(inTopic: "diet", week: store.currentWeek)
                if !diet.isEmpty {
                    Section("孕期百科") {
                        ForEach(diet) { entry in
                            NavigationLink {
                                EncyclopediaEntryView(entryID: entry.id, store: store, agentStore: agentStore)
                            } label: {
                                EncyclopediaEntryRow(entry: entry, week: store.currentWeek)
                            }
                            .accessibilityIdentifier("encyclopedia-entry-\(entry.id)")
                            .listRowBackground(Color.aimSurface)
                        }
                    }
                } else if let source = store.collections["nutrition"], !source.items.isEmpty {
                    Section("Aim 自带的参考") {
                        ForEach(source.items) { item in
                            contentItemRow(item: item, collection: source)
                        }
                    }
                }
            }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .accessibilityIdentifier("library-nutrition")
    }

    /// 一条攒下来的资料。菜谱、饮食提示、办事步骤共用同一种行——
    /// 差别只在内容，不在交互：都能点进详情、都能划开编辑或删除。
    private func knowledgeRow(_ entry: KnowledgeEntry) -> some View {
        NavigationLink {
            KnowledgeDetailView(entry: entry, agentStore: agentStore)
        } label: {
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: AimMetrics.space8) {
                    if let verdict = entry.data.verdict {
                        Text(verdict.displayName)
                            .font(.caption2)
                            .padding(.horizontal, AimMetrics.space8)
                            .padding(.vertical, 1)
                            .background(verdictTint(verdict), in: Capsule())
                            .foregroundStyle(verdictColor(verdict))
                    }
                    Text(entry.title)
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(Color.aimTextPrimary)
                }
                Text(entry.subtitle)
                    .font(.footnote)
                    .foregroundStyle(Color.aimTextSecondary)
                    .lineLimit(2)
            }
        }
        .listRowBackground(Color.aimSurface)
        .swipeActions(edge: .trailing) {
            Button(role: .destructive) {
                Task { await store.deleteEntry(id: entry.id) }
            } label: { Label("删除", systemImage: "trash") }
            Button { composingEntry = .existing(entry) } label: {
                Label("编辑", systemImage: "pencil")
            }
            .tint(Color.aimAccent)
        }
    }

    private func purposeChip(_ purpose: String?, label: String) -> some View {
        let selected = selectedPurpose == purpose
        return Button {
            selectedPurpose = purpose
        } label: {
            Text(label)
                .font(.caption)
                .padding(.horizontal, AimMetrics.space12)
                .padding(.vertical, AimMetrics.space4)
                .background(selected ? Color.aimAccent : Color.aimSurfaceSunken, in: Capsule())
                .foregroundStyle(selected ? Color.aimTextOnAccent : Color.aimTextSecondary)
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("nutrition-purpose-\(purpose ?? "all")")
    }

    private func verdictTint(_ verdict: FoodVerdict) -> Color {
        switch verdict {
        case .avoid: Color.aimDangerSoft
        case .limit: Color.aimAccentSoft
        case .safe: Color.aimSuccessSoft
        case .unknown: Color.aimSurfaceSunken
        }
    }

    private func verdictColor(_ verdict: FoodVerdict) -> Color {
        switch verdict {
        case .avoid: Color.aimDanger
        case .limit: Color.aimAccent
        case .safe: Color.aimSuccess
        case .unknown: Color.aimTextSecondary
        }
    }

    /// Aim 自带的条目行。可点进详情——此前只有标题和一行摘要且不可点，
    /// 用户看到的就是一堆读不下去的行。
    private func contentItemRow(item: ContentItem, collection: ContentCollection) -> some View {
        NavigationLink {
            ContentItemDetailView(item: item, collection: collection, agentStore: agentStore)
        } label: {
            VStack(alignment: .leading, spacing: 2) {
                Text(item.title)
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(Color.aimTextPrimary)
                Text(item.summary)
                    .font(.footnote)
                    .foregroundStyle(Color.aimTextSecondary)
                    .lineLimit(2)
            }
        }
        .accessibilityIdentifier("content-item-\(item.id)")
        .listRowBackground(Color.aimSurface)
    }

    /// 分组与平铺两处共用同一行渲染。
    private func checklistRow(collection: String, item: ContentItem) -> some View {
        Button {
            Task { await store.toggleChecklistItem(collection: collection, itemID: item.id) }
        } label: {
            HStack(alignment: .top, spacing: AimMetrics.space8) {
                let done = store.isChecked(collection: collection, itemID: item.id)
                Image(systemName: done ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(done ? Color.aimSuccess : Color.aimTextTertiary)
                VStack(alignment: .leading, spacing: 2) {
                    Text(item.title)
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(Color.aimTextPrimary)
                    Text(item.summary)
                        .font(.footnote)
                        .foregroundStyle(Color.aimTextSecondary)
                }
            }
        }
        .accessibilityIdentifier("library-checklist-\(item.id)")
        .listRowBackground(Color.aimSurface)
    }

    private func reference(collection: String) -> some View {
        let items = store.collections[collection]?.items ?? []
        return List {
            Section { addRows }
            if let source = store.collections[collection] {
                ForEach(items) { item in
                    contentItemRow(item: item, collection: source)
                }
            }
            if let source = store.collections[collection] {
                Section {
                    Text("来源：\(source.source)。具体尺度以产检医生的意见为准。")
                        .font(.caption)
                        .foregroundStyle(Color.aimTextTertiary)
                }
                .listRowBackground(Color.aimSurface)
            }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .accessibilityIdentifier("library-reference-\(collection)")
    }

    private func recordTitle(_ record: RecordItem) -> String {
        if let title = record.title, !title.isEmpty { return title }
        switch record.structuredData {
        case let .symptom(data): return data.symptoms.joined(separator: "、")
        case let .checkup(data): return data.examItems
        default: return record.content ?? "记录"
        }
    }

    private var comingSoon: some View {
        AimEmptyState(
            title: category.title,
            message: category.summary(from: store.snapshot).headline,
            actionTitle: "问问 AIM"
        ) {
            agentStore.focus(context: category.agentContext(from: store.snapshot))
            showingAgent = true
        }
        .frame(maxHeight: .infinity)
    }
}


/// 录入界面的目标：新建还是编辑某一条。
enum KnowledgeComposerTarget: Identifiable {
    case new
    case existing(KnowledgeEntry)

    var id: String {
        switch self {
        case .new: "new"
        case let .existing(entry): entry.id.uuidString
        }
    }
}


/// 指标趋势的大图。柱状而不是折线——产检次数少，柱子更容易读出「这次比上次」。
private struct MetricChart: View {
    let trend: MetricTrend
    let title: String

    var body: some View {
        let values = trend.points.map(\.value)
        let low = values.min() ?? 0
        let high = values.max() ?? 1
        let span = max(high - low, 0.001)
        return VStack(alignment: .leading, spacing: AimMetrics.space8) {
            HStack(alignment: .firstTextBaseline) {
                Text(format(trend.latest ?? 0))
                    .font(.title2.weight(.medium))
                    .foregroundStyle(Color.aimTextPrimary)
                Text(trend.unit).font(.caption).foregroundStyle(Color.aimTextTertiary)
                Spacer()
                if let change = trend.change {
                    Text(change >= 0 ? "较首次 +\(format(change))" : "较首次 \(format(change))")
                        .font(.caption)
                        .foregroundStyle(Color.aimTextSecondary)
                }
            }
            HStack(alignment: .bottom, spacing: 4) {
                ForEach(Array(values.enumerated()), id: \.offset) { index, value in
                    let ratio = (value - low) / span
                    RoundedRectangle(cornerRadius: 3, style: .continuous)
                        .fill(index == values.count - 1 ? Color.aimAccent : Color.aimAccentSoft)
                        .frame(height: 12 + CGFloat(ratio) * 56)
                }
            }
            .frame(height: 68)
            .accessibilityLabel("\(title)趋势，共 \(values.count) 次记录")
        }
        .padding(.vertical, AimMetrics.space4)
    }

    private func format(_ value: Double) -> String {
        value == value.rounded() ? String(Int(value)) : String(format: "%.1f", value)
    }
}
