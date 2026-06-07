import Foundation
import SmartSleepCore
import WatchKit

protocol RuntimeSessionScheduling: AnyObject {
    var latestLog: RuntimeSessionLog? { get }
    var onLogUpdated: ((RuntimeSessionLog) -> Void)? { get set }
    func schedule(for payload: AlarmConfigPayload, runId: UUID) -> RuntimeSessionLog
    func invalidate()
}

final class FakeRuntimeSessionScheduler: RuntimeSessionScheduling {
    var shouldSucceed: Bool
    var latestLog: RuntimeSessionLog? {
        didSet {
            if let latestLog {
                onLogUpdated?(latestLog)
            }
        }
    }
    var onLogUpdated: ((RuntimeSessionLog) -> Void)?
    private(set) var invalidateCallCount = 0
    private(set) var lastRunID: UUID?

    init(shouldSucceed: Bool) {
        self.shouldSucceed = shouldSucceed
    }

    func schedule(for payload: AlarmConfigPayload, runId: UUID) -> RuntimeSessionLog {
        lastRunID = runId
        let log = RuntimeSessionLog(
            runId: runId,
            sessionType: "fakeSmartAlarmPreMonitoring",
            scheduledAt: Date(),
            targetStartAt: payload.nextFireAt.addingTimeInterval(-30 * 60),
            actualStartAt: nil,
            invalidatedAt: nil,
            invalidationReason: nil,
            startLatencySec: nil,
            didStartBeforeAlarm: false,
            didReachRingTime: false,
            errorCode: shouldSucceed ? nil : "fake_runtime_schedule_failed",
            errorMessage: shouldSucceed ? nil : "Fake runtime scheduler was configured to fail."
        )
        latestLog = log
        return log
    }

    func invalidate() {
        invalidateCallCount += 1
    }

    func emitInvalidation(_ log: RuntimeSessionLog) {
        latestLog = log
    }
}

final class WatchRuntimeSessionScheduler: NSObject, ObservableObject, RuntimeSessionScheduling {
    @Published private(set) var latestLog: RuntimeSessionLog? {
        didSet {
            if let latestLog {
                onLogUpdated?(latestLog)
            }
        }
    }
    var onLogUpdated: ((RuntimeSessionLog) -> Void)?

    private var session: WKExtendedRuntimeSession?

    func schedule(for payload: AlarmConfigPayload, runId: UUID) -> RuntimeSessionLog {
        let targetStart = payload.nextFireAt.addingTimeInterval(-30 * 60)
        let now = Date()
        let newSession = WKExtendedRuntimeSession()
        newSession.delegate = self
        session = newSession

        let log = RuntimeSessionLog(
            runId: runId,
            sessionType: "smartAlarmPreMonitoring",
            scheduledAt: now,
            targetStartAt: targetStart,
            actualStartAt: nil,
            invalidatedAt: nil,
            invalidationReason: nil,
            startLatencySec: nil,
            didStartBeforeAlarm: false,
            didReachRingTime: false,
            errorCode: nil,
            errorMessage: nil
        )
        latestLog = log

        if targetStart <= now {
            newSession.start()
        } else {
            newSession.start(at: targetStart)
        }

        return log
    }

    func invalidate() {
        session?.invalidate()
        session = nil
    }
}

extension WatchRuntimeSessionScheduler: WKExtendedRuntimeSessionDelegate {
    nonisolated func extendedRuntimeSessionDidStart(_ extendedRuntimeSession: WKExtendedRuntimeSession) {
        Task { @MainActor in
            guard var log = latestLog else { return }
            let now = Date()
            log.actualStartAt = now
            log.startLatencySec = now.timeIntervalSince(log.targetStartAt)
            log.didStartBeforeAlarm = true
            latestLog = log
        }
    }

    nonisolated func extendedRuntimeSessionWillExpire(_ extendedRuntimeSession: WKExtendedRuntimeSession) {}

    nonisolated func extendedRuntimeSession(
        _ extendedRuntimeSession: WKExtendedRuntimeSession,
        didInvalidateWith reason: WKExtendedRuntimeSessionInvalidationReason,
        error: Error?
    ) {
        Task { @MainActor in
            guard var log = latestLog else { return }
            log.invalidatedAt = Date()
            log.invalidationReason = String(describing: reason)
            log.errorMessage = error?.localizedDescription
            latestLog = log
        }
    }
}
