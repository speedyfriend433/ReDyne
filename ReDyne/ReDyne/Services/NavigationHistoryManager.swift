import Foundation

/// A destination in the binary analysis interface.
enum NavigationEntry: Equatable {
    case section(index: Int)
    case disassembly(address: UInt64)
    case symbol(name: String)
    case hexView(offset: UInt64)
}

/// History belongs to the UI, including callbacks that replay a destination.
/// Main-actor isolation keeps synchronous reads, updates, and replay on the same
/// executor without recursively dispatching to a serial queue.
@MainActor
final class NavigationHistoryManager {
    private static let maxDepth = 100
    private var entries: [NavigationEntry] = []
    private var currentIndex = -1
    private var replayDepth = 0

    var canGoBack: Bool {
        currentIndex > 0
    }

    var canGoForward: Bool {
        currentIndex < entries.count - 1
    }

    /// Records a destination, discarding the forward branch after a new visit.
    func push(entry: NavigationEntry) {
        guard replayDepth == 0 else { return }
        if currentIndex >= 0, entries[currentIndex] == entry { return }

        if currentIndex < entries.count - 1 {
            entries.removeSubrange((currentIndex + 1)...)
        }
        entries.append(entry)
        currentIndex = entries.count - 1

        if entries.count > Self.maxDepth {
            let overflow = entries.count - Self.maxDepth
            entries.removeFirst(overflow)
            currentIndex -= overflow
        }
    }

    func goBack() -> NavigationEntry? {
        guard canGoBack else { return nil }
        currentIndex -= 1
        return entries[currentIndex]
    }

    func goForward() -> NavigationEntry? {
        guard canGoForward else { return nil }
        currentIndex += 1
        return entries[currentIndex]
    }

    /// Runs UI navigation inline, suppressing recording until all nested replays
    /// have returned. Deferred/asynchronous navigation is outside this scope.
    func performWithoutRecording(_ body: @MainActor () -> Void) {
        replayDepth += 1
        defer { replayDepth -= 1 }
        body()
    }

    func clear() {
        entries.removeAll()
        currentIndex = -1
    }
}
