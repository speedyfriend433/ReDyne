import Foundation

@MainActor
@main
struct NavigationHistoryTests {
    static func main() {
        emptyAndSingleEntry()
        backAndForward()
        newVisitDiscardsForwardBranch()
        duplicateVisitKeepsForwardBranch()
        replayCanReadAndPushHistory()
        nestedReplayStaysSuppressed()
        clearDuringReplay()
        boundedHistory()
        print("Navigation history tests passed")
    }

    private static func emptyAndSingleEntry() {
        let history = NavigationHistoryManager()
        precondition(!history.canGoBack && !history.canGoForward)
        precondition(history.goBack() == nil && history.goForward() == nil)
        history.push(entry: .section(index: 0))
        precondition(!history.canGoBack && !history.canGoForward)
        precondition(history.goBack() == nil && history.goForward() == nil)
    }

    private static func backAndForward() {
        let history = NavigationHistoryManager()
        let visits: [NavigationEntry] = [
            .section(index: 0), .disassembly(address: 0x1000),
            .symbol(name: "example"), .hexView(offset: 0x200)
        ]
        for visit in visits { history.push(entry: visit) }
        for visit in visits.dropLast().reversed() {
            precondition(history.canGoBack)
            precondition(history.goBack() == visit)
        }
        precondition(history.goBack() == nil)
        for visit in visits.dropFirst() {
            precondition(history.canGoForward)
            precondition(history.goForward() == visit)
        }
        precondition(history.goForward() == nil)
    }

    private static func newVisitDiscardsForwardBranch() {
        let history = NavigationHistoryManager()
        history.push(entry: .section(index: 0))
        history.push(entry: .section(index: 1))
        history.push(entry: .section(index: 2))
        precondition(history.goBack() == .section(index: 1))
        history.push(entry: .symbol(name: "new branch"))
        precondition(!history.canGoForward && history.goForward() == nil)
        precondition(history.goBack() == .section(index: 1))
        precondition(history.goForward() == .symbol(name: "new branch"))
    }

    private static func duplicateVisitKeepsForwardBranch() {
        let history = NavigationHistoryManager()
        history.push(entry: .section(index: 0))
        history.push(entry: .section(index: 1))
        history.push(entry: .section(index: 2))
        precondition(history.goBack() == .section(index: 1))
        history.push(entry: .section(index: 1))
        precondition(history.goForward() == .section(index: 2))
        precondition(history.goBack() == .section(index: 1))
        precondition(history.goBack() == .section(index: 0))
        precondition(history.goBack() == nil)
    }

    private static func replayCanReadAndPushHistory() {
        let history = NavigationHistoryManager()
        history.push(entry: .section(index: 0))
        history.push(entry: .section(index: 1))
        precondition(history.goBack() == .section(index: 0))
        history.performWithoutRecording {
            precondition(Thread.isMainThread)
            precondition(!history.canGoBack && history.canGoForward)
            // Switching sections can synchronously attempt to record a visit.
            history.push(entry: .hexView(offset: 0x999))
        }
        precondition(history.goForward() == .section(index: 1))
        history.push(entry: .symbol(name: "recording restored"))
        precondition(history.goBack() == .section(index: 1))
        precondition(history.goForward() == .symbol(name: "recording restored"))
    }

    private static func nestedReplayStaysSuppressed() {
        let history = NavigationHistoryManager()
        history.push(entry: .section(index: 0))
        history.performWithoutRecording {
            history.performWithoutRecording {
                history.push(entry: .section(index: 1))
            }
            history.push(entry: .section(index: 2))
        }
        precondition(!history.canGoBack)
        history.push(entry: .section(index: 3))
        precondition(history.goBack() == .section(index: 0))
    }

    private static func clearDuringReplay() {
        let history = NavigationHistoryManager()
        history.push(entry: .section(index: 0))
        history.performWithoutRecording {
            history.clear()
            history.push(entry: .section(index: 1))
        }
        precondition(!history.canGoBack && !history.canGoForward)
        history.push(entry: .section(index: 2))
        history.push(entry: .section(index: 3))
        precondition(history.goBack() == .section(index: 2))
        precondition(history.goBack() == nil)
        history.clear()
        precondition(history.goBack() == nil && history.goForward() == nil)
    }

    private static func boundedHistory() {
        let history = NavigationHistoryManager()
        for index in 0..<150 { history.push(entry: .section(index: index)) }
        var recovered: [NavigationEntry] = []
        while let entry = history.goBack() { recovered.append(entry) }
        precondition(recovered.count == 99)
        precondition(recovered.first == .section(index: 148))
        precondition(recovered.last == .section(index: 50))
        for index in 51..<150 { precondition(history.goForward() == .section(index: index)) }
        precondition(history.goForward() == nil)
    }
}
