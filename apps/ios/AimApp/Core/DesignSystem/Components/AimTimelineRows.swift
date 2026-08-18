import SwiftUI

struct AimSourceBadge: View {
    var body: some View {
        Text("Agent 调整")
            .font(.footnote)
            .foregroundStyle(Color.aimAccent)
    }
}

struct AimTaskRow: View {
    let task: TaskItem
    var assigneeName: String?
    var onToggle: (() -> Void)?

    private var isDone: Bool { task.status == .completed }

    var body: some View {
        HStack(alignment: .top, spacing: AimMetrics.space12) {
            Button { onToggle?() } label: { checkbox }
                .buttonStyle(.plain)
                .disabled(onToggle == nil)
                .accessibilityLabel(isDone ? "已完成" : "未完成")

            VStack(alignment: .leading, spacing: AimMetrics.space4) {
                Text(task.title)
                    .font(.body)
                    .foregroundStyle(isDone ? Color.aimTextTertiary : Color.aimTextPrimary)
                    .strikethrough(isDone, color: Color.aimTextTertiary)
                meta
            }
            Spacer(minLength: 0)
        }
        .padding(.vertical, AimMetrics.space8)
        .accessibilityElement(children: .combine)
    }

    @ViewBuilder
    private var checkbox: some View {
        if isDone {
            Image(systemName: "checkmark.circle.fill")
                .font(.body)
                .foregroundStyle(Color.aimSuccess)
        } else {
            Circle()
                .stroke(Color.aimRail, lineWidth: AimMetrics.railDotStroke)
                .frame(width: AimMetrics.checkboxSize, height: AimMetrics.checkboxSize)
        }
    }

    @ViewBuilder
    private var meta: some View {
        let parts = metaParts
        if !parts.isEmpty || task.isAgentChanged {
            HStack(spacing: AimMetrics.space4) {
                if !parts.isEmpty {
                    Text(parts.joined(separator: " · "))
                        .font(.footnote)
                        .foregroundStyle(Color.aimTextSecondary)
                }
                if task.isAgentChanged {
                    if !parts.isEmpty {
                        Text("·").font(.footnote).foregroundStyle(Color.aimTextSecondary)
                    }
                    AimSourceBadge()
                }
            }
        }
    }

    private var metaParts: [String] {
        var parts: [String] = []
        if let assigneeName { parts.append(assigneeName) }
        if let date = task.dueAt ?? task.scheduledFor {
            parts.append(date.formatted(date: .abbreviated, time: .shortened))
        }
        return parts
    }
}

struct AimRecordRow: View {
    let record: RecordItem

    var body: some View {
        HStack(alignment: .top, spacing: AimMetrics.space12) {
            Image(systemName: record.type.symbolName)
                .font(.body)
                .foregroundStyle(Color.aimAccent)
                .frame(width: AimMetrics.checkboxSize)

            VStack(alignment: .leading, spacing: AimMetrics.space4) {
                Text(record.displayTitle)
                    .font(.body)
                    .foregroundStyle(Color.aimTextPrimary)
                Text("\(record.type.displayName) · \(record.displaySummary)")
                    .font(.footnote)
                    .foregroundStyle(Color.aimTextSecondary)
                    .lineLimit(2)
            }
            Spacer(minLength: 0)
        }
        .padding(.vertical, AimMetrics.space8)
        .accessibilityElement(children: .combine)
    }
}
