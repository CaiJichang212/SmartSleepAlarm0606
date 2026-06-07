import XCTest
@testable import SmartSleepCore

final class SmartSleepCoreTests: XCTestCase {
    func testSmartModeReadyRequiresWatchArmingAndScheduledSession() {
        let alarm = Alarm.fixture(smartEnabled: true)

        XCTAssertEqual(SmartModeResolver.status(for: alarm, arming: nil), .needsWatchArming)

        let armedOnly = WatchArmingStatus(
            alarmId: alarm.id,
            isArmed: true,
            sessionScheduled: false,
            fallbackChannel: .iOSLocalNotification,
            failureReason: "runtime session denied"
        )
        XCTAssertEqual(SmartModeResolver.status(for: alarm, arming: armedOnly), .fallbackOnly)

        let ready = WatchArmingStatus(
            alarmId: alarm.id,
            isArmed: true,
            sessionScheduled: true,
            fallbackChannel: .iOSAlarmKit,
            failureReason: nil
        )
        XCTAssertEqual(SmartModeResolver.status(for: alarm, arming: ready), .ready)
    }

    func testStateMachineCoversMainFallbackSnoozeAndResleepPaths() throws {
        var machine = AlarmStateMachine()

        try machine.apply(.phoneCreatedAlarm)
        XCTAssertEqual(machine.state, .needsWatchArming)

        try machine.apply(.watchArmed)
        try machine.apply(.runtimeSessionScheduled)
        try machine.apply(.preMonitoringStarted)
        try machine.apply(.ringTimeReached)
        XCTAssertEqual(machine.state, .ringing)

        try machine.apply(.gestureSnoozeAccepted)
        XCTAssertEqual(machine.state, .snoozed)

        try machine.apply(.snoozeIntervalElapsed)
        XCTAssertEqual(machine.state, .ringing)

        try machine.apply(.awakeCandidateDetected)
        try machine.apply(.awakeConfirmed)
        XCTAssertEqual(machine.state, .silencedMonitoring)

        try machine.apply(.reSleepRiskDetected)
        XCTAssertEqual(machine.state, .reSleepRiskDetected)

        try machine.apply(.reRingRequested)
        XCTAssertEqual(machine.state, .reRinging)

        try machine.apply(.userStopped)
        XCTAssertEqual(machine.state, .completed)
    }

    func testInvalidTransitionThrowsAndKeepsExistingState() {
        var machine = AlarmStateMachine()

        XCTAssertThrowsError(try machine.apply(.awakeConfirmed))
        XCTAssertEqual(machine.state, .idle)
    }

    func testAwakeScorerRequiresFreshMotionAndDoesNotAllowHeartRateOnlySilence() {
        let freshness = SensorFreshness.fixture(
            motionLastSampleAgeSec: 1,
            hrLastSampleAgeSec: 30,
            baselineHRConfidence: .high,
            watchWornConfidence: .high
        )

        let heartRateOnly = SensorSummary.fixture(
            motionContinuitySec: 0,
            postureDelta: 0,
            gyroPeak: 0,
            stepDelta: 0,
            interactionCount: 0,
            hrDeltaFromBaseline: 30
        )
        let hrOnlyResult = AwakeScorer().evaluate(summary: heartRateOnly, freshness: freshness)
        XCTAssertFalse(hrOnlyResult.shouldAutoSilence)
        XCTAssertTrue(hrOnlyResult.reasonCodes.contains(.heartRateOnlyRejected))

        let staleMotion = SensorFreshness.fixture(
            motionLastSampleAgeSec: 5,
            hrLastSampleAgeSec: 30,
            baselineHRConfidence: .high,
            watchWornConfidence: .high
        )
        let movement = SensorSummary.fixture(
            motionContinuitySec: 14,
            postureDelta: 65,
            gyroPeak: 4.2,
            stepDelta: 4,
            interactionCount: 1,
            hrDeltaFromBaseline: 15
        )
        let staleResult = AwakeScorer().evaluate(summary: movement, freshness: staleMotion)
        XCTAssertFalse(staleResult.shouldAutoSilence)
        XCTAssertTrue(staleResult.reasonCodes.contains(.motionStale))

        let awakeResult = AwakeScorer().evaluate(summary: movement, freshness: freshness)
        XCTAssertTrue(awakeResult.shouldAutoSilence)
        XCTAssertGreaterThanOrEqual(awakeResult.confidence, 0.8)
    }

    func testGestureSnoozeOnlyAcceptsConstrainedGestureWhileRinging() {
        let detector = GestureSnoozeDetector()
        let samples = [
            RotationSample(timestampOffsetSec: 0.1, direction: .clockwise, gyroPeak: 3.4, postureDelta: 30),
            RotationSample(timestampOffsetSec: 0.9, direction: .clockwise, gyroPeak: 3.1, postureDelta: 28)
        ]

        let accepted = detector.evaluate(
            state: .ringing,
            ringingElapsedSec: 2.2,
            motionFresh: true,
            samples: samples
        )
        XCTAssertTrue(accepted.accepted)
        XCTAssertEqual(accepted.rejectionReason, nil)

        let wrongState = detector.evaluate(
            state: .silencedMonitoring,
            ringingElapsedSec: 2.2,
            motionFresh: true,
            samples: samples
        )
        XCTAssertFalse(wrongState.accepted)
        XCTAssertEqual(wrongState.rejectionReason, .invalidState)

        let cooldown = detector.evaluate(
            state: .ringing,
            ringingElapsedSec: 0.8,
            motionFresh: true,
            samples: samples
        )
        XCTAssertFalse(cooldown.accepted)
        XCTAssertEqual(cooldown.rejectionReason, .cooldown)
    }

    func testJSONLEventStoreExportsAppendOnlyEvents() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let store = try JSONLAlarmEventStore(directory: directory)
        let runId = UUID()

        try store.append(.stateTransition(StateTransitionLog(
            runId: runId,
            fromState: .ringing,
            toState: .awakeCandidate,
            timestamp: Date(timeIntervalSince1970: 10),
            reason: "motion_candidate",
            confidence: 0.62,
            featureSnapshotId: "feature-1",
            errorCode: nil
        )))
        try store.append(.channel(AlarmChannelLog(
            runId: runId,
            channel: .watchRuntimeHapticAudio,
            scheduledAt: Date(timeIntervalSince1970: 20),
            firedAt: Date(timeIntervalSince1970: 21),
            stoppedAt: nil,
            snoozedAt: nil,
            cancelledAt: nil,
            authorizationState: .authorized,
            failureReason: nil,
            userVisibleState: "ringing"
        )))

        let exported = try store.export(runId: runId)
        XCTAssertEqual(exported.count, 2)
        XCTAssertTrue(exported[0].contains("\"schemaVersion\":1"))
        XCTAssertTrue(exported[0].contains("\"stateTransition\""))
        XCTAssertTrue(exported[1].contains("\"watchRuntimeHapticAudio\""))
    }
}

