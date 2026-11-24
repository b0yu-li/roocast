import Foundation
import Combine

/// Launcher search text + optional locked command chip (Tab-to-lock).
@MainActor
final class SearchSession: ObservableObject {
    @Published var query = ""
    @Published var lockedVerb: String?
    @Published var argument = ""

    var searchQuery: String {
        if let lockedVerb {
            return CommandLock.composedQuery(verb: lockedVerb, argument: argument)
        }
        return query
    }

    var fieldPlaceholder: String {
        if let lockedVerb, let cmd = CommandLock.command(forVerb: lockedVerb) {
            return cmd.argumentPlaceholder
        }
        return "Search apps, files, commands…"
    }

    var showsClearButton: Bool {
        !query.isEmpty || lockedVerb != nil || !argument.isEmpty
    }

    @discardableResult
    func tryLockCommand() -> Bool {
        guard lockedVerb == nil else { return false }
        guard let locked = CommandLock.lockAttempt(from: query) else { return false }
        lockedVerb = locked.verb
        argument = locked.argument
        query = ""
        return true
    }

    @discardableResult
    func unlockCommand() -> Bool {
        guard let verb = lockedVerb else { return false }
        query = CommandLock.composedQuery(verb: verb, argument: argument)
        lockedVerb = nil
        argument = ""
        return true
    }

    func clear() {
        query = ""
        lockedVerb = nil
        argument = ""
    }
}
