import Foundation

enum TimelineBuilder {
    static var calendar: Calendar { PregnancyDateCalculator.calendar }

    static func lastMenstrualPeriod(asOf: Date, weeks: Int, days: Int) -> Date {
        calendar.date(byAdding: .day, value: -(weeks * 7 + days), to: asOf) ?? asOf
    }

    static func week(for date: Date, lastMenstrualPeriod: Date) -> Int {
        let start = calendar.startOfDay(for: lastMenstrualPeriod)
        let target = calendar.startOfDay(for: date)
        let days = calendar.dateComponents([.day], from: start, to: target).day ?? 0
        return days / 7
    }

    static func startDate(ofWeek week: Int, lastMenstrualPeriod: Date) -> Date {
        let start = calendar.startOfDay(for: lastMenstrualPeriod)
        return calendar.date(byAdding: .day, value: week * 7, to: start) ?? start
    }

    static func build(
        tasks: [TaskItem],
        records: [RecordItem],
        lastMenstrualPeriod: Date,
        today: Date
    ) -> [TimelineWeek] {
        let currentWeek = week(for: today, lastMenstrualPeriod: lastMenstrualPeriod)

        var buckets: [Int: [TimelineEntry]] = [currentWeek: []]

        for task in tasks {
            let entry = TimelineEntry.task(task)
            let bucket = entry.date.map { week(for: $0, lastMenstrualPeriod: lastMenstrualPeriod) } ?? currentWeek
            buckets[bucket, default: []].append(entry)
        }

        for record in records {
            let entry = TimelineEntry.record(record)
            let bucket = week(for: record.occurredAt, lastMenstrualPeriod: lastMenstrualPeriod)
            buckets[bucket, default: []].append(entry)
        }

        return buckets.keys.sorted().map { weekNumber in
            let start = startDate(ofWeek: weekNumber, lastMenstrualPeriod: lastMenstrualPeriod)
            let end = calendar.date(byAdding: .day, value: 6, to: start) ?? start
            let position: TimelineWeek.Position = weekNumber < currentWeek
                ? .past
                : (weekNumber == currentWeek ? .current : .future)
            let sorted = (buckets[weekNumber] ?? []).sorted {
                ($0.date ?? start) < ($1.date ?? start)
            }
            return TimelineWeek(
                week: weekNumber,
                startDate: start,
                endDate: end,
                position: position,
                entries: sorted
            )
        }
    }
}
