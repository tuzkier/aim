import SwiftUI

/// 胎动相关的固定文案集中放在这里，便于医学审核一次看全。
enum FetalMovementCopy {
    static let howTo = "选宝宝活跃的时段（饭后、睡前），侧躺或坐着。一阵连续的动只按一次，数到 10 次就结束。"
    static let underRule = "2 小时内不足 10 次，或比平时明显少了，要尽快联系医院。"
    static let mostImportant = "感觉胎动明显变少、变弱或停止时，不用数完，立即联系医院或去产科急诊。"
    static let doctorFirst = "如果你的医生教过别的数法，以医生为准。"
    static let underTitle = "2 小时内胎动不足 10 次"
    static let underBody = "请现在联系你的产检医院，或去产科急诊。不要等到明天，也不要靠喝冷水、吃甜食来「叫醒」宝宝。"
    static let lessTitle = "感觉胎动明显少了"
    static let lessBody = "不用数完。请现在联系你的产检医院，或去产科急诊。"
    static let recordedNote = "已记录。数够 10 次不代表一切正常，感觉不对就联系医院。"
    /// 没数完时没有「数够 10 次」可言，只提醒感觉不对就联系医院。
    static let recordedStoppedNote = "已记录。感觉不对就联系医院。"
    static func resume(count: Int) -> String { "有一次计数还没结束（\(count) 次）" }

    static func slow(duration: Int, baseline: Int) -> String {
        "这次用了 \(FetalMovementFormat.duration(duration))，比你平时（约 \(FetalMovementFormat.duration(baseline))）慢了一倍多，胎动可能比平时少。建议尽快联系你的产检医院。"
    }
}

struct FetalMovementCounterView: View {
    @Environment(FetalMovementStore.self) private var store
    let agentStore: AgentStore
    let onClose: () -> Void

    /// 为什么进安全提示页：文案相同的部分不变，「问问 AIM」的问题按原因区分。
    private enum SafetyReason: Equatable {
        /// 满 2 小时不足 10 次。
        case under
        /// 计数中自己点了「胎动明显少了？」。
        case less
    }

    private enum Phase: Equatable {
        case counting
        /// 本地算出的结果，不等保存；保存回来的完整结果在 `completion` 里。
        case finished(FetalMovementResult)
        case safety(SafetyReason)
    }

    @State private var phase: Phase = .counting
    /// 后台保存回来的结果，用来补上「和平时比」。保存期间为 nil。
    @State private var completion: FetalMovementCompletion?
    /// 结束那一刻就判断出的「慢一倍多」，不等保存。历史还没拉回来时为 nil，等 `completion` 补上。
    @State private var immediateSlowNotice: FetalMovementSlowNotice?
    /// 后台保存进行中：期间「重试」显示为进度，不提示没保存上。
    @State private var saving = false
    @State private var tapCount = 0
    @State private var ignoredCount = 0
    @State private var confirmingEnd = false
    @State private var showingGuide = false
    @State private var showingAgent = false
    /// 已经调过 `store.start()`。只调一次：从「问问 AIM」返回时 onAppear 会再跑，
    /// 那时计数已经结束，再 start 就会悄悄新建一个计数挂在本地。
    /// 调过之后 `active` 仍为 nil，说明计数没法开始（例如还没绑定账号与孕期）。
    @State private var startAttempted = false
    /// 已经开始结束：到点自动结束、第 10 次点击、点「胎动明显少了？」可能挨着发生，只结束一次。
    @State private var ending = false

    /// 计数阶段却没有进行中的计数——给出提示，别留一个点了没反应的大按钮。
    private var unableToStart: Bool {
        phase == .counting && startAttempted && !ending && store.active == nil
    }

    var body: some View {
        NavigationStack {
            Group {
                switch phase {
                case .counting:
                    if unableToStart { unavailable } else { counting }
                case let .finished(result): finished(result)
                case let .safety(reason): safety(reason)
                }
            }
            .padding(.horizontal, AimMetrics.space16)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color.aimCanvas)
            .navigationTitle("数胎动")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    if phase != .counting || unableToStart { Button("关闭", action: onClose) }
                }
            }
        }
        .onAppear {
            guard !startAttempted, phase == .counting else { return }
            // 恢复出来的断点已经过了 2 小时：那段时间计数页没开着，不是真的「不足 10 次」，
            // 不弹安全页。先记为未数完（后台保存），再开始一个新计数。
            if store.queueExpiredActive() { Task { await store.saveUnsaved() } }
            store.start()
            startAttempted = true
            // 上次数到第 10 次就被系统杀掉、没来得及结束：直接显示结果，不用再点一下。
            if (store.active?.count ?? 0) >= FetalMovementCounter.target { end() }
        }
        .sheet(isPresented: $showingGuide) { FetalMovementGuideView() }
        .fullScreenCover(isPresented: $showingAgent) {
            AgentView(store: agentStore) { showingAgent = false }
        }
        .confirmationDialog("现在结束吗？这次会记为未数完。", isPresented: $confirmingEnd, titleVisibility: .visible) {
            Button("结束并记录") { end() }
            Button("继续数", role: .cancel) {}
        }
    }

    private var unavailable: some View {
        ContentUnavailableView {
            Label("暂时无法开始计数", systemImage: "exclamationmark.circle")
        } description: {
            Text(FetalMovementCopy.mostImportant)
        } actions: {
            Button("关闭", action: onClose).buttonStyle(.borderedProminent)
        }
    }

    private var counting: some View {
        SwiftUI.TimelineView(.periodic(from: .now, by: 1)) { context in
            let counter = store.active
            VStack(spacing: AimMetrics.space16) {
                Button { reportLess() } label: {
                    Label("胎动明显少了？", systemImage: "exclamationmark.triangle")
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(Color.aimDanger)
                }
                .accessibilityIdentifier("fetal-movement-less-than-usual")

                Text(Self.clock(counter?.elapsed(at: context.date) ?? 0))
                    .font(.system(size: 44, weight: .semibold, design: .rounded).monospacedDigit())
                    .foregroundStyle(Color.aimTextPrimary)
                Text("目标 10 次").font(.subheadline).foregroundStyle(Color.aimTextSecondary)

                Button { tap() } label: {
                    VStack(spacing: AimMetrics.space4) {
                        Text("\(counter?.count ?? 0)")
                            .font(.system(size: 64, weight: .bold, design: .rounded).monospacedDigit())
                            .accessibilityIdentifier("fetal-movement-count")
                        Text("动了一下").font(.headline)
                    }
                    .foregroundStyle(Color.aimTextOnAccent)
                    .frame(width: 220, height: 220)
                    .background(Color.aimAccent, in: Circle())
                }
                .buttonStyle(.plain)
                .sensoryFeedback(.impact(weight: .medium), trigger: tapCount)
                // 计上一次时 ignoredCount 会清零，那次不能再轻震一下。
                .sensoryFeedback(trigger: ignoredCount) { old, new in
                    new > old ? .impact(weight: .light) : nil
                }
                .accessibilityIdentifier("fetal-movement-tap")

                if ignoredCount > 0 {
                    Text("这阵已经记过了").font(.caption).foregroundStyle(Color.aimTextSecondary)
                }

                VStack(alignment: .leading, spacing: AimMetrics.space8) {
                    Text(FetalMovementCopy.howTo)
                    Text(FetalMovementCopy.underRule)
                    Text(FetalMovementCopy.mostImportant).foregroundStyle(Color.aimDanger)
                }
                .font(.footnote)
                .foregroundStyle(Color.aimTextPrimary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .aimCard()

                HStack {
                    Button("怎么数？") { showingGuide = true }
                        .accessibilityIdentifier("fetal-movement-guide")
                    Spacer()
                    Button("结束") {
                        if (store.active?.count ?? 0) == 0 { store.discardActive(); onClose() }
                        else { confirmingEnd = true }
                    }
                    .accessibilityIdentifier("fetal-movement-end")
                }
                .font(.subheadline)
            }
            .onChange(of: context.date) { _, now in
                // 前台计时只负责刷新显示；满 2 小时的判断以开始时间为准，
                // 从后台回来时第一次刷新就会结束。
                if store.active?.isExpired(at: now) == true { end() }
            }
        }
    }

    private func tap() {
        switch store.tap() {
        case .counted: tapCount += 1; ignoredCount = 0
        case .ignored: ignoredCount += 1
        case .reachedTarget: tapCount += 1; end()
        case .expired: end()
        }
    }

    /// 结果在本地先算出来，界面立刻切过去；保存在后台进行。
    /// 保存要等网络（弱网下可能很久），安全提示不能等它。
    private func end() {
        guard !ending, let counter = store.active else { return }
        ending = true
        let result = counter.result(at: store.clock())
        // 必须在 finish() 之前取：此刻的历史还不含这次。
        immediateSlowNotice = store.slowNoticeBeforeSaving(result)
        phase = result.outcome == .under ? .safety(.under) : .finished(result)
        saveInBackground { await store.finish() }
    }

    /// 计数中点「胎动明显少了？」：先给安全提示，再善后——记一条标了「感觉胎动少了」的记录（0 次也记）。
    private func reportLess() {
        guard !ending else { return }
        ending = true
        phase = .safety(.less)
        saveInBackground { await store.abandonForSafety() }
    }

    private func saveInBackground(_ work: @escaping @MainActor () async -> FetalMovementCompletion?) {
        saving = true
        Task {
            let done = await work()
            completion = done
            saving = false
            // 本地算结果与 finish() 之间隔了一小会儿，正好跨过 2 小时时以保存的结果为准，补上安全提示。
            if done?.result.outcome == .under, case .finished = phase { phase = .safety(.under) }
        }
    }

    private func finished(_ local: FetalMovementResult) -> some View {
        let result = completion?.result ?? local
        return VStack(alignment: .leading, spacing: AimMetrics.space16) {
            Text(result.outcome == .reached
                 ? "\(result.count) 次，用了 \(FetalMovementFormat.duration(result.durationSeconds))"
                 : "\(result.count) 次 · 未数完")
                .font(.title2.weight(.semibold))
                .foregroundStyle(Color.aimTextPrimary)
            // 有历史时结束那一刻就判断；历史还没拉回来时，等保存前拉到的历史回来再补上。
            if let notice = immediateSlowNotice ?? completion?.slowNotice {
                Text(FetalMovementCopy.slow(duration: notice.durationSeconds, baseline: notice.baselineSeconds))
                    .font(.subheadline)
                    .foregroundStyle(Color.aimAccent)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .aimCard()
                    .accessibilityIdentifier("fetal-movement-slow")
                askAgentButton("我数胎动用了 \(FetalMovementFormat.duration(notice.durationSeconds))，比平时慢了一倍多，现在该怎么办？")
            }
            Text(result.outcome == .reached ? FetalMovementCopy.recordedNote : FetalMovementCopy.recordedStoppedNote)
                .font(.footnote).foregroundStyle(Color.aimTextSecondary)
            FetalMovementRetryButton(busy: saving)
            Button("完成", action: onClose)
                .buttonStyle(.borderedProminent)
                .accessibilityIdentifier("fetal-movement-done")
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("fetal-movement-finished")
    }

    private func safety(_ reason: SafetyReason) -> some View {
        VStack(alignment: .leading, spacing: AimMetrics.space16) {
            Label(reason == .under ? FetalMovementCopy.underTitle : FetalMovementCopy.lessTitle,
                  systemImage: "exclamationmark.triangle.fill")
                .font(.title3.weight(.semibold))
                .foregroundStyle(Color.aimDanger)
            Text(reason == .under ? FetalMovementCopy.underBody : FetalMovementCopy.lessBody)
                .font(.body).foregroundStyle(Color.aimTextPrimary)
            askAgentButton(reason == .under
                           ? "我数胎动 2 小时不到 10 次，现在该怎么办？"
                           : "我感觉胎动比平时少了，现在该怎么办？")
            FetalMovementRetryButton(busy: saving)
            Button("我知道了", action: onClose).buttonStyle(.borderedProminent)
        }
        .padding()
        .background(Color.aimDangerSoft, in: RoundedRectangle(cornerRadius: AimMetrics.radiusCard))
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("fetal-movement-safety")
    }

    private func askAgentButton(_ question: String) -> some View {
        Button {
            agentStore.prepareAnalysis(question, context: AgentContext(title: "胎动", summary: "刚刚数胎动"))
            showingAgent = true
        } label: {
            Label("问问 AIM", systemImage: "wand.and.sparkles")
        }
    }

    private static func clock(_ seconds: TimeInterval) -> String {
        let total = Int(seconds)
        return String(format: "%02d:%02d", total / 60, total % 60)
    }
}

/// 「有 N 次没保存上，重试」。保存进行中显示进度，不提示没保存上，也不给重复点。
struct FetalMovementRetryButton: View {
    @Environment(FetalMovementStore.self) private var store
    /// 调用方自己发起的保存还在进行（例如刚结束的这次）。
    var busy = false

    var body: some View {
        if busy || store.isSaving {
            ProgressView("正在保存…")
        } else if !store.unsaved.isEmpty {
            Button("有 \(store.unsaved.count) 次没保存上，重试") { Task { await store.saveUnsaved() } }
                .accessibilityIdentifier("fetal-movement-retry")
        }
    }
}

/// 计数页内置的说明。详细内容在资料库「孕期百科 · 胎动与数胎动」。
struct FetalMovementGuideView: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                Section("怎么数") { Text(FetalMovementCopy.howTo) }
                Section("什么时候联系医院") {
                    Text(FetalMovementCopy.underRule)
                    Text(FetalMovementCopy.mostImportant).foregroundStyle(Color.aimDanger)
                }
                Section { Text(FetalMovementCopy.doctorFirst) }
                Section { Text("更多说明见资料库 · 孕期百科「胎动与数胎动」。").font(.footnote) }
            }
            .navigationTitle("怎么数胎动")
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("好") { dismiss() } } }
        }
    }
}
