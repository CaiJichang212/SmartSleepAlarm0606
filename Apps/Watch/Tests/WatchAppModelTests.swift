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
        XCTAssertEqual(connectivity.outboundMessages.count, 4)

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
        XCTAssertEqual(connectivity.outboundMessages.count, 4)
    }
}
