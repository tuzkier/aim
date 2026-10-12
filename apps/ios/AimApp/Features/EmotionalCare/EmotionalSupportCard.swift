import SwiftUI

struct EmotionalSupportCard: View {
    @Environment(\.openURL) private var openURL
    var level: EmotionalSupportLevel?
    var assessmentDate: Date?

    private var isHistorical: Bool {
        assessmentDate.map { EmotionalSchedule.isHistoricalAssessment($0, now: .now) } ?? false
    }

    private var message: String {
        if isHistorical {
            return level == .immediate
                ? "这是一条历史自评，不能代表你现在的情况。如果现在仍有伤害自己的想法或担心安全，请让可信赖的人陪伴，联系专业人员；紧急时去急诊或联系急救。"
                : "这是一条历史自评，不能代表你现在的感受。如果最近持续难受或影响生活，可以寻求专业支持，也可以做一次新的自评。"
        }
        return level?.message ?? "可以和信任的人说说，也可以联系专业人员。不用等自评分数变高才寻求支持。"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: AimMetrics.space12) {
            Label(isHistorical ? "留意现在的感受" : level?.title ?? "不用独自扛着", systemImage: "heart")
                .font(.headline)
            Text(message)
                .font(.subheadline)
            Text("中国大陆的支持入口").font(.caption).foregroundStyle(.secondary)
            Button("联系心理援助 12356") { openURL(URL(string: "tel:12356")!) }
                .accessibilityIdentifier("emotion-contact-support")
            if level == .immediate {
                Button("紧急情况联系急救 120") { openURL(URL(string: "tel:120")!) }
                    .accessibilityIdentifier("emotion-contact-emergency")
            }
            Text("如果热线未接通，或你担心当下安全，请联系当地医院或急救。App 不会替你联系家人或专业人员。")
                .font(.caption).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(AimMetrics.space16)
        .background(level == .immediate ? Color.aimDangerSoft : Color.aimSurface,
                    in: RoundedRectangle(cornerRadius: AimMetrics.radiusCard))
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier(level == .immediate ? "emotion-immediate-support" : "emotion-support")
    }
}
