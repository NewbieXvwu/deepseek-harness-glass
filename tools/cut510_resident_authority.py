from pathlib import Path

STORE = Path("glass/Sources/Core/Session/NativeSessionStore.swift")
TESTS = Path("glass/Tests/Core/NativeSessionStoreTests.swift")


def replace_once(text: str, source: str, target: str, label: str) -> str:
    count = text.count(source)
    if count != 1:
        raise SystemExit(f"{label}: expected one anchor, found {count}")
    return text.replace(source, target, 1)


def function_block(text: str, marker: str) -> tuple[int, int, str]:
    start = text.find(marker)
    if start < 0:
        raise SystemExit(f"missing function marker: {marker}")
    end = text.find("\n    func ", start + len(marker))
    if end < 0:
        end = len(text)
    return start, end, text[start:end]


store = STORE.read_text()

helper_marker = "    /// Core-internal resident-window restore seam used by regression tests.\n"
helper = '''    /// Invalidate every Host-authoritative value cached by a prior resident
    /// generation while retaining the already-rendered local snapshot. The current
    /// generation must repopulate these fields from SessionRuntime/control authority.
    private func invalidateResidentHostAuthority(sessionID: String) {
        let cachedChatNodes = chatNodes
        let cachedTrajectoryNodes = trajectoryNodes
        hasMoreHistory = false
        isLoadingOlderHistory = false
        isRunning = false
        queuedMessages = []
        backgroundJobs = []
        pendingApproval = nil
        pendingQuestion = nil
        isSubmittingApproval = false
        isSubmittingQuestion = false
        lastError = nil
        appliedSequences = []
        subscribedLastSequence = nil
        projections.remove(sessionID: sessionID)
        resetConversationWindow()
        chatNodes = cachedChatNodes
        trajectoryNodes = cachedTrajectoryNodes
    }

    /// Reapply only the currently bound Host generation's shared control snapshot.
    /// A resident cache is never itself allowed to restore queue/jobs/projections.
    private func refreshCurrentControlAuthority(for sessionID: String) {
        guard let runtime = sessionControlRuntime else { return }
        let bindingGeneration = controlBindingGeneration
        Task { [weak self] in
            guard let snapshot = await runtime.currentSnapshot(),
                  !Task.isCancelled,
                  self?.controlBindingGeneration == bindingGeneration,
                  self?.activeSessionID == sessionID
            else { return }
            self?.installRemoteControl(snapshot)
        }
    }

'''
store = replace_once(store, helper_marker, helper + helper_marker, "resident authority helpers")

start, end, block = function_block(store, "    func restoreResidentState(for sessionID: String) -> Bool {\n")
block = replace_once(
    block,
    "        return true\n",
    "        invalidateResidentHostAuthority(sessionID: sessionID)\n        return true\n",
    "resident restore invalidation",
)
store = store[:start] + block + store[end:]

store = replace_once(
    store,
    '''        } else {
            // The render tree remains on the resident window while the next
            // history authority baseline arrives; this is not a new blank UI.
            phase = .ready(sessionID: sessionID)
        }

        modelDirectoryStatus = .loading
''',
    '''        } else {
            // Keep the resident render tree visible while authority is absent.
            // Host-owned state remains loading until this generation installs it.
            phase = .loading(sessionID: sessionID)
            refreshCurrentControlAuthority(for: sessionID)
        }

        modelDirectoryStatus = .loading
''',
    "resident open authority phase",
)

store = replace_once(
    store,
    '''    /// Host authority baseline. Cold instances have no transport to rebuild.
    /// Queue/jobs deliberately remain until the fresh `session/subscribed`
    /// mux boundary supplies their ordered whole snapshots.
''',
    '''    /// Host authority baseline. Cold instances have no transport to rebuild.
    /// Cached Host authority is dropped immediately; the bound generation alone
    /// may repopulate control state while the durable journal is reopening.
''',
    "resync authority comment",
)

start, end, block = function_block(store, "    func resyncActiveSession() {\n")
block = replace_once(
    block,
    "        phase = .loading(sessionID: sessionID)\n",
    "        phase = .loading(sessionID: sessionID)\n        invalidateResidentHostAuthority(sessionID: sessionID)\n        refreshCurrentControlAuthority(for: sessionID)\n",
    "resync immediate authority invalidation",
)
store = store[:start] + block + store[end:]
STORE.write_text(store)


tests = TESTS.read_text()
tests = replace_once(
    tests,
    "    func testResidentResyncRetainsQueueAndJobsUntilFreshSubscriptionBoundary() async {\n",
    "    func testResidentResyncDropsCachedQueueAndJobsBeforeFreshAuthority() async {\n",
    "resident resync test name",
)
tests = replace_once(
    tests,
    '''        XCTAssertEqual(store.queuedMessages.map(\\.id), ["prior-queue"], "RC8 preserves the mirror until the ordered subscription baseline")
        XCTAssertEqual(store.backgroundJobs.map(\\.id), ["prior-job"])
''',
    '''        XCTAssertTrue(store.queuedMessages.isEmpty, "resident resync must not retain prior-generation queue authority")
        XCTAssertTrue(store.backgroundJobs.isEmpty, "resident resync must not retain prior-generation jobs authority")
''',
    "resident resync stale authority assertions",
)
TESTS.write_text(tests)
