import XCTest
@testable import SmartSleepWatch
import SmartSleepCore

@MainActor
final class WatchAlarmRunEngineTests: XCTestCase {
    func testRuntimeStartMovesToPreMonitoringAndRingTimeStartsRingingInsideRuntimeWindow() {
        let ringer = FakeWatchAlarmRinger()
        let logger = FakeWatchAlarmRunLogger()
        let engine = WatchAlarmRunEngine(ringer: ringer)
        let runId = UUID()
        let log = RuntimeSessionLog(
            runId: runId,
            sessionType: "smartAlarmPreMonitoring",
            scheduledAt: Date(timeIntervalSince1970: 0),
            targetStartAt: Date(timeIntervalSince1970: 10),
            actualStartAt: Date(timeIntervalSince1970: 11),
            invalidatedAt: nil,
            invalidationReason: nil,
            startLatencySec: 1,
            didStartBeforeAlarm: true,
            didReachRingTime: false,
            errorCode: nil,
            errorMessage: nil
        )

        engine.runtimeDidStart(log, nextFireAt: Date(timeIntervalSince1970: 20), runLogger: logger)
        XCTAssertEqual(engine.state, .preMonitoring)
        XCTAssertEqual(logger.stateTransitionLogs.map(\.toState), [.preMonitoring])

        engine.ringTimeReached(runLogger: logger)
        XCTAssertEqual(engine.state, .ringing)
        XCTAssertEqual(ringer.startCallCount, 1)
        XCTAssertEqual(logger.channelLogs.last?.channel, .watchRuntimeHapticAudio)
        XCTAssertEqual(logger.channelLogs.last?.userVisibleState, "ringing")
        XCTAssertEqual(logger.stateTransitionLogs.map(\.toState), [.preMonitoring, .ringing])
    }

    func testSnoozeAndStopRecordChannelOutcomeAndTransitions() {
        let ringer = FakeWatchAlarmRinger()
        let logger = FakeWatchAlarmRunLogger()
        let engine = WatchAlarmRunEngine(ringer: ringer)
        let runId = UUID()
        let log = RuntimeSessionLog(
            runId: runId,
            sessionType: "smartAlarmPreMonitoring",
            scheduledAt: Date(timeIntervalSince1970: 0),
            targetStartAt: Date(timeIntervalSince1970: 10),
            actualStartAt: Date(timeIntervalSince1970: 11),
            invalidatedAt: nil,
            invalidationReason: nil,
            startLatencySec: 1,
            didStartBeforeAlarm: true,
            didReachRingTime: false,
            errorCode: nil,
            errorMessage: nil
        )

        engine.runtimeDidStart(log, nextFireAt: Date(timeIntervalSince1970: 20), runLogger: logger)
        engine.ringTimeReached(runLogger: logger, at: Date(timeIntervalSince1970: 20))
        engine.snooze(runLogger: logger, at: Date(timeIntervalSince1970: 21))

        XCTAssertEqual(engine.state, .snoozed)
        XCTAssertEqual(ringer.snoozeCallCount, 1)
        XCTAssertEqual(logger.channelLogs.last?.snoozedAt, Date(timeIntervalSince1970: 21))
        XCTAssertEqual(logger.channelLogs.last?.userVisibleState, "snoozed")
        XCTAssertEqual(logger.stateTransitionLogs.last?.toState, .snoozed)

        engine.stop(runLogger: logger, at: Date(timeIntervalSince1970: 22))

        XCTAssertEqual(engine.state, .completed)
        XCTAssertEqual(ringer.stopCallCount, 1)
        XCTAssertEqual(logger.channelLogs.last?.stoppedAt, Date(timeIntervalSince1970: 22))
        XCTAssertEqual(logger.channelLogs.last?.userVisibleState, "stopped")
        XCTAssertEqual(logger.stateTransitionLogs.last?.toState, .completed)
        XCTAssertEqual(logger.outcomeLogs.last?.manualStop, true)
    }

    func testReSleepEvaluationDoesNothingWithDefaultFlags() {
        let ringer = FakeWatchAlarmRinger()
        let engine = WatchAlarmRunEngine(ringer: ringer)
        let freshness = SensorFreshness.fixture(
            motionLastSampleAgeSec: 1,
            hrLastSampleAgeSec: nil,
            baselineHRConfidence: .none,
            watchWornConfidence: .medium
        )
        var summary = SensorSummary.fixture(
            motionContinuitySec: 0,
            postureDelta: 1,
            gyroPeak: 0,
            stepDelta: 0,
            interactionCount: 0,
            hrDeltaFromBaseline: nil
        )
        summary.stillnessDurationSec = 180

        engine.autoSilenceConfirmed(at: Date(timeIntervalSince1970: 0))
        let result = engine.evaluateReSleep(
            summary: summary,
            freshness: freshness,
            now: Date(timeIntervalSince1970: 180)
        )

        XCTAssertNil(result)
        XCTAssertEqual(engine.state, .sessionScheduled)
        XCTAssertEqual(ringer.startCallCount, 0)
    }

    func testReSleepEvaluationReRingsWhenFlagsEnabledAndRiskHigh() {
        let ringer = FakeWatchAlarmRinger()
        let flags = FeatureFlags(
            autoSilenceEnabled: true,
            reSleepDetectionEnabled: true,
            gestureSnoozeEnabled: true,
            heartRateBoostEnabled: true,
            maxReAlarmCount: 2
        )
        let engine = WatchAlarmRunEngine(ringer: ringer, featureFlags: flags)
        let freshness = SensorFreshness.fixture(
            motionLastSampleAgeSec: 1,
            hrLastSampleAgeSec: nil,
            baselineHRConfidence: .none,
            watchWornConfidence: .medium
        )
        var summary = SensorSummary.fixture(
            motionContinuitySec: 0,
            postureDelta: 1,
            gyroPeak: 0,
            stepDelta: 0,
            interactionCount: 0,
            hrDeltaFromBaseline: nil
        )
        summary.stillnessDurationSec = 180

        engine.autoSilenceConfirmed(at: Date(timeIntervalSince1970: 0))
        let result = engine.evaluateReSleep(
            summary: summary,
            freshness: freshness,
            now: Date(timeIntervalSince1970: 180)
        )

        XCTAssertEqual(engine.state, .reRinging)
        XCTAssertEqual(ringer.startCallCount, 1)
        XCTAssertEqual(result?.shouldReRing, true)
    }

    func testAutoSilenceRequiresCandidateThenConfirmationWindow() {
        let ringer = FakeWatchAlarmRinger()
        let logger = FakeWatchAlarmRunLogger()
        let flags = FeatureFlags(
            autoSilenceEnabled: true,
            reSleepDetectionEnabled: false,
            gestureSnoozeEnabled: true,
            heartRateBoostEnabled: true,
            maxReAlarmCount: 2
        )
        let engine = WatchAlarmRunEngine(ringer: ringer, featureFlags: flags)
        let runId = UUID()
        engine.runtimeDidStart(RuntimeSessionLog(
            runId: runId,
            sessionType: "smartAlarmPreMonitoring",
            scheduledAt: Date(timeIntervalSince1970: 0),
            targetStartAt: Date(timeIntervalSince1970: 0),
            actualStartAt: Date(timeIntervalSince1970: 1),
            invalidatedAt: nil,
            invalidationReason: nil,
            startLatencySec: 1,
            didStartBeforeAlarm: true,
            didReachRingTime: false,
            errorCode: nil,
            errorMessage: nil
        ), nextFireAt: Date(timeIntervalSince1970: 20), runLogger: logger)
        engine.ringTimeReached(runLogger: logger, at: Date(timeIntervalSince1970: 20))

        var freshness = SensorFreshness.fixture(
            motionLastSampleAgeSec: 1,
            hrLastSampleAgeSec: nil,
            baselineHRConfidence: .none,
            watchWornConfidence: .medium
        )
        freshness.runId = runId
        var summary = SensorSummary.fixture(
            motionContinuitySec: 12,
            postureDelta: 50,
            gyroPeak: 3,
            stepDelta: 1,
            interactionCount: 1,
            hrDeltaFromBaseline: nil
        )
        summary.runId = runId

        let first = engine.evaluateAwake(
            summary: summary,
            freshness: freshness,
            now: Date(timeIntervalSince1970: 23),
            runLogger: logger
        )
        XCTAssertEqual(first?.shouldAutoSilence, true)
        XCTAssertEqual(engine.state, .awakeCandidate)
        XCTAssertEqual(ringer.stopCallCount, 0)

        _ = engine.evaluateAwake(
            summary: summary,
            freshness: freshness,
            now: Date(timeIntervalSince1970: 35),
            runLogger: logger
        )
        XCTAssertEqual(engine.state, .silencedMonitoring)
        XCTAssertEqual(ringer.stopCallCount, 1)
        XCTAssertTrue(logger.stateTransitionLogs.contains { $0.toState == .silencedMonitoring && $0.confidence != nil })
        XCTAssertTrue(logger.channelLogs.contains { $0.stoppedAt == Date(timeIntervalSince1970: 35) && $0.userVisibleState == "auto_silenced" })
        XCTAssertTrue(logger.outcomeLogs.contains { $0.autoSilenceAccepted })
    }

    func testAutoSilenceRejectsHeartRateOnlyEvidence() {
        let ringer = FakeWatchAlarmRinger()
        let logger = FakeWatchAlarmRunLogger()
        let flags = FeatureFlags(
            autoSilenceEnabled: true,
            reSleepDetectionEnabled: false,
            gestureSnoozeEnabled: true,
            heartRateBoostEnabled: true,
            maxReAlarmCount: 2
        )
        let engine = WatchAlarmRunEngine(ringer: ringer, featureFlags: flags)
        let runId = UUID()
        engine.runtimeDidStart(RuntimeSessionLog(
            runId: runId,
            sessionType: "smartAlarmPreMonitoring",
            scheduledAt: Date(timeIntervalSince1970: 0),
            targetStartAt: Date(timeIntervalSince1970: 0),
            actualStartAt: Date(timeIntervalSince1970: 1),
            invalidatedAt: nil,
            invalidationReason: nil,
            startLatencySec: 1,
            didStartBeforeAlarm: true,
            didReachRingTime: false,
            errorCode: nil,
            errorMessage: nil
        ), nextFireAt: Date(timeIntervalSince1970: 20), runLogger: logger)
        engine.ringTimeReached(runLogger: logger, at: Date(timeIntervalSince1970: 20))
        var freshness = SensorFreshness.fixture(
            motionLastSampleAgeSec: 1,
            hrLastSampleAgeSec: 30,
            baselineHRConfidence: .medium,
            watchWornConfidence: .medium
        )
        freshness.runId = runId
        var summary = SensorSummary.fixture(
            motionContinuitySec: 0,
            postureDelta: 0,
            gyroPeak: 0,
            stepDelta: 0,
            interactionCount: 0,
            hrDeltaFromBaseline: 20
        )
        summary.runId = runId

        let result = engine.evaluateAwake(
            summary: summary,
            freshness: freshness,
            now: Date(timeIntervalSince1970: 23),
            runLogger: logger
        )

        XCTAssertEqual(result?.shouldAutoSilence, false)
        XCTAssertEqual(engine.state, .ringing)
        XCTAssertEqual(ringer.stopCallCount, 0)
    }

    func testAutoSilenceRejectsStaleMotionAndReturnsToOriginState() {
        let ringer = FakeWatchAlarmRinger()
        let logger = FakeWatchAlarmRunLogger()
        let flags = FeatureFlags(
            autoSilenceEnabled: true,
            reSleepDetectionEnabled: false,
            gestureSnoozeEnabled: true,
            heartRateBoostEnabled: true,
            maxReAlarmCount: 2
        )
        let engine = WatchAlarmRunEngine(ringer: ringer, featureFlags: flags)
        let runId = UUID()
        engine.runtimeDidStart(RuntimeSessionLog(
            runId: runId,
            sessionType: "smartAlarmPreMonitoring",
            scheduledAt: Date(timeIntervalSince1970: 0),
            targetStartAt: Date(timeIntervalSince1970: 0),
            actualStartAt: Date(timeIntervalSince1970: 1),
            invalidatedAt: nil,
            invalidationReason: nil,
            startLatencySec: 1,
            didStartBeforeAlarm: true,
            didReachRingTime: false,
            errorCode: nil,
            errorMessage: nil
        ), nextFireAt: Date(timeIntervalSince1970: 20), runLogger: logger)
        engine.ringTimeReached(runLogger: logger, at: Date(timeIntervalSince1970: 20))
        var activeSummary = SensorSummary.fixture(
            motionContinuitySec: 12,
            postureDelta: 50,
            gyroPeak: 3,
            stepDelta: 1,
            interactionCount: 1,
            hrDeltaFromBaseline: nil
        )
        activeSummary.runId = runId
        var fresh = SensorFreshness.fixture(
            motionLastSampleAgeSec: 1,
            hrLastSampleAgeSec: nil,
            baselineHRConfidence: .none,
            watchWornConfidence: .medium
        )
        fresh.runId = runId
        _ = engine.evaluateAwake(
            summary: activeSummary,
            freshness: fresh,
            now: Date(timeIntervalSince1970: 23),
            runLogger: logger
        )
        XCTAssertEqual(engine.state, .awakeCandidate)

        var staleFreshness = SensorFreshness.fixture(
            motionLastSampleAgeSec: 5,
            hrLastSampleAgeSec: nil,
            baselineHRConfidence: .none,
            watchWornConfidence: .medium
        )
        staleFreshness.runId = runId
        let stale = engine.evaluateAwake(
            summary: activeSummary,
            freshness: staleFreshness,
            now: Date(timeIntervalSince1970: 24),
            runLogger: logger
        )

        XCTAssertEqual(stale?.shouldAutoSilence, false)
        XCTAssertEqual(engine.state, .ringing)
        XCTAssertEqual(ringer.stopCallCount, 0)
        XCTAssertTrue(logger.stateTransitionLogs.contains { $0.toState == .ringing && $0.reason == "awake_candidate_rejected" })
    }

    func testReSleepRiskReRingsAndLogsRiskReasonAfterGracePeriod() {
        let ringer = FakeWatchAlarmRinger()
        let logger = FakeWatchAlarmRunLogger()
        let flags = FeatureFlags(
            autoSilenceEnabled: true,
            reSleepDetectionEnabled: true,
            gestureSnoozeEnabled: true,
            heartRateBoostEnabled: true,
            maxReAlarmCount: 2
        )
        let engine = WatchAlarmRunEngine(ringer: ringer, featureFlags: flags)
        let runId = UUID()
        engine.runtimeDidStart(RuntimeSessionLog(
            runId: runId,
            sessionType: "smartAlarmPreMonitoring",
            scheduledAt: Date(timeIntervalSince1970: 0),
            targetStartAt: Date(timeIntervalSince1970: 0),
            actualStartAt: Date(timeIntervalSince1970: 1),
            invalidatedAt: nil,
            invalidationReason: nil,
            startLatencySec: 1,
            didStartBeforeAlarm: true,
            didReachRingTime: false,
            errorCode: nil,
            errorMessage: nil
        ), nextFireAt: Date(timeIntervalSince1970: 20), runLogger: logger)
        engine.autoSilenceConfirmed(at: Date(timeIntervalSince1970: 0))
        var freshness = SensorFreshness.fixture(
            motionLastSampleAgeSec: 1,
            hrLastSampleAgeSec: nil,
            baselineHRConfidence: .none,
            watchWornConfidence: .medium
        )
        freshness.runId = runId
        var summary = SensorSummary.fixture(
            motionContinuitySec: 0,
            postureDelta: 1,
            gyroPeak: 0,
            stepDelta: 0,
            interactionCount: 0,
            hrDeltaFromBaseline: nil
        )
        summary.runId = runId
        summary.stillnessDurationSec = 180

        let result = engine.evaluateReSleep(
            summary: summary,
            freshness: freshness,
            now: Date(timeIntervalSince1970: 180),
            runLogger: logger
        )

        XCTAssertEqual(result?.shouldReRing, true)
        XCTAssertEqual(engine.state, .reRinging)
        XCTAssertEqual(ringer.startCallCount, 1)
        XCTAssertTrue(logger.stateTransitionLogs.contains { $0.toState == .reRinging && ($0.reason.contains("lowMotion")) })
        XCTAssertTrue(logger.channelLogs.contains { $0.userVisibleState == "re_ringing" && $0.firedAt == Date(timeIntervalSince1970: 180) })
    }
}
