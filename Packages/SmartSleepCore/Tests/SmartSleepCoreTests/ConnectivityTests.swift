import XCTest
@testable import SmartSleepCore

final class ConnectivityTests: XCTestCase {
    func testAlarmConfigPayloadRoundTripsThroughMockTransport() throws {
        let alarm = Alarm.fixture(smartEnabled: true)
        let payload = AlarmConfigPayload(alarm: alarm, nextFireAt: Date(timeIntervalSince1970: 1_000))
        let transport = MockSmartSleepTransport()

        try transport.send(.alarmConfig(payload), direction: .phoneToWatch)

        XCTAssertEqual(transport.deliveredMessages.count, 1)
        XCTAssertEqual(transport.deliveredMessages.first?.direction, .phoneToWatch)
        XCTAssertEqual(transport.deliveredMessages.first?.message, .alarmConfig(payload))
    }

    func testDisconnectedTransportStoresMessageInOutbox() throws {
        let alarm = Alarm.fixture(smartEnabled: true)
        let payload = AlarmConfigPayload(alarm: alarm, nextFireAt: Date(timeIntervalSince1970: 1_000))
        let transport = MockSmartSleepTransport(isReachable: false)

        try transport.send(.alarmConfig(payload), direction: .phoneToWatch)

        XCTAssertTrue(transport.deliveredMessages.isEmpty)
        XCTAssertEqual(transport.outbox.count, 1)
        XCTAssertEqual(transport.outbox.first?.message, .alarmConfig(payload))
    }

    func testArmingSessionAndRunSummaryPayloadsAreCodable() throws {
        let alarm = Alarm.fixture(smartEnabled: true)
        let arming = ArmingResultPayload(
            alarmId: alarm.id,
            armedAt: Date(timeIntervalSince1970: 2_000),
            status: WatchArmingStatus(
                alarmId: alarm.id,
                isArmed: true,
                sessionScheduled: true,
                fallbackChannel: .iOSAlarmKit,
                failureReason: nil
            )
        )
        let session = SessionResultPayload(
            alarmId: alarm.id,
            runId: UUID(uuidString: "00000000-0000-0000-0000-000000000002")!,
            state: .sessionScheduled,
            scheduledAt: Date(timeIntervalSince1970: 2_010),
            failureReason: nil
        )
        let summary = RunLogSummaryPayload(
            runId: session.runId,
            finalState: .completed,
            outcome: .wokeUp,
            eventCount: 12,
            fallbackUsed: false
        )

        let encoder = JSONEncoder()
        let decoder = JSONDecoder()

        XCTAssertEqual(try decoder.decode(SmartSleepConnectivityMessage.self, from: encoder.encode(SmartSleepConnectivityMessage.armingResult(arming))), .armingResult(arming))
        XCTAssertEqual(try decoder.decode(SmartSleepConnectivityMessage.self, from: encoder.encode(SmartSleepConnectivityMessage.sessionResult(session))), .sessionResult(session))
        XCTAssertEqual(try decoder.decode(SmartSleepConnectivityMessage.self, from: encoder.encode(SmartSleepConnectivityMessage.runLogSummary(summary))), .runLogSummary(summary))
    }
}

