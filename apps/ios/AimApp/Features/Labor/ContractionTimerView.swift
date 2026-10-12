import SwiftUI
import UIKit

/// 宫缩计时（全屏）：按开始、按结束，实时显示 5-1-1 档位。规格 6.2。
struct ContractionTimerView: View {
    @Environment(ContractionStore.self) private var store
    let agentStore: AgentStore
    /// 刚在计时页告诉了家人：调用方据此显示「已告诉家人」的提示。随后还会调 `onClose`。
    let onTripSaved: () -> Void
    let onClose: () -> Void

    @State private var confirmingFinish = false
    /// 正在结束并保存：期间不能再次结束、也不能再点出发，免得打开两次确认页。
    @State private var finishing = false
    @State private var resolvingStaleTrip = false
    @State private var trip: HospitalTripLaunch?
    @State private var lastAlertedStage: ContractionStage?

    init(agentStore: AgentStore, onTripSaved: @escaping () -> Void = {}, onClose: @escaping () -> Void) {
        self.agentStore = agentStore
        self.onTripSaved = onTripSaved
        self.onClose = onClose
    }

    var body: some View {
        NavigationStack {
            SwiftUI.TimelineView(.periodic(from: .now, by: 1)) { _ in
                // 档位随时间变化（停顿回落、单次过长），每秒取一次；底部栏也放在里面，
                // 才能和状态卡同步决定「我们出发去医院了」显示在哪里。
                let status = store.status
                ScrollView {
                    VStack(spacing: AimMetrics.space16) {
                        if let weeks = store.gestationalWeeks, weeks < ContractionMath.pretermWeeks {
                            notice(LaborCopy.pretermBanner, color: .aimDanger)
                        }
                        // 过期计时：每秒在这里判断，页面一直开着也能及时出现，不靠 TimelineView 外的弹窗。
                        if store.needsStaleDecision {
                            staleCard
                        } else {
                            statusCard(status)
                        }
                        if status?.isLongRunning == true {
                            notice(LaborCopy.longRunning, color: .aimDanger)
                        }
                        toggleButton(status)
                        LaborGoNowCard(callIdentifier: nil)
                        historyList
                    }
                    .padding(AimMetrics.space16)
                }
                .safeAreaInset(edge: .bottom) { bottomBar(status) }
                // 放在 TimelineView 里才会每秒求值：停顿回落、早产窗口滑出这类随时间的变化也能看到。
                .onChange(of: status?.stage) { _, stage in
                    guard stage == .go || stage == .pretermAlert else {
                        // 离开这两档就复位，下次再进入时还能再提醒一次。
                        lastAlertedStage = nil
                        return
                    }
                    guard stage != lastAlertedStage else { return }
                    lastAlertedStage = stage
                    UINotificationFeedbackGenerator().notificationOccurred(.warning)
                }
            }
            .background(Color.aimCanvas)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    // 关掉页面不结束计时：断点在本地，回来接着记。
                    Button("收起", action: onClose).accessibilityIdentifier("contraction-close")
                }
            }
            .navigationTitle("宫缩计时")
            .navigationBarTitleDisplayMode(.inline)
        }
        .onAppear { store.resumeAfterLaunch() }
        .confirmationDialog("结束这次计时？", isPresented: $confirmingFinish, titleVisibility: .visible) {
            Button("结束并保存") { startFinish(thenTrip: false) }
            Button("取消", role: .cancel) {}
        } message: {
            Text("正在进行的这次宫缩不计入。")
        }
        .sheet(item: $trip) { launch in
            HospitalTripSheet(
                repository: store.repository, defaultReason: .contractions,
                contractionRecordID: launch.contractionRecordID
            ) { saved in
                trip = nil
                if saved {
                    onTripSaved()
                    onClose()
                }
            }
        }
        .staleContractionTripPrompt(isPresented: $resolvingStaleTrip, resolve: startStaleTrip)
    }

    /// 档位到了「去医院」这一档：状态卡里展开按钮，底部那个隐藏，页面上只留一个。
    private func isUrgent(_ status: ContractionStatus?) -> Bool {
        status?.stage == .go || status?.stage == .pretermAlert
    }

    // MARK: - 状态卡

    private func statusCard(_ status: ContractionStatus?) -> some View {
        let stage = status?.stage ?? .early
        return VStack(alignment: .leading, spacing: AimMetrics.space8) {
            Text(LaborCopy.stageTitle(stage))
                .font(.title3.weight(.semibold))
                .foregroundStyle(Color.aimTextPrimary)
            if let minutes = status?.quietMinutes {
                Text(LaborCopy.quiet(minutes: minutes))
                    .font(.subheadline)
                    .foregroundStyle(Color.aimTextSecondary)
            }
            Text(summaryLine(status?.summary))
                .font(.subheadline)
                .foregroundStyle(Color.aimTextPrimary)
            Text(LaborCopy.stageDetail(stage))
                .font(.footnote)
                .foregroundStyle(Color.aimTextSecondary)
            Text(LaborCopy.doctorFirst)
                .font(.caption)
                .foregroundStyle(Color.aimTextTertiary)
            if isUrgent(status) {
                HStack(spacing: AimMetrics.space12) {
                    Button { startFinish(thenTrip: true) } label: {
                        tripLabel.frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                    .disabled(finishing)
                    .accessibilityIdentifier("contraction-hospital-trip")
                    LaborCallButton(identifier: nil)
                }
                .padding(.top, AimMetrics.space4)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(AimMetrics.space16)
        .background(background(for: stage), in: RoundedRectangle(cornerRadius: AimMetrics.radiusCard, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: AimMetrics.radiusCard, style: .continuous)
                .stroke(border(for: stage), lineWidth: 1)
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("contraction-status")
    }

    /// 上次计时超过 6 小时没保存：占住状态卡的位置，先选保存或丢弃。
    private var staleCard: some View {
        VStack(alignment: .leading, spacing: AimMetrics.space8) {
            Text(LaborCopy.staleTitle)
                .font(.title3.weight(.semibold))
                .foregroundStyle(Color.aimTextPrimary)
            Text(LaborCopy.staleMessage)
                .font(.subheadline)
                .foregroundStyle(Color.aimTextSecondary)
            HStack(spacing: AimMetrics.space12) {
                Button { startFinish(thenTrip: false) } label: {
                    Text("保存").frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .disabled(finishing)
                .accessibilityIdentifier("contraction-stale-save")
                Button(role: .destructive) { store.discardActive() } label: {
                    Text("丢弃").frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .disabled(finishing)
                .accessibilityIdentifier("contraction-stale-discard")
            }
            .controlSize(.large)
            .padding(.top, AimMetrics.space4)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(AimMetrics.space16)
        .background(Color.aimWarningSoft, in: RoundedRectangle(cornerRadius: AimMetrics.radiusCard, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: AimMetrics.radiusCard, style: .continuous)
                .stroke(Color.aimWarning, lineWidth: 1)
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("contraction-stale")
    }

    private func summaryLine(_ summary: ContractionSummary?) -> String {
        guard let summary else { return "按下面的按钮开始记录第一次宫缩" }
        var parts = ["最近 1 小时 \(summary.lastHourCount) 次"]
        if let interval = summary.avgIntervalSeconds { parts.append("平均 \(ContractionFormat.seconds(interval))一次") }
        parts.append("每次约 \(ContractionFormat.seconds(summary.avgDurationSeconds))")
        return parts.joined(separator: " · ")
    }

    /// 底色用浅色版，文字保持主色，读起来不费劲；边框用对应的正色区分档位。
    private func background(for stage: ContractionStage) -> Color {
        switch stage {
        case .early: .aimSurface
        case .approaching: .aimWarningSoft
        case .go: .aimAccentSoft
        case .pretermAlert: .aimDangerSoft
        }
    }

    private func border(for stage: ContractionStage) -> Color {
        switch stage {
        case .early: .aimSeparator
        case .approaching: .aimWarning
        case .go: .aimAccent
        case .pretermAlert: .aimDanger
        }
    }

    // MARK: - 开始 / 结束

    private func toggleButton(_ status: ContractionStatus?) -> some View {
        let contracting = store.active?.isContracting == true
        return Button {
            let result = store.toggle()
            if result == .began || result == .ended {
                UIImpactFeedbackGenerator(style: .medium).impactOccurred()
            }
        } label: {
            VStack(spacing: AimMetrics.space8) {
                Text(contracting ? "宫缩结束" : "宫缩开始")
                    .font(.title2.weight(.semibold))
                if contracting, let seconds = status?.runningSeconds {
                    Text(String(format: "%02d:%02d", seconds / 60, seconds % 60))
                        .font(.title3.monospacedDigit())
                }
            }
            .foregroundStyle(Color.aimTextOnAccent)
            .frame(width: 200, height: 200)
            .background(contracting ? Color.aimDanger : Color.aimAccent, in: Circle())
            .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .disabled(store.needsStaleDecision || finishing)
        .accessibilityIdentifier("contraction-toggle")
    }

    // MARK: - 本次记录

    private var historyList: some View {
        let spans = store.active?.spans ?? []
        return VStack(alignment: .leading, spacing: AimMetrics.space8) {
            HStack {
                Text("本次记录").font(.headline).foregroundStyle(Color.aimTextPrimary)
                Spacer()
                Button("删掉上一次") { store.removeLast() }
                    .disabled(spans.isEmpty || finishing)
                    .accessibilityIdentifier("contraction-remove-last")
            }
            if spans.isEmpty {
                Text("还没有记录").font(.subheadline).foregroundStyle(Color.aimTextSecondary)
            }
            ForEach(Array(spans.enumerated().reversed()), id: \.offset) { index, span in
                HStack(spacing: AimMetrics.space12) {
                    Text("第 \(index + 1) 次").foregroundStyle(Color.aimTextSecondary)
                    Text(span.start.formatted(date: .omitted, time: .standard))
                        .monospacedDigit()
                        .foregroundStyle(Color.aimTextPrimary)
                    Spacer()
                    Text(span.end.map { ContractionFormat.seconds(Int($0.timeIntervalSince(span.start))) } ?? "进行中")
                        .foregroundStyle(Color.aimTextPrimary)
                    if index > 0 {
                        Text("间隔 " + ContractionFormat.seconds(Int(span.start.timeIntervalSince(spans[index - 1].start))))
                            .foregroundStyle(Color.aimTextSecondary)
                    }
                }
                .font(.subheadline)
            }
        }
        .aimCard()
    }

    // MARK: - 底部

    private func bottomBar(_ status: ContractionStatus?) -> some View {
        VStack(spacing: AimMetrics.space8) {
            // 只显示保存失败；拉历史失败与本页无关，不冒充「没保存上」。
            if let message = store.saveError {
                HStack {
                    Text(message).font(.subheadline).foregroundStyle(Color.aimDanger)
                    Spacer()
                    Button("重试") { Task { await store.saveUnsaved() } }
                }
            }
            HStack(spacing: AimMetrics.space12) {
                Button { confirmingFinish = true } label: {
                    Text("结束计时").frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .controlSize(.large)
                .disabled(finishing || store.active?.completed.isEmpty != false)
                .accessibilityIdentifier("contraction-finish")
                if !isUrgent(status) {
                    Button {
                        startFinish(thenTrip: true)
                    } label: {
                        tripLabel.frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.large)
                    .disabled(finishing)
                    .accessibilityIdentifier("contraction-hospital-trip")
                }
            }
        }
        .padding(.horizontal, AimMetrics.space16)
        .padding(.vertical, AimMetrics.space12)
        .background(.bar)
    }

    private func notice(_ text: String, color: Color) -> some View {
        Label(text, systemImage: "exclamationmark.triangle.fill")
            .font(.subheadline)
            .foregroundStyle(color)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(AimMetrics.space12)
            .background(Color.aimDangerSoft, in: RoundedRectangle(cornerRadius: AimMetrics.radiusButton, style: .continuous))
    }

    /// 保存期间出发按钮原地显示进度，用户知道在等什么。
    @ViewBuilder private var tripLabel: some View {
        if finishing {
            HStack(spacing: AimMetrics.space8) {
                ProgressView()
                Text("正在保存…")
            }
        } else {
            Text("我们出发去医院了")
        }
    }

    /// 点击时同步置位 `finishing`，再启动保存：同一帧里的连点也挡得住。
    private func startFinish(thenTrip: Bool) {
        guard !finishing else { return }
        if thenTrip {
            switch HospitalTripLink.decide(active: store.active, latest: store.latest, now: .now) {
            case .resolveStale:
                resolvingStaleTrip = true
                return
            case let .existing(id):
                trip = HospitalTripLaunch(contractionRecordID: id)
                return
            case .none:
                trip = HospitalTripLaunch(contractionRecordID: nil)
                return
            case .finishActive: break
            }
        }
        finishing = true
        Task { await finish(thenTrip: thenTrip) }
    }

    private func startStaleTrip(_ choice: StaleContractionChoice) {
        guard !finishing else { return }
        finishing = true
        Task {
            defer { finishing = false }
            if await store.resolveStaleTrip(choice) {
                trip = HospitalTripLaunch(contractionRecordID: nil)
            }
        }
    }

    /// 只由 `startFinish` 调用，进来时 `finishing` 已为真；结束时复位。
    private func finish(thenTrip: Bool) async {
        defer { finishing = false }
        if thenTrip {
            // 最多等 5 秒：超时先打开确认页、不带关联，计时留在队列里照常补存。
            let outcome = await store.finish(timeout: ContractionStore.tripSaveTimeout)
            trip = HospitalTripLaunch(contractionRecordID: outcome?.savedRecordID)
            return
        }
        let outcome = await store.finish()
        if outcome?.savedRecordID != nil { onClose() }
        // 没保存上：留在页面，saveError 会显示「没保存上，重试」。
    }
}

/// 「立即去医院」的情况：常驻显示，不折叠（规格风险一节）。计时页和分娩页共用。
struct LaborGoNowCard: View {
    /// 「打 120」按钮的无障碍标识；分娩页要，计时页不要。
    let callIdentifier: String?

    var body: some View {
        VStack(alignment: .leading, spacing: AimMetrics.space8) {
            HStack(alignment: .top) {
                Text(LaborCopy.goNowTitle)
                    .font(.headline)
                    .foregroundStyle(Color.aimDanger)
                Spacer()
                LaborCallButton(identifier: callIdentifier)
            }
            ForEach(LaborCopy.goNowItems, id: \.self) { item in
                Label(item, systemImage: "exclamationmark.circle")
                    .font(.subheadline)
                    .foregroundStyle(Color.aimTextPrimary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .aimCard()
    }
}

/// 「打 120」：直接拨号。
struct LaborCallButton: View {
    let identifier: String?

    var body: some View {
        let link = Link(destination: URL(string: "tel://120")!) {
            Label("打 120", systemImage: "phone.fill")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(Color.aimTextOnDanger)
                .padding(.horizontal, AimMetrics.space12)
                .padding(.vertical, AimMetrics.space8)
                .background(Color.aimDanger, in: Capsule())
        }
        if let identifier {
            link.accessibilityIdentifier(identifier)
        } else {
            link
        }
    }
}
