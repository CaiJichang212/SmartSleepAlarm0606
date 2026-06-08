import XCTest
@testable import SmartSleepWatch
import SmartSleepCore

@MainActor
final class WatchAlarmRunLoggerTests: XCTestCase {
    func testLoggerExportsRuntimeChannelAndFreshnessEvents() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let logger = try WatchAlarmRunLogger(logsDirectory: directory)
        let runId = UUID()

        try logger.recordRuntimeSession(RuntimeSessionLog(
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
        ))
        try logger.recordChannel(AlarmChannelLog(
            runId: runId,
            channel: .watchRuntimeHapticAudio,
            scheduledAt: Date(timeIntervalSince1970: 20),
            firedAt: Date(timeIntervalSince1970: 20),
            stoppedAt: nil,
            snoozedAt: nil,
            cancelledAt: nil,
            authorizationState: .authorized,
            failureReason: nil,
            userVisibleState: "ringing"
        ))
        try logger.recordFreshness(SensorFreshness(
            runId: runId,
            timestamp: Date(timeIntervalSince1970: 21),
            motionSampleCount: 20,
            motionLastSampleAgeSec: 1,
            hrSampleCount: 0,
            hrLastSampleAgeSec: nil,
            baselineHRConfidence: .none,
            baselineMotionConfidence: .medium,
            watchWornConfidence: .medium,
            sensorConfidence: .medium
        ))

        let exported = try logger.export(runId: runId)
        XCTAssertTrue(exported.contains("runtimeSession"))
        XCTAssertTrue(exported.contains("watchRuntimeHapticAudio"))
        XCTAssertTrue(exported.contains("sensorFreshness"))
    }

    func testLoggerExportsStateTransitionAndOutcomeEvents() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let logger = try WatchAlarmRunLogger(logsDirectory: directory)
        let runId = UUID()

        try logger.recordStateTransition(StateTransitionLog(
            runId: runId,
            fromState: .sessionScheduled,
            toState: .preMonitoring,
            timestamp: Date(timeIntervalSince1970: 5),
            reason: "runtime_started",
            confidence: nil,
            featureSnapshotId: nil,
            errorCode: nil
        ))
        try logger.recordOutcome(OutcomeLabel(
            runId: runId,
            manualStop: true,
            manualSnooze: false,
            gestureSnooze: false,
            autoSilenceAccepted: false,
            falseSilenceReported: false,
            falseReAlarmReported: false,
            missedAlarmReported: false,
            fallbackUsed: false,
            userReportedStillAsleep: false,
            userReportedAwake: false,
            notes: "Stopped on watch",
            labeledAt: Date(timeIntervalSince1970: 6)
        ))

        let exported = try logger.export(runId: runId)
        XCTAssertTrue(exported.contains("stateTransition"))
        XCTAssertTrue(exported.contains("\"manualStop\":true"))
    }
}
