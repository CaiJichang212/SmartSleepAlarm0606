import XCTest
@testable import SmartSleepWatch
import SmartSleepCore

@MainActor
final class WatchAppModelTests: XCTestCase {
    func testCancelForDifferentAlarmKeepsCurrentConfig() {
        let alarm = Alarm.fixture(smartEnabled: true)
        let payload = AlarmConfigPayload(
            alarm: alarm,
            nextFireAt: Date(timeIntervalSince1970: 3_600)
        )
        let connectivity = FakeWatchConnectivityClient(latestAlarmConfig: payload)
        let model = WatchAppModel(
            connectivity: connectivity,
            runtimeScheduler: FakeRuntimeSessionScheduler(shouldSucceed: true),
            ringer: FakeWatchAlarmRinger()
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
            nextFireAt: Date(timeIntervalSince1970: 3_600)
        )
        let connectivity = FakeWatchConnectivityClient(latestAlarmConfig: payload)
        let model = WatchAppModel(
            connectivity: connectivity,
            runtimeScheduler: FakeRuntimeSessionScheduler(shouldSucceed: false),
            ringer: FakeWatchAlarmRinger()
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
            nextFireAt: Date(timeIntervalSince1970: 3_600)
        )
        let connectivity = FakeWatchConnectivityClient(latestAlarmConfig: payload)
        let runtimeScheduler = FakeRuntimeSessionScheduler(shouldSucceed: true)
        let model = WatchAppModel(
            connectivity: connectivity,
            runtimeScheduler: runtimeScheduler,
            ringer: FakeWatchAlarmRinger()
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
            nextFireAt: Date(timeIntervalSince1970: 3_600)
        )
        let connectivity = FakeWatchConnectivityClient(latestAlarmConfig: payload)
        let runtimeScheduler = FakeRuntimeSessionScheduler(shouldSucceed: true)
        let model = WatchAppModel(
            connectivity: connectivity,
            runtimeScheduler: runtimeScheduler,
            ringer: FakeWatchAlarmRinger()
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
            nextFireAt: Date(timeIntervalSince1970: 3_600)
        )
        let connectivity = FakeWatchConnectivityClient(latestAlarmConfig: payload)
        let runtimeScheduler = FakeRuntimeSessionScheduler(shouldSucceed: true)
        let ringer = FakeWatchAlarmRinger()
        let logger = FakeWatchAlarmRunLogger()
        let sensorSampler = FakeWatchSensorSampler()
        let model = WatchAppModel(
            connectivity: connectivity,
            runtimeScheduler: runtimeScheduler,
            ringer: ringer,
            runLogger: logger,
            sensorSampler: sensorSampler
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
            nextFireAt: Date(timeIntervalSince1970: 3_600)
        )
        let connectivity = FakeWatchConnectivityClient(latestAlarmConfig: payload)
        let runtimeScheduler = FakeRuntimeSessionScheduler(shouldSucceed: true)
        let logger = FakeWatchAlarmRunLogger()
        let model = WatchAppModel(
            connectivity: connectivity,
            runtimeScheduler: runtimeScheduler,
            ringer: FakeWatchAlarmRinger(),
            runLogger: logger
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

    func testStopAfterRuntimeRunSendsRunLogSummaryWithLoggerEventCount() {
        let alarm = Alarm.fixture(smartEnabled: true)
        let payload = AlarmConfigPayload(alarm: alarm, nextFireAt: Date(timeIntervalSince1970: 3_600))
        let connectivity = FakeWatchConnectivityClient(latestAlarmConfig: payload)
        let runtimeScheduler = FakeRuntimeSessionScheduler(shouldSucceed: true)
        let logger = FakeWatchAlarmRunLogger()
        let model = WatchAppModel(
            connectivity: connectivity,
            runtimeScheduler: runtimeScheduler,
            ringer: FakeWatchAlarmRinger(),
            runLogger: logger
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
        let payload = AlarmConfigPayload(alarm: alarm, nextFireAt: Date(timeIntervalSince1970: 3_600))
        let connectivity = FakeWatchConnectivityClient(latestAlarmConfig: payload)
        let runtimeScheduler = FakeRuntimeSessionScheduler(shouldSucceed: true)
        let logger = FakeWatchAlarmRunLogger()
        let model = WatchAppModel(
            connectivity: connectivity,
            runtimeScheduler: runtimeScheduler,
            ringer: FakeWatchAlarmRinger(),
            runLogger: logger
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

    private func flushMainActorWork() async {
        for _ in 0..<3 {
            await Task.yield()
        }
    }
}
