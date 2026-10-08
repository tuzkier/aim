import SwiftUI

/// 本周详情：宝宝多大、宝宝和妈妈这周的变化、这周可以做的事。可以左右翻到第 4–42 周。
struct WeekDetailView: View {
    @Bindable var store: HomeDashboardStore
    let agentStore: AgentStore
    @State private var week: Int
    @State private var added: Set<String> = []
    @State private var showingAgent = false
    @State private var toast: AimToastMessage?

    init(store: HomeDashboardStore, initialWeek: Int, agentStore: AgentStore) {
        self.store = store
        self.agentStore = agentStore
        _week = State(initialValue: min(max(initialWeek, WeeklyContentBook.firstWeek), WeeklyContentBook.lastWeek))
    }

    private var currentWeek: Int? { store.pregnancy?.weeks }

    var body: some View {
        VStack(spacing: 0) {
            weekSwitcher
            TabView(selection: $week) {
                ForEach(WeeklyContentBook.firstWeek...WeeklyContentBook.lastWeek, id: \.self) { number in
                    page(for: number).tag(number)
                }
            }
            .tabViewStyle(.page(indexDisplayMode: .never))
        }
        .background(Color.aimCanvas)
        .navigationTitle("第 \(week) 周")
        .navigationBarTitleDisplayMode(.inline)
        .fullScreenCover(isPresented: $showingAgent) {
            AgentView(store: agentStore) { showingAgent = false }
        }
        .aimToast($toast)
    }

    private var weekSwitcher: some View {
        HStack(spacing: AimMetrics.space12) {
            Button { withAnimation { week = max(WeeklyContentBook.firstWeek, week - 1) } } label: {
                Image(systemName: "chevron.left")
            }
            .disabled(week <= WeeklyContentBook.firstWeek)
            .accessibilityLabel("上一周")
            ForEach([week - 1, week, week + 1], id: \.self) { number in
                if (WeeklyContentBook.firstWeek...WeeklyContentBook.lastWeek).contains(number) {
                    Button { withAnimation { week = number } } label: {
                        Text(number == week ? "\(number) 周" : "\(number)")
                            .font(.subheadline.weight(number == week ? .semibold : .regular))
                            .padding(.horizontal, 12).padding(.vertical, 5)
                            .background(number == week ? Color.aimAccentSoft : Color.clear, in: Capsule())
                            .foregroundStyle(number == week ? Color.aimAccent : Color.aimTextSecondary)
                    }
                    .buttonStyle(.plain)
                } else {
                    Text("").frame(width: 36)
                }
            }
            Button { withAnimation { week = min(WeeklyContentBook.lastWeek, week + 1) } } label: {
                Image(systemName: "chevron.right")
            }
            .disabled(week >= WeeklyContentBook.lastWeek)
            .accessibilityLabel("下一周")
            .accessibilityIdentifier("week-next")
        }
        .foregroundStyle(Color.aimTextSecondary)
        .padding(.vertical, AimMetrics.space8)
    }

    private func page(for number: Int) -> some View {
        let content = store.book?.content(forWeek: number) ?? WeeklyContentBook.earlyFallback
        return ScrollView {
            VStack(spacing: AimMetrics.space12) {
                VStack(spacing: 6) {
                    Text(content.fruit).font(.system(size: 72))
                    Text("宝宝像\(content.fruitName)").font(.title3.weight(.semibold))
                    if let size = content.detailedSizeText {
                        Text(size)
                            .font(.subheadline).foregroundStyle(Color.aimTextSecondary)
                    }
                    if number == currentWeek {
                        Text("这是你现在所在的一周").font(.caption).foregroundStyle(Color.aimAccent)
                    }
                }
                .padding(.vertical, AimMetrics.space12)

                section("figure.and.child.holdinghands", "宝宝", content.baby)
                section("heart", "妈妈", content.mom)

                VStack(alignment: .leading, spacing: AimMetrics.space8) {
                    Label("这周可以做", systemImage: "checklist").font(.headline).foregroundStyle(Color.aimTextPrimary)
                    ForEach(content.tips, id: \.self) { tip in
                        HStack {
                            Text("· \(tip)").font(.subheadline).foregroundStyle(Color.aimTextPrimary)
                            Spacer()
                            Button(added.contains(tip) ? "已加入" : "加进待办") { Task { await addTask(tip) } }
                                .font(.caption)
                                .foregroundStyle(added.contains(tip) ? Color.aimTextTertiary : Color.aimAccent)
                                .disabled(added.contains(tip))
                                .buttonStyle(.plain)
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(AimMetrics.space16)
                .background(Color.aimSurface, in: RoundedRectangle(cornerRadius: AimMetrics.radiusCard))

                Button { askAgent(week: number) } label: {
                    HStack {
                        Image(systemName: "wand.and.sparkles").foregroundStyle(Color.aimAccent)
                        Text("关于这一周，问问 AIM").font(.subheadline).foregroundStyle(Color.aimTextPrimary)
                        Spacer()
                        Image(systemName: "chevron.right").font(.caption).foregroundStyle(Color.aimTextTertiary)
                    }
                    .padding(AimMetrics.space16)
                    .background(Color.aimSurface, in: RoundedRectangle(cornerRadius: AimMetrics.radiusCard))
                }
                .buttonStyle(.plain)

                if let book = store.book {
                    Text("内容参考：\(book.source)。\(book.reviewedAt) 核对。数值为平均水平，个体差异很大，以产检结果为准。")
                        .font(.caption2)
                        .foregroundStyle(Color.aimTextTertiary)
                        .padding(.horizontal, AimMetrics.space4)
                }
            }
            .padding(.horizontal, AimMetrics.space16)
            .padding(.bottom, AimMetrics.space28)
        }
    }

    private func section(_ symbol: String, _ title: String, _ text: String) -> some View {
        VStack(alignment: .leading, spacing: AimMetrics.space8) {
            Label(title, systemImage: symbol).font(.headline).foregroundStyle(Color.aimTextPrimary)
            Text(text).font(.subheadline).foregroundStyle(Color.aimTextPrimary).fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(AimMetrics.space16)
        .background(Color.aimSurface, in: RoundedRectangle(cornerRadius: AimMetrics.radiusCard))
    }

    private func addTask(_ tip: String) async {
        guard let repository = store.repository else { return }
        do {
            _ = try await repository.createTask(title: tip, description: nil, dueAt: nil, assignedMemberID: nil)
            added.insert(tip)
            toast = AimToastMessage(text: "已加进待办", undoTitle: "", accessibilityIdentifier: "week-task-added")
            NotificationCenter.default.post(name: .aimDataChanged, object: nil, userInfo: ["kinds": ["task"]])
        } catch {
            toast = AimToastMessage(text: "没加上，稍后再试", undoTitle: "", accessibilityIdentifier: "week-task-failed")
        }
    }

    private func askAgent(week number: Int) {
        agentStore.prepareAnalysis(
            "我现在在看孕 \(number) 周的内容，这周需要注意什么？",
            context: AgentContext(title: "孕 \(number) 周", summary: "本周详情"))
        showingAgent = true
    }
}
