@testable import MLHCore

func runSyntheticDeletionTests() -> (passed: Int, failed: Int) {
    var passed = 0
    var failed = 0
    func check(_ name: String, _ condition: Bool) {
        if condition { passed += 1 }
        else { failed += 1; print("FAIL synthetic deletion: \(name)") }
    }

    // Excel temporarily deactivates the original input controller during
    // deletion; some synthetic key notifications may never return to it.
    var edit = SyntheticDeletionProgress()
    edit.start(count: 3)
    let generation = edit.generation
    check("ordinary in-flight input keeps existing behaviour",
          edit.actionForOtherKey(allEventsPosted: false, contextMatches: false) == .ignore)
    check("first backspace is not the last", !edit.observeBackspace())
    check("fallback cannot resume after focus loss", !edit.lostFocus(canValidateContext: false))
    check("fallback does not mark context validation", !edit.needsContextValidation)
    check("readable context can resume after focus loss", edit.lostFocus(canValidateContext: true))
    check("focus loss requires context validation", edit.needsContextValidation)
    check("key cancels while backspaces are still being posted",
          edit.actionForOtherKey(allEventsPosted: false, contextMatches: true) == .cancel)
    check("key cancels if context is unavailable",
          edit.actionForOtherKey(allEventsPosted: true, contextMatches: false) == .cancel)
    check("key completes verified pending edit",
          edit.actionForOtherKey(allEventsPosted: true, contextMatches: true) == .finish)
    check("another backspace is not the last", !edit.observeBackspace())
    check("one backspace notification is missing", edit.remaining == 1)
    check("changed context cannot complete", !edit.allowsCompletion(contextMatches: false))
    check("verified context can complete", edit.allowsCompletion(contextMatches: true))
    edit.reset()
    check("completion invalidates scheduled work", edit.generation != generation)
    check("completion clears pending events", edit.remaining == 0 && !edit.needsContextValidation)

    // With no focus change, the usual final-event path remains in control.
    edit.start(count: 2)
    check("focus unchanged does not need context", edit.allowsCompletion(contextMatches: false))
    check("first of two backspaces is not the last", !edit.observeBackspace())
    check("second backspace is the last", edit.observeBackspace())
    check("extra backspaces do not complete again", !edit.observeBackspace())

    // Starting another edit invalidates callbacks belonging to the previous one.
    let previous = edit.generation
    edit.start(count: 1)
    check("new edit gets a new generation", edit.generation != previous)
    check("new edit does not inherit focus loss", !edit.needsContextValidation)

    // Reading at most 1024 UTF-16 units moves the start of a long line
    // backward when the suffix is deleted.
    let retained = String(repeating: "x", count: 1016)
    check("shifted context window matches", SyntheticDeletionProgress.matchesContext(
        expectedLocation: 84, expectedPrefix: retained,
        currentLocation: 76, currentText: String(repeating: "x", count: 1024)))
    check("different cursor does not match", !SyntheticDeletionProgress.matchesContext(
        expectedLocation: 84, expectedPrefix: retained,
        currentLocation: 75, currentText: String(repeating: "x", count: 1024)))
    check("different text does not match", !SyntheticDeletionProgress.matchesContext(
        expectedLocation: 84, expectedPrefix: retained,
        currentLocation: 76, currentText: String(repeating: "x", count: 1023) + "y"))
    check("cursor offsets count UTF-16 units", SyntheticDeletionProgress.matchesContext(
        expectedLocation: 4, expectedPrefix: "😀a", currentLocation: 2, currentText: "xx😀a"))
    check("cursor offset rejects character count", !SyntheticDeletionProgress.matchesContext(
        expectedLocation: 4, expectedPrefix: "😀a", currentLocation: 3, currentText: "xx😀a"))

    return (passed, failed)
}
