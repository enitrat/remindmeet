import EventKit
import Foundation

struct Meeting: Equatable {
    /// eventIdentifier is shared by every occurrence of a recurring event, so the start date is part of the id.
    let id: String
    let title: String
    let start: Date
    let end: Date
    let url: URL?
    let calendarName: String
    let calendarColor: CGColor?
}

private let meetRegex = try! NSRegularExpression(
    pattern: #"https://meet\.google\.com/[a-z]{3}-[a-z]{4}-[a-z]{3}"#
)

func meetURL(in event: EKEvent) -> URL? {
    let haystacks = [event.url?.absoluteString, event.location, event.notes].compactMap { $0 }
    for text in haystacks {
        let range = NSRange(text.startIndex..., in: text)
        if let match = meetRegex.firstMatch(in: text, range: range),
           let swiftRange = Range(match.range, in: text) {
            return URL(string: String(text[swiftRange]))
        }
    }
    return nil
}

/// A meeting is a timed event that has a Meet link or other attendees, and that I haven't declined.
func fetchMeetings(store: EKEventStore, in interval: DateInterval) -> [Meeting] {
    let predicate = store.predicateForEvents(withStart: interval.start, end: interval.end, calendars: nil)
    let events = store.events(matching: predicate).sorted { $0.startDate < $1.startDate }
    return events.compactMap { event in
        guard !event.isAllDay, event.status != .canceled else { return nil }
        let me = event.attendees?.first(where: \.isCurrentUser)
        if me?.participantStatus == .declined { return nil }
        let url = meetURL(in: event)
        guard url != nil || event.hasAttendees else { return nil }
        return Meeting(
            id: "\(event.eventIdentifier ?? event.calendarItemIdentifier)@\(event.startDate.timeIntervalSince1970)",
            title: event.title ?? "Meeting",
            start: event.startDate,
            end: event.endDate,
            url: url,
            calendarName: event.calendar?.title ?? "",
            calendarColor: event.calendar?.cgColor
        )
    }
}
