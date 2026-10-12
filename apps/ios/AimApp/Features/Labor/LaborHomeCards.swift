import SwiftUI

/// 首页置顶的去医院横幅：24 小时内家里有人出发去医院了。规格 6.4。
struct LaborBannerCard: View {
    let record: RecordItem
    let actorName: String
    let isMine: Bool
    let onOpen: () -> Void
    let onWithdraw: () -> Void
    let onDismiss: () -> Void
    @State private var confirmingWithdraw = false

    var body: some View {
        VStack(alignment: .leading, spacing: AimMetrics.space8) {
            Button(action: onOpen) {
                HStack(alignment: .top) {
                    Image(systemName: "car.fill")
                    Text(HospitalTrip.bannerText(record, actorName: actorName))
                        .font(.headline)
                        .multilineTextAlignment(.leading)
                    Spacer()
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("home-hospital-trip-banner")
            HStack {
                Spacer()
                if isMine {
                    Button("说错了，撤回") { confirmingWithdraw = true }
                        .accessibilityIdentifier("home-hospital-trip-withdraw")
                } else {
                    Button("知道了", action: onDismiss)
                        .accessibilityIdentifier("home-hospital-trip-dismiss")
                }
            }
            .font(.subheadline)
        }
        .foregroundStyle(Color.aimTextOnAccent)
        .padding(AimMetrics.space16)
        .background(Color.aimAccent, in: RoundedRectangle(cornerRadius: AimMetrics.radiusCard))
        .confirmationDialog("撤回这条？", isPresented: $confirmingWithdraw, titleVisibility: .visible) {
            Button("撤回", role: .destructive, action: onWithdraw)
            Button("取消", role: .cancel) {}
        } message: {
            Text("家人那边的横幅和动态也会一起消失。")
        }
    }
}

/// 本机有进行中的宫缩计时：首页置顶显示，点进计时页。
struct ContractionActiveCard: View {
    @Environment(ContractionStore.self) private var store
    let onOpen: () -> Void

    var body: some View {
        SwiftUI.TimelineView(.periodic(from: .now, by: 1)) { _ in
            Button(action: onOpen) {
                HStack {
                    VStack(alignment: .leading, spacing: AimMetrics.space4) {
                        Text("宫缩计时中").font(.headline).foregroundStyle(Color.aimTextPrimary)
                        Text(subtitle).font(.subheadline).foregroundStyle(Color.aimTextSecondary)
                    }
                    Spacer()
                    Image(systemName: "chevron.right").foregroundStyle(Color.aimTextTertiary)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .aimCard()
            .accessibilityIdentifier("home-contraction-active")
        }
    }

    private var subtitle: String {
        guard let status = store.status else { return "" }
        var parts = [LaborCopy.stageTitle(status.stage)]
        if let summary = status.summary {
            parts.append("\(summary.count) 次")
            if let interval = summary.avgIntervalSeconds { parts.append("约 \(ContractionFormat.seconds(interval))一次") }
        }
        return parts.joined(separator: " · ")
    }
}

/// 孕 36 周起：「分娩准备」入口。
struct LaborPrepCard: View {
    let libraryStore: LibraryStore
    let agentStore: AgentStore

    var body: some View {
        NavigationLink {
            LaborView(libraryStore: libraryStore, agentStore: agentStore)
        } label: {
            HStack {
                VStack(alignment: .leading, spacing: AimMetrics.space4) {
                    Text("分娩准备").font(.headline).foregroundStyle(Color.aimTextPrimary)
                    Text("宫缩计时、什么时候去医院、待产包").font(.subheadline).foregroundStyle(Color.aimTextSecondary)
                    if let progress = LibraryCategoryID.preparationProgress(from: libraryStore.snapshot) {
                        Text(progress).font(.subheadline).foregroundStyle(Color.aimTextSecondary)
                    }
                }
                Spacer()
                Image(systemName: "chevron.right").foregroundStyle(Color.aimTextTertiary)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .aimCard()
        .accessibilityIdentifier("home-labor-card")
    }
}
