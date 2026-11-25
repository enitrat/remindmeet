import AppKit
import SwiftUI

final class PanelModel: ObservableObject {
    @Published var meeting: Meeting?
    @Published var now = Date()
    @Published var snoozesLeft = 0
    @Published var meetOpened = false
}

private final class OverlayPanel: NSPanel {
    override var canBecomeKey: Bool { true }
}

final class PanelController {
    let model = PanelModel()
    private let panel: OverlayPanel

    var shownMeetingID: String? { panel.isVisible ? model.meeting?.id : nil }

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
        panel.contentView = NSHostingView(
            rootView: PanelView(model: model, onJoin: onJoin, onSnooze: onSnooze, onSkip: onSkip)
        )
    }

    func show(_ meeting: Meeting, snoozesLeft: Int, meetOpened: Bool, now: Date) {
        model.meeting = meeting
        model.snoozesLeft = snoozesLeft
        model.meetOpened = meetOpened
        model.now = now
        guard !panel.isVisible else { return }
        if let screen = NSScreen.main { panel.setFrame(screen.frame, display: true) }
        panel.orderFrontRegardless()
        panel.makeKey()
        NSApp.activate(ignoringOtherApps: true)
    }

    func hide() {
        panel.orderOut(nil)
    }
}

private struct PanelView: View {
    @ObservedObject var model: PanelModel
    let onJoin: () -> Void
    let onSnooze: () -> Void
    let onSkip: () -> Void

    var body: some View {
        ZStack {
            Color.black.opacity(0.88).ignoresSafeArea()
            if let meeting = model.meeting {
                VStack(spacing: 28) {
                    Text(countdown(to: meeting.start))
                        .font(.system(size: 24, weight: .medium))
                        .foregroundStyle(.white.opacity(0.7))
                        .monospacedDigit()
                    Text(meeting.title)
                        .font(.system(size: 56, weight: .bold))
                        .foregroundStyle(.white)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 80)
                    HStack(spacing: 16) {
                        Button(joinLabel(meeting), action: onJoin)
                            .keyboardShortcut(.defaultAction)
                        if model.snoozesLeft > 0 {
                            Button("Snooze 1 min (\(model.snoozesLeft))", action: onSnooze)
                        }
                        Button("Je saute cette réunion", action: onSkip)
                    }
                    .controlSize(.extraLarge)
                    .padding(.top, 12)
                }
            }
        }
    }

    private func joinLabel(_ meeting: Meeting) -> String {
        if meeting.url == nil { return "OK, j'y vais" }
        return model.meetOpened ? "J'y suis" : "Rejoindre"
    }

    private func countdown(to start: Date) -> String {
        let seconds = Int(start.timeIntervalSince(model.now).rounded())
        if seconds > 0 { return "Commence dans \(seconds) s" }
        let late = -seconds / 60
        return late == 0 ? "Commence maintenant" : "A commencé il y a \(late) min"
    }
}
