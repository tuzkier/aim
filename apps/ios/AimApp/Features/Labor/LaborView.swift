import SwiftUI

/// 分娩页：宫缩计时、立即就医的情况、什么时候出发、待产包、「我们出发去医院了」。规格 6.1。
struct LaborView: View {
    @Environment(ContractionStore.self) private var contractions
    let libraryStore: LibraryStore
    let agentStore: AgentStore

    @State private var timing = false
    @State private var showingTrip = false
    @State private var showingWhenToGo = false
    @State private var showingAgent = false
    @State private var toast: AimToastMessage?

    /// 百科里讲「什么时候去医院」的条目。
    private static let whenToGoEntryID = "birth.when-to-go"

    var body: some View {
        ScrollView {
            VStack(spacing: AimMetrics.space12) {
                if let weeks = contractions.gestationalWeeks, weeks < ContractionMath.pretermWeeks {
                    pretermNotice
                }
                timerCard
                LaborGoNowCard(callIdentifier: "labor-call-120")
                whenToLeaveCard
                preparationCard
                tripButton
            }
            .padding(.horizontal, AimMetrics.space16)
            .padding(.bottom, AimMetrics.space28)
        }
        .background(Color.aimCanvas)
        .accessibilityIdentifier("labor-page")
        .navigationTitle("分娩准备")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button("问 AIM") {
                    agentStore.focus(context: agentContext)
                    showingAgent = true
                }
            }
        }
        .task { await contractions.load() }
        .navigationDestination(isPresented: $showingWhenToGo) {
            EncyclopediaEntryView(entryID: Self.whenToGoEntryID, store: libraryStore, agentStore: agentStore)
        }
        .fullScreenCover(isPresented: $timing) {
            ContractionTimerView(agentStore: agentStore, onTripSaved: showTripSaved) { timing = false }
        }
        .fullScreenCover(isPresented: $showingAgent) {
            AgentView(store: agentStore) { showingAgent = false }
        }
        .sheet(isPresented: $showingTrip) {
            HospitalTripSheet(repository: contractions.repository, defaultReason: .contractions, contractionRecordID: nil) { saved in
                showingTrip = false
                if saved { showTripSaved() }
            }
        }
        .aimToast($toast)
    }

    private func showTripSaved() {
        toast = AimToastMessage(text: LaborCopy.tripSaved, undoTitle: "", accessibilityIdentifier: "labor-trip-saved")
    }

    private var agentContext: AgentContext {
        var lines = ["当前在分娩准备页"]
        if let latest = contractions.latest {
            lines.append("最近一次宫缩计时：" + latest.startedAt.formatted(date: .abbreviated, time: .shortened)
                         + " " + ContractionFormat.summary(latest.data))
        }
        return AgentContext(title: "分娩准备", summary: lines.joined(separator: "\n"))
    }

    private var pretermNotice: some View {
        Label(LaborCopy.pretermBanner, systemImage: "exclamationmark.triangle.fill")
            .font(.subheadline)
            .foregroundStyle(Color.aimDanger)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(AimMetrics.space12)
            .background(Color.aimDangerSoft, in: RoundedRectangle(cornerRadius: AimMetrics.radiusButton, style: .continuous))
    }

    private var timerCard: some View {
        // 档位会随时间回落（停顿超过 20 分钟），每分钟刷新一次就够。
        SwiftUI.TimelineView(.everyMinute) { _ in
            VStack(alignment: .leading, spacing: AimMetrics.space8) {
                Text("宫缩计时").font(.headline).foregroundStyle(Color.aimTextPrimary)
                if let active = contractions.active, let status = contractions.status {
                    Text(LaborCopy.stageTitle(status.stage))
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(Color.aimTextPrimary)
                    Text("第 \(active.spans.count) 次")
                        .font(.subheadline)
                        .foregroundStyle(Color.aimTextSecondary)
                } else if let latest = contractions.latest.map({ "上次 " + ContractionFormat.summary($0.data) }) {
                    Text(latest).font(.subheadline).foregroundStyle(Color.aimTextSecondary)
                }
                Button { timing = true } label: {
                    Text(contractions.active == nil ? "开始宫缩计时" : "回到计时").frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .accessibilityIdentifier("labor-start-timer")
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .aimCard()
        }
    }

    private var whenToLeaveCard: some View {
        VStack(alignment: .leading, spacing: AimMetrics.space8) {
            Text(LaborCopy.whenToLeaveTitle).font(.headline).foregroundStyle(Color.aimTextPrimary)
            ForEach(LaborCopy.whenToLeave, id: \.self) { line in
                Text(line).font(.subheadline).foregroundStyle(Color.aimTextPrimary)
            }
            // 百科还没加载、或这条没发布时不显示：点进去只会看到「已下线」。
            if libraryStore.encyclopedia.entries.contains(where: { $0.id == Self.whenToGoEntryID }) {
                Button("详细说明") { showingWhenToGo = true }
                    .font(.subheadline.weight(.medium))
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .aimCard()
    }

    private var preparationCard: some View {
        NavigationLink {
            LibraryCategoryDetail(category: .preparation, store: libraryStore, agentStore: agentStore)
        } label: {
            HStack {
                VStack(alignment: .leading, spacing: AimMetrics.space4) {
                    Text("待产包").font(.headline).foregroundStyle(Color.aimTextPrimary)
                    // 清单还没拉到时沿用原来的分类摘要。
                    Text(LibraryCategoryID.preparationProgress(from: libraryStore.snapshot)
                         ?? LibraryCategoryID.preparation.summary(from: libraryStore.snapshot).headline)
                        .font(.subheadline)
                        .foregroundStyle(Color.aimTextSecondary)
                }
                Spacer()
                Image(systemName: "chevron.right").foregroundStyle(Color.aimTextTertiary)
            }
            .contentShape(Rectangle())
            .aimCard()
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("labor-preparation")
    }

    private var tripButton: some View {
        Button { showingTrip = true } label: {
            Text("我们出发去医院了")
                .font(.headline)
                .frame(maxWidth: .infinity)
                .padding(.vertical, AimMetrics.space8)
        }
        .buttonStyle(.borderedProminent)
        .controlSize(.large)
        .accessibilityIdentifier("labor-hospital-trip")
    }
}

/// 「我们出发去医院了」：选原因、写一句备注，保存为全家可见的记录。规格 6.3。
struct HospitalTripSheet: View {
    /// 项目里没有仓库的环境值，由调用方从 `ContractionStore.repository` 传入（同一个实例）。
    let repository: BusinessRepositoryProtocol?
    let defaultReason: HospitalTripReason
    let contractionRecordID: UUID?
    let onDone: (Bool) -> Void

    @State private var reason: HospitalTripReason
    @State private var note = ""
    @State private var saving = false
    @State private var error: String?

    init(repository: BusinessRepositoryProtocol?, defaultReason: HospitalTripReason, contractionRecordID: UUID?,
         onDone: @escaping (Bool) -> Void) {
        self.repository = repository
        self.defaultReason = defaultReason
        self.contractionRecordID = contractionRecordID
        self.onDone = onDone
        _reason = State(initialValue: defaultReason)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("为什么去") {
                    Picker("原因", selection: $reason) {
                        ForEach(HospitalTripReason.allCases, id: \.self) { Text($0.displayName).tag($0) }
                    }
                    .pickerStyle(.inline)
                    .labelsHidden()
                }
                Section {
                    TextField("一句话备注（可不填）", text: $note, axis: .vertical)
                        .accessibilityIdentifier("hospital-trip-note")
                } footer: {
                    Text(LaborCopy.tripExplanation)
                }
                if let error { Section { Text(error).foregroundStyle(Color.aimDanger) } }
            }
            .navigationTitle("我们出发去医院了")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { onDone(false) }.disabled(saving)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("告诉家人") {
                        // 同步置位再启动保存：连点只发一次，保存期间也不能取消。
                        guard !saving else { return }
                        saving = true
                        Task { await save() }
                    }
                        .disabled(saving)
                        .accessibilityIdentifier("hospital-trip-confirm")
                }
            }
        }
        .interactiveDismissDisabled(saving)
    }

    private func save() async {
        defer { saving = false }
        guard let repository else { error = "没保存上，重试"; return }
        do {
            _ = try await repository.createRecord(draft: HospitalTrip.draft(
                reason: reason, note: note, contractionRecordID: contractionRecordID, at: .now))
            NotificationCenter.default.post(name: .aimDataChanged, object: nil, userInfo: ["kinds": ["record"]])
            onDone(true)
        } catch {
            self.error = "没保存上，重试"
        }
    }
}
