import SwiftUI

/// 家庭页底部的「家庭动态」：谁做了什么，新的在前，滑到底继续加载更早的。
struct FamilyActivitySection: View {
    @Environment(AgentDestinations.self) private var destinations: AgentDestinations?
    @Bindable var store: FamilyStore
    /// 解析出要打开的原生页面后交给家庭页推入（navigationDestination 不能挂在 List 里）。
    let onOpen: (AgentDestination) -> Void
    @State private var opening: String?

    var body: some View {
        Section("家庭动态") {
            if store.activity.isEmpty {
                Text(store.isLoadingActivity ? "正在加载…" : "还没有动态。完成待办、记下记录后，家里人都能在这里看到。")
                    .font(.subheadline)
                    .foregroundStyle(Color.aimTextSecondary)
            }
            ForEach(store.activity) { item in
                row(item)
                    .onAppear {
                        if item.id == store.activity.last?.id {
                            Task { await store.loadMoreActivity() }
                        }
                    }
            }
            if store.isLoadingActivity && !store.activity.isEmpty {
                ProgressView().frame(maxWidth: .infinity)
            }
        }
    }

    @ViewBuilder
    private func row(_ item: FamilyActivityItem) -> some View {
        // 成员进出、改预产期没有可打开的页面：照常显示，不做成禁用的按钮（禁用态会整行发灰）。
        if item.targetID != nil && !item.targetDeleted {
            Button { Task { await open(item) } } label: { content(item) }
                .buttonStyle(.plain)
                .accessibilityIdentifier("family-activity-row")
        } else {
            content(item).accessibilityIdentifier("family-activity-row")
        }
    }

    private func content(_ item: FamilyActivityItem) -> some View {
        HStack(alignment: .top, spacing: AimMetrics.space12) {
            Image(systemName: icon(for: item.kind))
                .font(.system(size: 15))
                .foregroundStyle(item.kind == .taskCompleted ? Color.aimSuccess : Color.aimTextSecondary)
                .frame(width: 22)
            VStack(alignment: .leading, spacing: 2) {
                Text(item.sentence)
                    .font(.subheadline)
                    .foregroundStyle(item.targetDeleted ? Color.aimTextTertiary : Color.aimTextPrimary)
                    .strikethrough(item.targetDeleted)
                    .multilineTextAlignment(.leading)
                Text(item.createdAt.formatted(.relative(presentation: .named).locale(Locale(identifier: "zh_CN"))))
                    .font(.caption)
                    .foregroundStyle(Color.aimTextTertiary)
            }
            Spacer(minLength: 0)
            if opening == item.id {
                ProgressView()
            }
        }
        .contentShape(Rectangle())
    }

    private func icon(for kind: FamilyActivityItem.Kind) -> String {
        switch kind {
        case .taskCreated: "plus.circle"
        case .taskCompleted: "checkmark.circle"
        case .recordCreated: "note.text"
        case .memberJoined: "person.badge.plus"
        case .memberLeft, .memberRemoved: "person.badge.minus"
        case .dueDateChanged: "calendar"
        case .unknown: "circle"
        }
    }

    private func open(_ item: FamilyActivityItem) async {
        guard let id = item.targetID, let destinations else { return }
        opening = item.id
        defer { opening = nil }
        let route: AgentWebRoute = item.targetType == "record" ? .record(id) : .task(id)
        if let target = await destinations.resolve(route) { onOpen(target) }
    }
}
