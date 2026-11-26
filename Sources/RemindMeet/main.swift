import AppKit
import EventKit

private let leadTime: TimeInterval = 60
private let snoozeDuration: TimeInterval = 60
private let maxSnoozes = 2

private struct MeetingState {
    enum Outcome { case joined, skipped }

    var snoozes = 0
    var snoozedUntil: Date?
    var meetOpened = false
    /// Once set, the panel never comes back for this occurrence.
    var outcome: Outcome?
}

final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private let store = EKEventStore()
    private var statusItem: NSStatusItem!
    private var panel: PanelController!
    private var states: [String: MeetingState] = [:]
    private var hasAccess = false

    func applicationDidFinishLaunching(_ notification: Notification) {
        panel = PanelController(
            onJoin: { [unowned self] in join() },
            onSnooze: { [unowned self] in snooze() },
            onSkip: { [unowned self] in skip() }
        )

        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        statusItem.button?.image = NSImage(systemSymbolName: "calendar.badge.clock", accessibilityDescription: "RemindMeet")
        let menu = NSMenu()
        menu.delegate = self
        statusItem.menu = menu

        store.requestFullAccessToEvents { granted, _ in
            DispatchQueue.main.async { self.hasAccess = granted }
        }

        let timer = Timer(timeInterval: 1, repeats: true) { [unowned self] _ in tick() }
        RunLoop.main.add(timer, forMode: .common)
    }

    // MARK: Scheduling

    private func tick() {
        let now = Date()
        let window = DateInterval(start: now.addingTimeInterval(-6 * 3600), end: now.addingTimeInterval(3600))
        let meetings = hasAccess ? fetchMeetings(store: store, in: window) : []

        let liveIDs = Set(meetings.map(\.id))
        states = states.filter { liveIDs.contains($0.key) }

        let active = meetings
            .filter { now >= $0.start - leadTime && now < $0.end && states[$0.id]?.outcome == nil }
            .min { $0.start < $1.start }

        guard let meeting = active else {
            showNothingLive(now: now)
            return
        }

        var state = states[meeting.id, default: MeetingState()]
        if now >= meeting.start, !state.meetOpened, let url = meeting.url {
            NSWorkspace.shared.open(url)
            state.meetOpened = true
        }
        states[meeting.id] = state

        if let until = state.snoozedUntil, now < until {
            showNothingLive(now: now)
        } else {
            panel.show(
                Reminder(meeting: meeting, session: .live),
                snoozesLeft: maxSnoozes - state.snoozes,
                meetOpened: state.meetOpened,
                now: now
            )
        }
    }

    /// A preview stays up and keeps counting; a live reminder that is no longer due goes away.
    private func showNothingLive(now: Date) {
        if panel.model.reminder?.session == .live {
            panel.hide()
        } else {
            panel.model.now = now
        }
    }

    /// A preview closes without touching reminder state.
    private func respond(_ change: (inout MeetingState) -> Void) {
        guard let reminder = panel.model.reminder else { return }
        panel.hide()
        guard reminder.session == .live else { return }
        change(&states[reminder.meeting.id, default: MeetingState()])
        tick()
    }

    private func join() {
        guard let reminder = panel.model.reminder else { return }
        if reminder.session == .preview, let url = reminder.meeting.url {
            NSWorkspace.shared.open(url)
        }
        respond { state in
            if !state.meetOpened, let url = reminder.meeting.url { NSWorkspace.shared.open(url) }
            state.meetOpened = true
            state.outcome = .joined
        }
    }

    private func snooze() {
        respond { state in
            guard state.snoozes < maxSnoozes else { return }
            state.snoozes += 1
            state.snoozedUntil = Date().addingTimeInterval(snoozeDuration)
        }
    }

    private func skip() {
        respond { $0.outcome = .skipped }
    }

    // MARK: Menu

    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()
        let now = Date()
        let today = Calendar.current.dateInterval(of: .day, for: now)!

        menu.addItem(.sectionHeader(
            title: "Today · \(now.formatted(.dateTime.weekday(.abbreviated).day().month(.abbreviated)))"
        ))

        if !hasAccess {
            menu.addItem(withTitle: "No calendar access", action: nil, keyEquivalent: "")
        } else {
            let meetings = fetchMeetings(store: store, in: today)
            if meetings.isEmpty {
                menu.addItem(withTitle: "No meetings today", action: nil, keyEquivalent: "")
            }
            for meeting in meetings {
                menu.addItem(menuItem(for: meeting, now: now))
            }
        }

        menu.addItem(.separator())
        menu.addItem(withTitle: "Quit", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
    }

    private func menuItem(for meeting: Meeting, now: Date) -> NSMenuItem {
        let item = NSMenuItem(title: "", action: #selector(preview(_:)), keyEquivalent: "")
        item.target = self
        item.representedObject = meeting

        let past = now >= meeting.end
        var title = "\(meeting.start.formatted(date: .omitted, time: .shortened))  \(meeting.title)"
        if #available(macOS 14.4, *) {
            item.subtitle = status(of: meeting, now: now)
        } else {
            title += "  ·  \(status(of: meeting, now: now))"
        }
        item.attributedTitle = NSAttributedString(string: title, attributes: [
            .font: NSFont.menuFont(ofSize: 0),
            .foregroundColor: past ? NSColor.secondaryLabelColor : NSColor.labelColor,
        ])
        item.image = calendarDot(meeting.calendarColor, dimmed: past)
        return item
    }

    private func status(of meeting: Meeting, now: Date) -> String {
        let status: String
        switch states[meeting.id]?.outcome {
        case .joined: status = "Joined"
        case .skipped: status = "Skipped"
        case nil:
            if now >= meeting.end {
                status = "Ended"
            } else if now >= meeting.start {
                status = "Now"
            } else {
                let minutes = Int((meeting.start.timeIntervalSince(now) / 60).rounded(.up))
                status = minutes < 60 ? "in \(minutes) min" : "in \(minutes / 60) h \(minutes % 60) min"
            }
        }
        return meeting.url == nil ? "\(status) · No video link" : status
    }

    private func calendarDot(_ color: CGColor?, dimmed: Bool) -> NSImage {
        let fill = color.flatMap(NSColor.init(cgColor:)) ?? .tertiaryLabelColor
        return NSImage(size: NSSize(width: 10, height: 10), flipped: false) { rect in
            fill.withAlphaComponent(dimmed ? 0.45 : 1).setFill()
            NSBezierPath(ovalIn: rect.insetBy(dx: 1, dy: 1)).fill()
            return true
        }
    }

    @objc private func preview(_ sender: NSMenuItem) {
        guard let meeting = sender.representedObject as? Meeting else { return }
        panel.show(
            Reminder(meeting: meeting, session: .preview),
            snoozesLeft: maxSnoozes - (states[meeting.id]?.snoozes ?? 0),
            meetOpened: false,
            now: Date()
        )
    }
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.accessory)
app.run()
