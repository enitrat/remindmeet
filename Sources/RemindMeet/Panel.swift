import AppKit
import SwiftUI

final class PanelModel: ObservableObject {
    @Published var meeting: Meeting?
    @Published var now = Date()
    @Published var snoozesLeft = 0
    @Published var meetOpened = false
    /// Drives the content's enter scale; the window's own alpha carries the fade.
    @Published var presented = false
}

private final class OverlayPanel: NSPanel {
    override var canBecomeKey: Bool { true }
}

/// Lock-screen-like overlay: the desktop blurred and darkened under the content.
final class PanelController {
    let model = PanelModel()
    private let panel: OverlayPanel
    private var hiding = false

    var shownMeetingID: String? { panel.isVisible && !hiding ? model.meeting?.id : nil }

    init(onJoin: @escaping () -> Void, onSnooze: @escaping () -> Void, onSkip: @escaping () -> Void) {
        panel = OverlayPanel(
            contentRect: .zero,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.level = .screenSaver
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hidesOnDeactivate = false
        panel.appearance = NSAppearance(named: .darkAqua)

        let blur = NSVisualEffectView()
        blur.material = .fullScreenUI
        blur.blendingMode = .behindWindow
        blur.state = .active

        let content = NSHostingView(
            rootView: PanelView(model: model, onJoin: onJoin, onSnooze: onSnooze, onSkip: onSkip)
        )
        content.translatesAutoresizingMaskIntoConstraints = false
        blur.addSubview(content)
        NSLayoutConstraint.activate([
            content.leadingAnchor.constraint(equalTo: blur.leadingAnchor),
            content.trailingAnchor.constraint(equalTo: blur.trailingAnchor),
            content.topAnchor.constraint(equalTo: blur.topAnchor),
            content.bottomAnchor.constraint(equalTo: blur.bottomAnchor),
        ])
        panel.contentView = blur
    }

    func show(_ meeting: Meeting, snoozesLeft: Int, meetOpened: Bool, now: Date) {
        model.meeting = meeting
        model.snoozesLeft = snoozesLeft
        model.meetOpened = meetOpened
        model.now = now
        guard !panel.isVisible || hiding else { return }

        if !panel.isVisible {
            if let screen = NSScreen.main { panel.setFrame(screen.frame, display: true) }
            panel.alphaValue = 0
            model.presented = false
            panel.orderFrontRegardless()
            panel.makeKey()
            NSApp.activate(ignoringOtherApps: true)
        }
        hiding = false
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.3
            context.timingFunction = CAMediaTimingFunction(controlPoints: 0.32, 0.72, 0, 1)
            panel.animator().alphaValue = 1
        }
        withAnimation(reduceMotion ? nil : .timingCurve(0.32, 0.72, 0, 1, duration: 0.3)) {
            model.presented = true
        }
    }

    func hide() {
        guard panel.isVisible, !hiding else { return }
        hiding = true
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.18
            context.timingFunction = CAMediaTimingFunction(name: .easeIn)
            panel.animator().alphaValue = 0
        } completionHandler: { [self] in
            // show() during the fade takes the panel back; leave it on screen then.
            guard hiding else { return }
            hiding = false
            panel.orderOut(nil)
        }
    }

    private var reduceMotion: Bool { NSWorkspace.shared.accessibilityDisplayShouldReduceMotion }
}

// MARK: - View

private let leadTime: TimeInterval = 60

private struct PanelView: View {
    @ObservedObject var model: PanelModel
    let onJoin: () -> Void
    let onSnooze: () -> Void
    let onSkip: () -> Void

    var body: some View {
        ZStack {
            // The blur alone lets a bright wallpaper wash out the white type.
            Color.black.opacity(0.45)
            RadialGradient(
                colors: [.clear, .black.opacity(0.35)],
                center: .center,
                startRadius: 200,
                endRadius: 1100
            )

            if let meeting = model.meeting {
                content(meeting)
                    .scaleEffect(model.presented ? 1 : 0.96)
            }
        }
        .ignoresSafeArea()
    }

    private func content(_ meeting: Meeting) -> some View {
        let late = model.now >= meeting.start
        return VStack(spacing: 0) {
            CalendarLabel(meeting: meeting)

            Countdown(start: meeting.start, now: model.now)
                .padding(.top, 40)

            Text(meeting.title)
                .font(.system(size: 44, weight: .semibold))
                .tracking(-0.6)
                .foregroundStyle(.white)
                .multilineTextAlignment(.center)
                .lineLimit(2)
                .frame(maxWidth: 820)
                .padding(.top, 44)

            Text(linkLabel(meeting))
                .font(.system(size: 15))
                .foregroundStyle(.white.opacity(0.5))
                .padding(.top, 12)

            HStack(spacing: 12) {
                Button(action: onJoin) {
                    HStack(spacing: 10) {
                        if meeting.url != nil, !model.meetOpened {
                            Image(systemName: "video.fill").font(.system(size: 13))
                        }
                        Text(joinLabel(meeting))
                        Text("⏎").font(.system(size: 13)).opacity(0.4)
                    }
                }
                .buttonStyle(PillButtonStyle(kind: .primary))
                .keyboardShortcut(.defaultAction)

                if model.snoozesLeft > 0 {
                    Button(action: onSnooze) {
                        HStack(spacing: 10) {
                            Text("Snooze 1 min")
                            SnoozeDots(left: model.snoozesLeft)
                        }
                    }
                    .buttonStyle(PillButtonStyle(kind: .secondary))
                }
            }
            .padding(.top, 52)

            Button("Skip this meeting", action: onSkip)
                .buttonStyle(PillButtonStyle(kind: .quiet))
                .padding(.top, 12)

            Text(footnote(meeting, late: late))
                .font(.system(size: 13))
                .foregroundStyle(.white.opacity(0.35))
                .padding(.top, 36)
        }
        .padding(48)
    }

    private func joinLabel(_ meeting: Meeting) -> String {
        if meeting.url == nil { return "On my way" }
        return model.meetOpened ? "I'm in" : "Join"
    }

    private func linkLabel(_ meeting: Meeting) -> String {
        let time = "\(meeting.start.formatted(date: .omitted, time: .shortened)) – \(meeting.end.formatted(date: .omitted, time: .shortened))"
        guard let url = meeting.url else { return "\(time)  ·  No video link" }
        let code = url.lastPathComponent
        return code.count > 1 ? "\(time)  ·  meet.google.com/\(code)" : "\(time)  ·  Google Meet"
    }

    private func footnote(_ meeting: Meeting, late: Bool) -> String {
        guard meeting.url != nil else { return " " }
        if model.meetOpened { return "Meet is open in your browser." }
        return late ? " " : "Meet opens on its own at start time."
    }
}

private struct CalendarLabel: View {
    let meeting: Meeting

    var body: some View {
        HStack(spacing: 8) {
            Circle()
                .fill(meeting.calendarColor.map { Color(cgColor: $0) } ?? .white.opacity(0.6))
                .frame(width: 8, height: 8)
            Text(meeting.calendarName.isEmpty ? "Meeting" : meeting.calendarName)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(.white.opacity(0.6))
        }
        .padding(.horizontal, 14)
        .frame(height: 30)
        .background(Capsule().fill(.white.opacity(0.08)))
    }
}

/// The minute before the meeting drains out of the ring; once it has started, the ring
/// turns orange and the clock counts up.
private struct Countdown: View {
    let start: Date
    let now: Date

    var body: some View {
        let delta = start.timeIntervalSince(now)
        let late = delta <= 0
        let progress = late ? 1 : min(max(delta / leadTime, 0), 1)
        let tint: Color = late ? .orange : .white

        ZStack {
            Circle()
                .stroke(.white.opacity(0.1), lineWidth: 3)
            Circle()
                .trim(from: 0, to: progress)
                .stroke(tint, style: StrokeStyle(lineWidth: 3, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .animation(late ? nil : .linear(duration: 1), value: progress)

            VStack(spacing: 6) {
                Text(clock(late ? -delta : delta, late: late))
                    .font(.system(size: 64, weight: .light))
                    .monospacedDigit()
                    .tracking(-1)
                    .foregroundStyle(tint)
                    .contentTransition(.numericText(countsDown: !late))
                    .animation(.easeOut(duration: 0.2), value: Int(delta))
                Text(late ? "since start" : "until start")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(.white.opacity(0.45))
            }
        }
        .frame(width: 220, height: 220)
    }

    private func clock(_ interval: TimeInterval, late: Bool) -> String {
        let total = Int(interval.rounded())
        let text = String(format: "%d:%02d", total / 60, total % 60)
        return late ? "+\(text)" : text
    }
}

private struct SnoozeDots: View {
    let left: Int

    var body: some View {
        HStack(spacing: 4) {
            ForEach(0..<2, id: \.self) { index in
                Circle()
                    .fill(.white.opacity(index < left ? 0.7 : 0.2))
                    .frame(width: 5, height: 5)
            }
        }
        .accessibilityLabel("\(left) left")
    }
}

// MARK: - Buttons

private struct PillButtonStyle: ButtonStyle {
    enum Kind { case primary, secondary, quiet }
    let kind: Kind

    func makeBody(configuration: Configuration) -> some View {
        PillButton(configuration: configuration, kind: kind)
    }
}

private struct PillButton: View {
    let configuration: ButtonStyleConfiguration
    let kind: PillButtonStyle.Kind
    @State private var hovering = false

    var body: some View {
        configuration.label
            .font(.system(size: kind == .quiet ? 14 : 16, weight: kind == .quiet ? .regular : .semibold))
            .foregroundStyle(foreground)
            .padding(.horizontal, kind == .quiet ? 18 : 26)
            .frame(height: kind == .quiet ? 40 : 52)
            .background(Capsule().fill(fill))
            .contentShape(Capsule())
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .animation(.easeOut(duration: 0.15), value: configuration.isPressed)
            .animation(.easeOut(duration: 0.15), value: hovering)
            .onHover { hovering = $0 }
    }

    private var foreground: Color {
        switch kind {
        case .primary: .black
        case .secondary: .white
        case .quiet: .white.opacity(hovering ? 0.85 : 0.5)
        }
    }

    private var fill: Color {
        switch kind {
        case .primary: .white.opacity(hovering ? 0.88 : 1)
        case .secondary: .white.opacity(hovering ? 0.18 : 0.12)
        case .quiet: .white.opacity(hovering ? 0.06 : 0)
        }
    }
}

