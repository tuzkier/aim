import Foundation

enum TimelineEntry: Identifiable, Equatable {
    case task(TaskItem)
    case record(RecordItem)

    var id: String {
        switch self {
        case let .task(item): return "task-\(item.id.uuidString)"
        case let .record(item): return "record-\(item.id.uuidString)"
        }
    }

    var date: Date? {
        switch self {
        case let .task(item): return item.dueAt ?? item.scheduledFor
        case let .record(item): return item.occurredAt
        }
    }
}

struct TimelineWeek: Identifiable, Equatable {
    enum Position: Equatable {
        case past
        case current
        case future
    }

    let week: Int
    let startDate: Date
    let endDate: Date
    let position: Position
    let entries: [TimelineEntry]

    var id: Int { week }

    var openTaskCount: Int {
        entries.reduce(into: 0) { count, entry in
            if case let .task(item) = entry, item.isOpen { count += 1 }
        }
    }
}
