import SwiftUI

/// 孕期日期录入。登录后没有孕期档案时作为准入门槛整屏呈现——填完才能进主界面。
///
/// 日期不预填：`model.selectedDate` 初值为 `nil`，用户必须主动选择才能保存。
/// 详见 `PregnancySetupModel` 的说明。
struct PregnancySetupView: View {
    @Environment(AppSessionStore.self) private var session
    @State private var model = PregnancySetupModel()
    @State private var invitations = InvitationPromptStore()
    @State private var deciding: MyInvitation?

    private var repository: BusinessRepository { BusinessRepository(environment: session.environment) }

    var body: some View {
        NavigationStack {
            Form {
                if let notice = session.familyNotice {
                    Section {
                        Label(notice, systemImage: "info.circle")
                            .foregroundStyle(Color.aimTextSecondary)
                    }
                }
                // 新注册的人一定先到这里：家人发来的邀请直接列在最上面，不用先建一份自己的孕期。
                if !invitations.invitations.isEmpty {
                    Section {
                        ForEach(invitations.invitations) { invitation in
                            Button { deciding = invitation } label: {
                                VStack(alignment: .leading, spacing: 3) {
                                    Text("\(invitation.inviterName)邀请你加入「\(invitation.familyName)」")
                                        .foregroundStyle(Color.aimTextPrimary)
                                    Text("身份：\(invitation.role.displayName)")
                                        .font(.caption)
                                        .foregroundStyle(Color.aimTextSecondary)
                                }
                            }
                            .accessibilityIdentifier("setup-invitation-row")
                        }
                    } header: {
                        Text("家人邀请你加入")
                    } footer: {
                        Text("加入后共享对方的孕期，不用再填写下面的日期。")
                    }
                }
                Section {
                    Picker("我知道的是", selection: $model.dateMode) {
                        ForEach(PregnancyDateMode.allCases, id: \.self) { mode in
                            Text(mode.title).tag(mode)
                        }
                    }

                    if model.isPickingDate {
                        DatePicker(
                            model.dateMode.dateTitle,
                            selection: Binding(
                                get: { model.selectedDate ?? model.displayAnchor },
                                set: { model.selectedDate = $0 },
                            ),
                            in: model.dateMode.dateRange,
                            displayedComponents: .date,
                        )
                        .datePickerStyle(.wheel)
                        .accessibilityIdentifier("pregnancy-setup-date-picker")

                        if let selected = model.selectedDate {
                            Text(model.dateMode.calculatedSummary(for: selected))
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        } else {
                            Text("滑动选择你的\(model.dateMode.title)")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                    } else {
                        Button("选择\(model.dateMode.title)") { model.beginPickingDate() }
                            .accessibilityIdentifier("pregnancy-setup-choose-date")
                    }
                } footer: {
                    Text("两种日期都按孕 40 周（280 天）换算。填写后才能生成对应孕周的计划。")
                }

                if let errorMessage = model.errorMessage {
                    Section { Text(errorMessage).foregroundStyle(.red) }
                }

                Section {
                    Button {
                        Task { await save() }
                    } label: {
                        if model.isSubmitting {
                            ProgressView().frame(maxWidth: .infinity)
                        } else {
                            Text("保存并生成计划").frame(maxWidth: .infinity)
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(!model.canSave)
                    .accessibilityIdentifier("pregnancy-setup-save")
                }
            }
            .navigationTitle("补充孕期信息")
            .onChange(of: model.dateMode) { _, mode in
                model.modeDidChange(to: mode)
            }
            .task { await invitations.check(using: repository) }
            .sheet(item: $deciding) { invitation in
                InvitationDecisionSheet(invitation: invitation, repository: repository) {
                    Task { await invitations.check(using: repository) }
                }
            }
            .onDisappear { session.familyNotice = nil }
        }
    }

    private func save() async {
        guard let dueDate = model.resolvedDueDate else { return }
        guard session.familyID != nil else {
            model.errorMessage = "家庭信息还没有准备好，请稍后重试。"
            return
        }
        model.isSubmitting = true
        model.errorMessage = nil
        defer { model.isSubmitting = false }

        do {
            let repository = BusinessRepository(environment: session.environment)
            let pregnancyID = try await repository.createPregnancy(dueDate: dueDate)
            session.setPregnancyID(pregnancyID)
        } catch {
            model.errorMessage = error.localizedDescription
        }
    }
}

enum PregnancyDateMode: String, CaseIterable, Hashable {
    case dueDate
    case lastMenstrualPeriod

    var title: String {
        switch self {
        case .dueDate: return "预产期"
        case .lastMenstrualPeriod: return "末次月经"
        }
    }

    var dateTitle: String { title }

    var dateRange: ClosedRange<Date> {
        let calendar = PregnancyDateCalculator.calendar
        switch self {
        case .dueDate:
            return Date()...calendar.date(byAdding: .year, value: 1, to: .now)!
        case .lastMenstrualPeriod:
            return calendar.date(byAdding: .year, value: -1, to: .now)!...Date()
        }
    }

    func dueDate(from selectedDate: Date) -> Date {
        switch self {
        case .dueDate: return selectedDate
        case .lastMenstrualPeriod:
            return PregnancyDateCalculator.dueDate(fromLastMenstrualPeriod: selectedDate)
        }
    }

    func calculatedSummary(for selectedDate: Date) -> String {
        let calculatedDate: Date
        switch self {
        case .dueDate:
            calculatedDate = PregnancyDateCalculator.lastMenstrualPeriod(fromDueDate: selectedDate)
        case .lastMenstrualPeriod:
            calculatedDate = PregnancyDateCalculator.dueDate(fromLastMenstrualPeriod: selectedDate)
        }
        let formatter = DateFormatter()
        formatter.calendar = PregnancyDateCalculator.calendar
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.dateFormat = "yyyy年M月d日"
        return "对应的\(self == .dueDate ? "末次月经" : "预产期")：\(formatter.string(from: calculatedDate))"
    }
}

enum PregnancyDateCalculator {
    static let standardGestationDays = 280

    static var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = .current
        return calendar
    }

    static func dueDate(fromLastMenstrualPeriod date: Date) -> Date {
        calendar.date(byAdding: .day, value: standardGestationDays, to: date)!
    }

    static func lastMenstrualPeriod(fromDueDate date: Date) -> Date {
        calendar.date(byAdding: .day, value: -standardGestationDays, to: date)!
    }
}
