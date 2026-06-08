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
}
