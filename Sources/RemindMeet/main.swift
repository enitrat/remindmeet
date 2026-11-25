import AppKit
import EventKit

private let leadTime: TimeInterval = 60
private let snoozeDuration: TimeInterval = 60
private let maxSnoozes = 2

private struct MeetingState {
    var snoozes = 0
    var snoozedUntil: Date?
    var meetOpened = false
    /// Joined or skipped: the panel never comes back for this occurrence.
    var done = false
}

final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private let store = EKEventStore()
    private var statusItem: NSStatusItem!
    private var panel: PanelController!
    private var states: [String: MeetingState] = [:]
    private var nextMeeting: Meeting?
    private var testMeeting: Meeting?
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
        var meetings = hasAccess ? fetchMeetings(store: store, around: now) : []
        if let testMeeting { meetings.append(testMeeting) }

        let liveIDs = Set(meetings.map(\.id))
        states = states.filter { liveIDs.contains($0.key) }

        nextMeeting = meetings.filter { $0.start > now }.min { $0.start < $1.start }

        let active = meetings
            .filter { now >= $0.start - leadTime && now < $0.end && !(states[$0.id]?.done ?? false) }
            .min { $0.start < $1.start }

        guard let meeting = active else {
            panel.hide()
            return
        }
        if let shown = panel.shownMeetingID, shown != meeting.id { panel.hide() }

        var state = states[meeting.id, default: MeetingState()]
        if now >= meeting.start, !state.meetOpened, let url = meeting.url {
            NSWorkspace.shared.open(url)
            state.meetOpened = true
        }
        states[meeting.id] = state

        if let until = state.snoozedUntil, now < until {
            panel.hide()
        } else {
            panel.show(meeting, snoozesLeft: maxSnoozes - state.snoozes, meetOpened: state.meetOpened, now: now)
        }
    }

    private func updateShownState(_ change: (inout MeetingState) -> Void) {
        guard let id = panel.model.meeting?.id else { return }
        change(&states[id, default: MeetingState()])
        panel.hide()
        tick()
    }

    private func join() {
        guard let meeting = panel.model.meeting else { return }
        updateShownState { state in
            if !state.meetOpened, let url = meeting.url { NSWorkspace.shared.open(url) }
            state.meetOpened = true
            state.done = true
        }
    }

    private func snooze() {
        updateShownState { state in
            guard state.snoozes < maxSnoozes else { return }
            state.snoozes += 1
            state.snoozedUntil = Date().addingTimeInterval(snoozeDuration)
        }
    }

    private func skip() {
        updateShownState { $0.done = true }
    }

    // MARK: Menu

    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()

        let header: String
        if !hasAccess {
            header = "Pas d'accès au calendrier"
        } else if let next = nextMeeting {
            header = "Prochaine : \(next.title) à \(next.start.formatted(date: .omitted, time: .shortened))"
        } else {
            header = "Aucune réunion dans l'heure"
        }
        menu.addItem(withTitle: header, action: nil, keyEquivalent: "")
        menu.addItem(.separator())

        menu.addItem(withTitle: "Tester le panneau", action: #selector(startTest), keyEquivalent: "").target = self

        menu.addItem(.separator())
        menu.addItem(withTitle: "Quitter", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
    }

    /// A fake meeting starting in 20 s: exercises T-1, snooze and the T0 auto-open on a real Meet URL.
    @objc private func startTest() {
        let start = Date().addingTimeInterval(20)
        testMeeting = Meeting(
            id: "test@\(start.timeIntervalSince1970)",
            title: "Réunion de test",
            start: start,
            end: start.addingTimeInterval(5 * 60),
            url: URL(string: "https://meet.google.com/"),
            calendarName: "Test",
            calendarColor: NSColor.systemBlue.cgColor
        )
        tick()
    }
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.accessory)
app.run()
