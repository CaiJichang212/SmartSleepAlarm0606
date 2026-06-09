import XCTest
@testable import SmartSleepWatch
import SmartSleepCore

@MainActor
final class WatchAppModelTests: XCTestCase {
    func testCancelForDifferentAlarmKeepsCurrentConfig() {
        let alarm = Alarm.fixture(smartEnabled: true)
        let payload = AlarmConfigPayload(
            alarm: alarm,
            nextFireAt: Date.now.addingTimeInterval(3_600)
        )
        let connectivity = FakeWatchConnectivityClient(latestAlarmConfig: payload)
        let passingPreflight = makePassingPreflight()
        let model = WatchAppModel(
            connectivity: connectivity,
            runtimeScheduler: FakeRuntimeSessionScheduler(shouldSucceed: true),
            ringer: FakeWatchAlarmRinger(),
            preflightChecker: passingPreflight
        )

        connectivity.deliverCancellation(for: UUID())

        XCTAssertEqual(model.lastConfig?.alarm.id, alarm.id)
        XCTAssertNil(model.failureReason)
    }

    func testArmWithoutConfigFailsClosedAndReportsArmingFailure() {
        let connectivity = FakeWatchConnectivityClient()
        let model = WatchAppModel(connectivity: connectivity)

        model.armCurrentAlarm()

        XCTAssertEqual(model.currentState, .fallbackPhoneAlarm)
        XCTAssertFalse(model.sessionScheduled)
        XCTAssertEqual(model.failureReason, "missing_alarm_config")
        XCTAssertEqual(connectivity.outboundMessages.count, 1)
    }

    func testArmWithConfigAndFailedRuntimeReportsFallback() {
        let alarm = Alarm.fixture(smartEnabled: true)
        let payload = AlarmConfigPayload(
            alarm: alarm,
            nextFireAt: Date.now.addingTimeInterval(3_600)
        )
        let connectivity = FakeWatchConnectivityClient(latestAlarmConfig: payload)
        let passingPreflight = makePassingPreflight()
        let model = WatchAppModel(
            connectivity: connectivity,
            runtimeScheduler: FakeRuntimeSessionScheduler(shouldSucceed: false),
            ringer: FakeWatchAlarmRinger(),
            preflightChecker: passingPreflight
        )

        model.armCurrentAlarm()

        XCTAssertEqual(model.currentState, .fallbackPhoneAlarm)
        XCTAssertFalse(model.sessionScheduled)
        XCTAssertEqual(model.failureReason, "runtime_session_not_scheduled")
        XCTAssertEqual(connectivity.outboundMessages.count, 2)

        let armingFailures = connectivity.outboundMessages.compactMap { message -> ArmingResultPayload? in
            guard case let .armingResult(payload) = message else { return nil }
            return payload
        }
        let sessionFailures = connectivity.outboundMessages.compactMap { message -> SessionResultPayload? in
            guard case let .sessionResult(payload) = message else { return nil }
            return payload
        }

        XCTAssertTrue(armingFailures.contains {
            $0.alarmId == alarm.id && $0.status.failureReason == "runtime_session_not_scheduled"
        })
        XCTAssertTrue(sessionFailures.contains {
            $0.alarmId == alarm.id && $0.failureReason == "runtime_session_not_scheduled"
        })
    }

    func testConfigRemovalAfterArmingInvalidatesRuntimeAndClearsSession() {
        let alarm = Alarm.fixture(smartEnabled: true)
        let payload = AlarmConfigPayload(
            alarm: alarm,
            nextFireAt: Date.now.addingTimeInterval(3_600)
        )
        let connectivity = FakeWatchConnectivityClient(latestAlarmConfig: payload)
        let runtimeScheduler = FakeRuntimeSessionScheduler(shouldSucceed: true)
        let passingPreflight = makePassingPreflight()
        let model = WatchAppModel(
            connectivity: connectivity,
            runtimeScheduler: runtimeScheduler,
            ringer: FakeWatchAlarmRinger(),
            preflightChecker: passingPreflight
        )

        model.armCurrentAlarm()
        connectivity.deliverCancellation(for: alarm.id)

        XCTAssertFalse(model.sessionScheduled)
        XCTAssertEqual(model.currentState, .needsWatchArming)
        XCTAssertEqual(model.failureReason, "missing_alarm_config")
        XCTAssertEqual(runtimeScheduler.invalidateCallCount, 1)
    }

    func testRuntimeInvalidationAfterArmDowngradesStateAndResendsStatusToPhone() {
        let alarm = Alarm.fixture(smartEnabled: true)
        let payload = AlarmConfigPayload(
            alarm: alarm,
            nextFireAt: Date.now.addingTimeInterval(3_600)
        )
        let connectivity = FakeWatchConnectivityClient(latestAlarmConfig: payload)
        let runtimeScheduler = FakeRuntimeSessionScheduler(shouldSucceed: true)
        let passingPreflight = makePassingPreflight()
        let model = WatchAppModel(
            connectivity: connectivity,
            runtimeScheduler: runtimeScheduler,
            ringer: FakeWatchAlarmRinger(),
            preflightChecker: passingPreflight
        )

        model.armCurrentAlarm()
        runtimeScheduler.emitInvalidation(
            RuntimeSessionLog(
                runId: runtimeScheduler.lastRunID ?? UUID(),
                sessionType: "fakeSmartAlarmPreMonitoring",
                scheduledAt: Date(timeIntervalSince1970: 0),
                targetStartAt: Date(timeIntervalSince1970: 0),
                actualStartAt: Date(timeIntervalSince1970: 10),
                invalidatedAt: Date(timeIntervalSince1970: 20),
                invalidationReason: "expired",
                startLatencySec: 10,
                didStartBeforeAlarm: true,
                didReachRingTime: false,
                errorCode: "runtime_session_invalidated",
                errorMessage: "expired"
            )
        )

        XCTAssertFalse(model.sessionScheduled)
        XCTAssertEqual(model.currentState, .fallbackPhoneAlarm)
        XCTAssertEqual(model.failureReason, "runtime_session_invalidated")
        XCTAssertEqual(connectivity.outboundMessages.count, 5)
    }

    func testRuntimeStartAndMotionStaleAreRecordedAsStateTransitions() async {
        let alarm = Alarm.fixture(smartEnabled: true)
        let payload = AlarmConfigPayload(
            alarm: alarm,
            nextFireAt: Date.now.addingTimeInterval(3_600)
        )
        let connectivity = FakeWatchConnectivityClient(latestAlarmConfig: payload)
        let runtimeScheduler = FakeRuntimeSessionScheduler(shouldSucceed: true)
        let ringer = FakeWatchAlarmRinger()
        let logger = FakeWatchAlarmRunLogger()
        let sensorSampler = FakeWatchSensorSampler()
        let passingPreflight = makePassingPreflight()
        let model = WatchAppModel(
            connectivity: connectivity,
            runtimeScheduler: runtimeScheduler,
            ringer: ringer,
            runLogger: logger,
            sensorSampler: sensorSampler,
            preflightChecker: passingPreflight
        )

        model.armCurrentAlarm()
        let runId = try! XCTUnwrap(runtimeScheduler.lastRunID)
        runtimeScheduler.emitStart(
            RuntimeSessionLog(
                runId: runId,
                sessionType: "fakeSmartAlarmPreMonitoring",
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
            )
        )
        sensorSampler.emitFreshness(
            SensorFreshness(
                runId: runId,
                timestamp: Date(timeIntervalSince1970: 2),
                motionSampleCount: 5,
                motionLastSampleAgeSec: 3,
                hrSampleCount: 0,
                hrLastSampleAgeSec: nil,
                baselineHRConfidence: .none,
                baselineMotionConfidence: .low,
                watchWornConfidence: .medium,
                sensorConfidence: .low
            )
        )
        await flushMainActorWork()

        XCTAssertEqual(model.currentState, .ringingNoSmart)
        XCTAssertEqual(logger.stateTransitionLogs.map(\.toState), [.sessionScheduled, .preMonitoring, .ringingNoSmart])
    }

    func testRuntimeInvalidationIsRecordedAsStateTransition() {
        let alarm = Alarm.fixture(smartEnabled: true)
        let payload = AlarmConfigPayload(
            alarm: alarm,
            nextFireAt: Date.now.addingTimeInterval(3_600)
        )
        let connectivity = FakeWatchConnectivityClient(latestAlarmConfig: payload)
        let runtimeScheduler = FakeRuntimeSessionScheduler(shouldSucceed: true)
        let logger = FakeWatchAlarmRunLogger()
        let passingPreflight = makePassingPreflight()
        let model = WatchAppModel(
            connectivity: connectivity,
            runtimeScheduler: runtimeScheduler,
            ringer: FakeWatchAlarmRinger(),
            runLogger: logger,
            preflightChecker: passingPreflight
        )

        model.armCurrentAlarm()
        runtimeScheduler.emitInvalidation(
            RuntimeSessionLog(
                runId: runtimeScheduler.lastRunID ?? UUID(),
                sessionType: "fakeSmartAlarmPreMonitoring",
                scheduledAt: Date(timeIntervalSince1970: 0),
                targetStartAt: Date(timeIntervalSince1970: 0),
                actualStartAt: Date(timeIntervalSince1970: 10),
                invalidatedAt: Date(timeIntervalSince1970: 20),
                invalidationReason: "expired",
                startLatencySec: 10,
                didStartBeforeAlarm: true,
                didReachRingTime: false,
                errorCode: "runtime_session_invalidated",
                errorMessage: "expired"
            )
        )

        XCTAssertEqual(logger.stateTransitionLogs.last?.toState, .fallbackPhoneAlarm)
        XCTAssertEqual(logger.stateTransitionLogs.last?.errorCode, "runtime_session_invalidated")
    }

    func testStopAfterRuntimeRunSendsRunLogSummaryWithLoggerEventCount() async {
        let alarm = Alarm.fixture(smartEnabled: true)
        let payload = AlarmConfigPayload(alarm: alarm, nextFireAt: Date.now.addingTimeInterval(3_600))
        let connectivity = FakeWatchConnectivityClient(latestAlarmConfig: payload)
        let runtimeScheduler = FakeRuntimeSessionScheduler(shouldSucceed: true)
        let logger = FakeWatchAlarmRunLogger()
        let passingPreflight = makePassingPreflight()
        let model = WatchAppModel(
            connectivity: connectivity,
            runtimeScheduler: runtimeScheduler,
            ringer: FakeWatchAlarmRinger(),
            runLogger: logger,
            preflightChecker: passingPreflight
        )

        model.armCurrentAlarm()
        let runId = try! XCTUnwrap(runtimeScheduler.lastRunID)
        runtimeScheduler.emitStart(RuntimeSessionLog(
            runId: runId,
            sessionType: "fakeSmartAlarmPreMonitoring",
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
        ))
        await flushMainActorWork()
        model.simulateRinging()
        model.stop()

        let summaries = connectivity.outboundMessages.compactMap { message -> RunLogSummaryPayload? in
            guard case let .runLogSummary(payload) = message else { return nil }
            return payload
        }
        let summary = try! XCTUnwrap(summaries.last)
        XCTAssertEqual(summary.runId, runId)
        XCTAssertEqual(summary.finalState, .completed)
        XCTAssertEqual(summary.outcome, .userStopped)
        XCTAssertEqual(summary.eventCount, try logger.eventCount(runId: runId))
    }

    func testRuntimeInvalidationSendsRunLogSummaryWithFallbackUsed() {
        let alarm = Alarm.fixture(smartEnabled: true)
        let payload = AlarmConfigPayload(alarm: alarm, nextFireAt: Date.now.addingTimeInterval(3_600))
        let connectivity = FakeWatchConnectivityClient(latestAlarmConfig: payload)
        let runtimeScheduler = FakeRuntimeSessionScheduler(shouldSucceed: true)
        let logger = FakeWatchAlarmRunLogger()
        let passingPreflight = makePassingPreflight()
        let model = WatchAppModel(
            connectivity: connectivity,
            runtimeScheduler: runtimeScheduler,
            ringer: FakeWatchAlarmRinger(),
            runLogger: logger,
            preflightChecker: passingPreflight
        )

        model.armCurrentAlarm()
        let runId = try! XCTUnwrap(runtimeScheduler.lastRunID)
        runtimeScheduler.emitInvalidation(RuntimeSessionLog(
            runId: runId,
            sessionType: "fakeSmartAlarmPreMonitoring",
            scheduledAt: Date(timeIntervalSince1970: 0),
            targetStartAt: Date(timeIntervalSince1970: 0),
            actualStartAt: Date(timeIntervalSince1970: 10),
            invalidatedAt: Date(timeIntervalSince1970: 20),
            invalidationReason: "expired",
            startLatencySec: 10,
            didStartBeforeAlarm: true,
            didReachRingTime: false,
            errorCode: "runtime_session_invalidated",
            errorMessage: "expired"
        ))

        let summaries = connectivity.outboundMessages.compactMap { message -> RunLogSummaryPayload? in
            guard case let .runLogSummary(payload) = message else { return nil }
            return payload
        }
        let summary = try! XCTUnwrap(summaries.last)
        XCTAssertEqual(summary.runId, runId)
        XCTAssertEqual(summary.finalState, .fallbackPhoneAlarm)
        XCTAssertNil(summary.outcome)
        XCTAssertEqual(summary.fallbackUsed, true)
        XCTAssertEqual(summary.eventCount, try logger.eventCount(runId: runId))
    }

    func testLowBatteryPreflightFailsClosedBeforeSchedulingRuntime() {
        let alarm = Alarm.fixture(smartEnabled: true)
        let payload = AlarmConfigPayload(alarm: alarm, nextFireAt: Date.now.addingTimeInterval(3_600))
        let connectivity = FakeWatchConnectivityClient(latestAlarmConfig: payload)
        let runtimeScheduler = FakeRuntimeSessionScheduler(shouldSucceed: true)
        let preflight = FakeWatchPreflightChecker(result: WatchPreflightResult(
            canArmSmartMode: false,
            batteryLevel: 0.08,
            motionAvailable: true,
            failureReason: "watch_battery_low"
        ))
        let model = WatchAppModel(
            connectivity: connectivity,
            runtimeScheduler: runtimeScheduler,
            ringer: FakeWatchAlarmRinger(),
            preflightChecker: preflight
        )

        model.armCurrentAlarm()

        XCTAssertEqual(model.currentState, .fallbackPhoneAlarm)
        XCTAssertFalse(model.sessionScheduled)
        XCTAssertEqual(model.failureReason, "watch_battery_low")
        XCTAssertNil(runtimeScheduler.lastRunID)
        let arming = connectivity.outboundMessages.compactMap { message -> ArmingResultPayload? in
            guard case let .armingResult(payload) = message else { return nil }
            return payload
        }.last
        XCTAssertEqual(arming?.status.isArmed, false)
        XCTAssertEqual(arming?.status.sessionScheduled, false)

        let sessionResults = connectivity.outboundMessages.compactMap { message -> SessionResultPayload? in
            guard case let .sessionResult(payload) = message else { return nil }
            return payload
        }
        let sessionResult = try! XCTUnwrap(sessionResults.last)
        XCTAssertEqual(sessionResult.alarmId, alarm.id)
        XCTAssertEqual(sessionResult.state, .fallbackPhoneAlarm)
        XCTAssertEqual(sessionResult.failureReason, "watch_battery_low")

        let summaries = connectivity.outboundMessages.compactMap { message -> RunLogSummaryPayload? in
            guard case let .runLogSummary(payload) = message else { return nil }
            return payload
        }
        let summary = try! XCTUnwrap(summaries.last)
        XCTAssertEqual(summary.runId, sessionResult.runId)
        XCTAssertEqual(summary.finalState, .fallbackPhoneAlarm)
        XCTAssertTrue(summary.fallbackUsed)
    }

    func testSummaryDrivesAutoSilenceWhenExperimentFlagEnabled() async {
        let alarm = Alarm.fixture(smartEnabled: true)
        let payload = AlarmConfigPayload(alarm: alarm, nextFireAt: Date(timeIntervalSinceNow: 3_600))
        let connectivity = FakeWatchConnectivityClient(latestAlarmConfig: payload)
        let runtimeScheduler = FakeRuntimeSessionScheduler(shouldSucceed: true)
        let ringer = FakeWatchAlarmRinger()
        let logger = FakeWatchAlarmRunLogger()
        let sensorSampler = FakeWatchSensorSampler()
        let flags = FeatureFlags(
            autoSilenceEnabled: true,
            reSleepDetectionEnabled: false,
            gestureSnoozeEnabled: true,
            heartRateBoostEnabled: true,
            maxReAlarmCount: 2
        )
        let model = WatchAppModel(
            connectivity: connectivity,
            runtimeScheduler: runtimeScheduler,
            ringer: ringer,
            runLogger: logger,
            sensorSampler: sensorSampler,
            preflightChecker: makePassingPreflight(),
            engineFactory: WatchAlarmRunEngineFactory(featureFlags: flags)
        )

        model.armCurrentAlarm()
        let runId = try! XCTUnwrap(runtimeScheduler.lastRunID)
        runtimeScheduler.emitStart(RuntimeSessionLog(
            runId: runId,
            sessionType: "fakeSmartAlarmPreMonitoring",
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
        ))
        await flushMainActorWork()
        model.simulateRinging()
        var freshness = SensorFreshness.fixture(
            motionLastSampleAgeSec: 1,
            hrLastSampleAgeSec: nil,
            baselineHRConfidence: .none,
            watchWornConfidence: .medium
        )
        freshness.runId = runId
        sensorSampler.emitFreshness(freshness)
        var firstSummary = SensorSummary.fixture(
            motionContinuitySec: 12,
            postureDelta: 50,
            gyroPeak: 3,
            stepDelta: 1,
            interactionCount: 1,
            hrDeltaFromBaseline: nil
        )
        firstSummary.runId = runId
        firstSummary.windowEnd = Date(timeIntervalSince1970: 23)
        sensorSampler.emitSummary(firstSummary)
        await flushMainActorWork()

        XCTAssertEqual(model.currentState, .awakeCandidate)
        XCTAssertEqual(ringer.stopCallCount, 0)

        var secondSummary = SensorSummary.fixture(
            motionContinuitySec: 12,
            postureDelta: 50,
            gyroPeak: 3,
            stepDelta: 1,
            interactionCount: 1,
            hrDeltaFromBaseline: nil
        )
        secondSummary.runId = runId
        secondSummary.windowEnd = Date(timeIntervalSince1970: 35)
        sensorSampler.emitSummary(secondSummary)
        await flushMainActorWork()

        XCTAssertEqual(model.currentState, .silencedMonitoring)
        XCTAssertEqual(ringer.stopCallCount, 1)
        XCTAssertTrue(logger.stateTransitionLogs.contains { $0.toState == .silencedMonitoring })
        XCTAssertTrue(logger.channelLogs.contains { $0.userVisibleState == "auto_silenced" })
        XCTAssertTrue(logger.freshnessLogs.contains { $0.runId == runId && $0.motionFresh })
        XCTAssertTrue(logger.summaryLogs.contains { $0.runId == runId && $0.windowEnd == Date(timeIntervalSince1970: 35) })
    }

    func testSummaryDrivesReSleepDetectionWhenExperimentFlagEnabled() async {
        let alarm = Alarm.fixture(smartEnabled: true)
        let payload = AlarmConfigPayload(alarm: alarm, nextFireAt: Date(timeIntervalSinceNow: 3_600))
        let connectivity = FakeWatchConnectivityClient(latestAlarmConfig: payload)
        let runtimeScheduler = FakeRuntimeSessionScheduler(shouldSucceed: true)
        let ringer = FakeWatchAlarmRinger()
        let logger = FakeWatchAlarmRunLogger()
        let sensorSampler = FakeWatchSensorSampler()
        let flags = FeatureFlags(
            autoSilenceEnabled: true,
            reSleepDetectionEnabled: true,
            gestureSnoozeEnabled: true,
            heartRateBoostEnabled: true,
            maxReAlarmCount: 2
        )
        let model = WatchAppModel(
            connectivity: connectivity,
            runtimeScheduler: runtimeScheduler,
            ringer: ringer,
            runLogger: logger,
            sensorSampler: sensorSampler,
            preflightChecker: makePassingPreflight(),
            engineFactory: WatchAlarmRunEngineFactory(featureFlags: flags)
        )

        model.armCurrentAlarm()
        let runId = try! XCTUnwrap(runtimeScheduler.lastRunID)
        runtimeScheduler.emitStart(RuntimeSessionLog(
            runId: runId,
            sessionType: "fakeSmartAlarmPreMonitoring",
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
        ))
        await flushMainActorWork()
        model.simulateRinging()
        var freshness = SensorFreshness.fixture(
            motionLastSampleAgeSec: 1,
            hrLastSampleAgeSec: nil,
            baselineHRConfidence: .none,
            watchWornConfidence: .medium
        )
        freshness.runId = runId
        sensorSampler.emitFreshness(freshness)
        var awakeSummary = SensorSummary.fixture(
            motionContinuitySec: 12,
            postureDelta: 50,
            gyroPeak: 3,
            stepDelta: 1,
            interactionCount: 1,
            hrDeltaFromBaseline: nil
        )
        awakeSummary.runId = runId
        awakeSummary.windowEnd = Date(timeIntervalSince1970: 23)
        sensorSampler.emitSummary(awakeSummary)
        awakeSummary.windowEnd = Date(timeIntervalSince1970: 35)
        sensorSampler.emitSummary(awakeSummary)
        await flushMainActorWork()
        XCTAssertEqual(model.currentState, .silencedMonitoring)

        var reSleepSummary = SensorSummary.fixture(
            motionContinuitySec: 0,
            postureDelta: 1,
            gyroPeak: 0,
            stepDelta: 0,
            interactionCount: 0,
            hrDeltaFromBaseline: nil
        )
        reSleepSummary.runId = runId
        reSleepSummary.stillnessDurationSec = 180
        reSleepSummary.windowEnd = Date(timeIntervalSince1970: 220)
        sensorSampler.emitSummary(reSleepSummary)
        await flushMainActorWork()

        XCTAssertEqual(model.currentState, .reRinging)
        XCTAssertEqual(ringer.startCallCount, 2)
        XCTAssertTrue(logger.stateTransitionLogs.contains { $0.toState == .reRinging && $0.reason.contains("re_sleep_risk_detected") })
        XCTAssertTrue(logger.freshnessLogs.contains { $0.runId == runId && $0.motionFresh })
        XCTAssertTrue(logger.summaryLogs.contains {
            $0.runId == runId
                && $0.stillnessDurationSec == 180
                && $0.stepDelta == 0
                && $0.interactionCount == 0
        })
    }

    private func flushMainActorWork() async {
        for _ in 0..<3 {
            await Task.yield()
        }
    }

    private func makePassingPreflight() -> FakeWatchPreflightChecker {
        FakeWatchPreflightChecker(result: WatchPreflightResult(
            canArmSmartMode: true,
            batteryLevel: 0.80,
            motionAvailable: true,
            failureReason: nil
        ))
    }
}

final class FakeWatchPreflightChecker: WatchPreflightChecking {
    var result: WatchPreflightResult

    init(result: WatchPreflightResult) {
        self.result = result
    }

    func check(nextFireAt: Date, now: Date) -> WatchPreflightResult {
        result
    }
}
