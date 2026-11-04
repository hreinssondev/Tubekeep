import AppKit
import SwiftUI

/// How far the page has scrolled down from the video to the library: 0 shows only the video, 1 the whole library.
/// Only vertical scrolling over the video or its title bar moves it, so the browser's lists keep their own scrolling.
/// Scrolling over the video never reaches the player, which would pause and seek; the arrow keys seek.
@MainActor
final class LibraryReveal: ObservableObject {
    @Published var progress: CGFloat = 1
    /// Points of scrolling between hidden and shown; the height the library takes up.
    var distance: CGFloat = 500
    weak var playerView: NSView?
    /// The title bar under the video, which scrolls the page too.
    weak var infoView: NSView?
    private var monitor: Any?
    /// The current trackpad gesture started over the video, so its momentum is ours too.
    private var tracking = false
    /// The current gesture's axis, fixed by its first movement: true is vertical, nil not yet known.
    private var vertical: Bool?
    private var velocity: CGFloat = 0
    private var wheelSnap: Task<Void, Never>?

    init() {
        monitor = NSEvent.addLocalMonitorForEvents(matching: .scrollWheel) { [weak self] event in
            MainActor.assumeIsolated { self?.handle(event) ?? event }
        }
    }

    var isShown: Bool { progress > 0.5 }

    func toggle() {
        withAnimation(.reveal) { progress = isShown ? 0 : 1 }
    }

    func hide() {
        withAnimation(.reveal) { progress = 0 }
    }

    private func handle(_ event: NSEvent) -> NSEvent? {
        if event.momentumPhase != [] {
            return tracking ? nil : event
        }
        if event.phase == [] {
            // A mouse wheel: no gesture phases, so snap once the wheel stops.
            guard isOverScrollArea(event) else { return event }
            guard !isSideways(event) else { return nil }
            move(by: event.scrollingDeltaY * (event.hasPreciseScrollingDeltas ? 1 : 8))
            wheelSnap?.cancel()
            wheelSnap = Task {
                try? await Task.sleep(for: .milliseconds(180))
                if !Task.isCancelled { snap() }
            }
            return nil
        }
        if event.phase.contains(.began) || event.phase.contains(.mayBegin) {
            tracking = isOverScrollArea(event)
            vertical = nil
            velocity = 0
        }
        guard tracking else { return event }
        if event.phase.contains(.changed) {
            if vertical == nil, event.scrollingDeltaX != 0 || event.scrollingDeltaY != 0 {
                vertical = !isSideways(event)
            }
            if vertical == true { move(by: event.scrollingDeltaY) }
        }
        if event.phase.contains(.ended) || event.phase.contains(.cancelled), vertical == true {
            snap()
        }
        return nil
    }

    private func move(by delta: CGFloat) {
        velocity = velocity * 0.6 + delta * 0.4
        progress = min(max(progress - delta / distance, 0), 1)
    }

    /// Settles fully open or closed, following the direction of the last movement.
    private func snap() {
        let target: CGFloat = if velocity < -0.5 { 1 } else if velocity > 0.5 { 0 } else { progress > 0.5 ? 1 : 0 }
        velocity = 0
        withAnimation(.reveal) { progress = target }
    }

    private func isSideways(_ event: NSEvent) -> Bool {
        abs(event.scrollingDeltaX) > abs(event.scrollingDeltaY)
    }

    private func isOverScrollArea(_ event: NSEvent) -> Bool {
        [playerView, infoView].contains { view in
            // The page's top scrolls up under the toolbar, which doesn't count.
            guard let view, let window = view.window, event.window === window,
                  window.contentLayoutRect.contains(event.locationInWindow) else { return false }
            return view.bounds.contains(view.convert(event.locationInWindow, from: nil))
        }
    }
}

/// Marks the view it's the background of as a place where scrolling moves the page.
struct PageScrollArea: NSViewRepresentable {
    let reveal: LibraryReveal

    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        reveal.infoView = view
        return view
    }

    func updateNSView(_ view: NSView, context: Context) {}
}

extension Animation {
    /// Opening and closing the library: `.snappy` where there is one (macOS 14).
    static var reveal: Animation {
        if #available(macOS 14, *) { .snappy(duration: 0.3) } else { .spring(response: 0.3, dampingFraction: 0.85) }
    }
}
