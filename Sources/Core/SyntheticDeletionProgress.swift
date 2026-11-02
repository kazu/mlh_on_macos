/// Tracks an edit while synthetic backspaces are delivered to the input method.
/// The controller owns the timers and checks the client context; this value
/// decides whether those observations are enough to continue an edit.
public struct SyntheticDeletionProgress {
    public enum OtherKeyAction: Equatable { case ignore, finish, cancel }
    public private(set) var remaining = 0
    public private(set) var generation = 0
    public private(set) var needsContextValidation = false

    public init() {}

    public mutating func start(count: Int) {
        reset()
        remaining = max(0, count)
    }

    /// Without a readable context there is no safe way to resume the edit.
    public mutating func lostFocus(canValidateContext: Bool) -> Bool {
        guard canValidateContext else { return false }
        needsContextValidation = true
        return true
    }

    /// Returns true only when this observation accounts for the last backspace.
    public mutating func observeBackspace() -> Bool {
        guard remaining > 0 else { return false }
        remaining -= 1
        return remaining == 0
    }

    /// After a focus change, only the original, verified context is safe.
    public func allowsCompletion(contextMatches: @autoclosure () -> Bool) -> Bool {
        !needsContextValidation || contextMatches()
    }

    /// Do not lose a new key while waiting for a context after focus returns.
    public func actionForOtherKey(allEventsPosted: Bool,
                                  contextMatches: @autoclosure () -> Bool) -> OtherKeyAction {
        guard needsContextValidation else { return .ignore }
        return allEventsPosted && contextMatches() ? .finish : .cancel
    }

    /// The client's look-behind window can move after deletion. The cursor
    /// must still be at the expected UTF-16 offset and the retained prefix
    /// must match the end of the newly read context.
    public static func matchesContext(expectedLocation: Int, expectedPrefix: String,
                                      currentLocation: Int, currentText: String) -> Bool {
        expectedLocation + expectedPrefix.utf16.count == currentLocation + currentText.utf16.count
            && currentText.hasSuffix(expectedPrefix)
    }

    public mutating func reset() {
        generation &+= 1
        remaining = 0
        needsContextValidation = false
    }
}
