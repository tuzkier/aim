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

    static func slow(duration: Int, baseline: Int) -> String {
        "这次用了 \(FetalMovementFormat.duration(duration))，比你平时（约 \(FetalMovementFormat.duration(baseline))）慢了一倍多，胎动可能比平时少。建议尽快联系你的产检医院。"
    }
}

struct FetalMovementCounterView: View {
    @Environment(FetalMovementStore.self) private var store
    let agentStore: AgentStore
    let onClose: () -> Void

    private enum Phase: Equatable {
        case counting
        case finished(FetalMovementCompletion)
        case safety(title: String, body: String)
    }

    @State private var phase: Phase = .counting
    @State private var tapCount = 0
    @State private var ignoredCount = 0
    @State private var confirmingEnd = false
    @State private var showingGuide = false
    @State private var showingAgent = false
    /// 已经调过 `store.start()`。之后 `active` 仍为 nil，说明计数没法开始（例如还没绑定账号与孕期）。
    @State private var startAttempted = false
    /// 正在结束：`finish()` 一开始就清掉 `active`，等待保存期间不能误判成「无法开始」，也不能重复结束。
    @State private var ending = false

    /// 计数阶段却没有进行中的计数，而且不是因为正在结束——给出提示，别留一个点了没反应的大按钮。
    private var unableToStart: Bool {
        phase == .counting && startAttempted && !ending && store.active == nil
    }

    var body: some View {
        NavigationStack {
            Group {
                switch phase {
                case .counting:
                    if unableToStart {
                        unavailable
                    } else if ending {
                        // 保存要等网络；这期间进行中的计数已清掉，别让大按钮显示成 0。
                        ProgressView("正在记录…")
                    } else {
                        counting
                    }
                case let .finished(completion): finished(completion)
                case let .safety(title, body): safety(title: title, body: body)
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
            store.start()
            startAttempted = true
        }
        .sheet(isPresented: $showingGuide) { FetalMovementGuideView() }
        .fullScreenCover(isPresented: $showingAgent) {
            AgentView(store: agentStore) { showingAgent = false }
        }
        .confirmationDialog("现在结束吗？这次会记为未数完。", isPresented: $confirmingEnd, titleVisibility: .visible) {
            Button("结束并记录") { Task { await end() } }
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
                Button {
                    phase = .safety(title: FetalMovementCopy.lessTitle, body: FetalMovementCopy.lessBody)
                } label: {
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
                .sensoryFeedback(.impact(weight: .light), trigger: ignoredCount)
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
                if store.active?.isExpired(at: now) == true { Task { await end() } }
            }
        }
    }

    private func tap() {
        switch store.tap() {
        case .counted: tapCount += 1; ignoredCount = 0
        case .ignored: ignoredCount += 1
        case .reachedTarget: tapCount += 1; Task { await end() }
        case .expired: Task { await end() }
        }
    }

    private func end() async {
        // 到点自动结束与第 10 次点击可能同时触发，只结束一次。
        guard !ending else { return }
        ending = true
        guard let completion = await store.finish() else {
            ending = false
            return
        }
        if completion.result.outcome == .under {
            phase = .safety(title: FetalMovementCopy.underTitle, body: FetalMovementCopy.underBody)
        } else {
            phase = .finished(completion)
        }
    }

    private func finished(_ completion: FetalMovementCompletion) -> some View {
        VStack(alignment: .leading, spacing: AimMetrics.space16) {
            Text(completion.result.outcome == .reached
                 ? "\(completion.result.count) 次，用了 \(FetalMovementFormat.duration(completion.result.durationSeconds))"
                 : "\(completion.result.count) 次 · 未数完")
                .font(.title2.weight(.semibold))
                .foregroundStyle(Color.aimTextPrimary)
            if completion.isSlow, let baseline = completion.baselineSeconds {
                Text(FetalMovementCopy.slow(duration: completion.result.durationSeconds, baseline: baseline))
                    .font(.subheadline)
                    .foregroundStyle(Color.aimAccent)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .aimCard()
                askAgentButton("我数胎动用了 \(FetalMovementFormat.duration(completion.result.durationSeconds))，比平时慢了一倍多，现在该怎么办？")
            }
            Text(FetalMovementCopy.recordedNote).font(.footnote).foregroundStyle(Color.aimTextSecondary)
            // 以队列为准：重试成功后按钮随之消失；这次已保存但队列里还有旧的，也给重试。
            if !store.unsaved.isEmpty { retryButton }
            Button("完成", action: onClose)
                .buttonStyle(.borderedProminent)
                .accessibilityIdentifier("fetal-movement-done")
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("fetal-movement-finished")
    }

    private func safety(title: String, body: String) -> some View {
        VStack(alignment: .leading, spacing: AimMetrics.space16) {
            Label(title, systemImage: "exclamationmark.triangle.fill")
                .font(.title3.weight(.semibold))
                .foregroundStyle(Color.aimDanger)
            Text(body).font(.body).foregroundStyle(Color.aimTextPrimary)
            askAgentButton("我感觉胎动比平时少了，现在该怎么办？")
            if !store.unsaved.isEmpty { retryButton }
            Button("我知道了", action: onClose).buttonStyle(.borderedProminent)
        }
        .padding()
        .background(Color.aimDangerSoft, in: RoundedRectangle(cornerRadius: AimMetrics.radiusCard))
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("fetal-movement-safety")
    }

    private var retryButton: some View {
        Button("没保存上，重试") { Task { await store.saveUnsaved() } }
            .accessibilityIdentifier("fetal-movement-retry")
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
