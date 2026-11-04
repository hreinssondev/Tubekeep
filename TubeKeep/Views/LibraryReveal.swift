import AppKit
import SwiftUI

/// How far the library has scrolled up under the player: 0 shows only the video, 1 the whole library.
/// Only vertical scrolling over the video moves it, so the browser's lists keep their own scrolling
/// and sideways scrolling still reaches the player to seek.
@MainActor @Observable
final class LibraryReveal {
    var progress: CGFloat = 1
    /// Points of scrolling between hidden and shown; the height the library takes up.
    @ObservationIgnored var distance: CGFloat = 500
    @ObservationIgnored weak var playerView: NSView?
    @ObservationIgnored private var monitor: Any?
    /// The current trackpad gesture started over the video, so its momentum is ours too.
    @ObservationIgnored private var tracking = false
    /// The current gesture's axis, fixed by its first movement: true is vertical, nil not yet known.
    @ObservationIgnored private var vertical: Bool?
    @ObservationIgnored private var velocity: CGFloat = 0
    @ObservationIgnored private var wheelSnap: Task<Void, Never>?

    init() {
        monitor = NSEvent.addLocalMonitorForEvents(matching: .scrollWheel) { [weak self] event in
            MainActor.assumeIsolated { self?.handle(event) ?? event }
        }
    }

    var isShown: Bool { progress > 0.5 }

    func toggle() {
        withAnimation(.snappy(duration: 0.3)) { progress = isShown ? 0 : 1 }
    }

    private func handle(_ event: NSEvent) -> NSEvent? {
        if event.momentumPhase != [] {
            return tracking && vertical == true ? nil : event
        }
        if event.phase == [] {
            // A mouse wheel: no gesture phases, so snap once the wheel stops.
            guard isOverPlayer(event), !isSideways(event) else { return event }
            move(by: event.scrollingDeltaY * (event.hasPreciseScrollingDeltas ? 1 : 8))
            wheelSnap?.cancel()
            wheelSnap = Task {
                try? await Task.sleep(for: .milliseconds(180))
                if !Task.isCancelled { snap() }
            }
            return nil
        }
        if event.phase.contains(.began) || event.phase.contains(.mayBegin) {
            tracking = isOverPlayer(event)
            vertical = nil
            velocity = 0
            return event
        }
        guard tracking else { return event }
        if event.phase.contains(.changed) {
            if vertical == nil, event.scrollingDeltaX != 0 || event.scrollingDeltaY != 0 {
                vertical = !isSideways(event)
            }
            guard vertical == true else { return event }
            move(by: event.scrollingDeltaY)
            return nil
        }
        if event.phase.contains(.ended) || event.phase.contains(.cancelled), vertical == true {
            snap()
        }
        return event
    }

    private func move(by delta: CGFloat) {
        velocity = velocity * 0.6 + delta * 0.4
        progress = min(max(progress - delta / distance, 0), 1)
    }

    /// Settles fully open or closed, following the direction of the last movement.
    private func snap() {
        let target: CGFloat = if velocity < -0.5 { 1 } else if velocity > 0.5 { 0 } else { progress > 0.5 ? 1 : 0 }
        velocity = 0
        withAnimation(.snappy(duration: 0.3)) { progress = target }
    }

    private func isSideways(_ event: NSEvent) -> Bool {
        abs(event.scrollingDeltaX) > abs(event.scrollingDeltaY)
    }

    private func isOverPlayer(_ event: NSEvent) -> Bool {
        guard let view = playerView, let window = view.window, event.window === window else { return false }
        return view.bounds.contains(view.convert(event.locationInWindow, from: nil))
    }
}
