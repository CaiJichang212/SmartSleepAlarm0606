import Foundation

public enum Weekday: String, Codable, CaseIterable, Sendable {
    case monday, tuesday, wednesday, thursday, friday, saturday, sunday
}

public enum TimezonePolicy: String, Codable, Sendable {
    case deviceLocal
    case fixed
}

public enum AlarmChannel: String, Codable, CaseIterable, Sendable {
    case watchRuntimeHapticAudio
    case iOSAlarmKit
    case iOSLocalNotification
    case watchLocalNotification
    case foregroundAudio
    case manualFallbackPrompt
}

public enum AuthorizationState: String, Codable, Sendable {
    case unknown
    case notDetermined
    case authorized
    case denied
    case unavailable
}

public enum ConfidenceLevel: String, Codable, Comparable, Sendable {
    case none
    case low
    case medium
    case high

    public static func < (lhs: ConfidenceLevel, rhs: ConfidenceLevel) -> Bool {
        lhs.rank < rhs.rank
    }

    private var rank: Int {
        switch self {
        case .none: 0
        case .low: 1
        case .medium: 2
        case .high: 3
        }
    }
}

public struct Alarm: Identifiable, Codable, Equatable, Sendable {
    public var id: UUID
    public var timeOfDay: DateComponents
    public var repeatDays: Set<Weekday>
    public var timezonePolicy: TimezonePolicy
    public var label: String
    public var soundId: String
    public var isEnabled: Bool
    public var smartEnabled: Bool
    public var requiresWatchArming: Bool
    public var snoozeIntervalMin: Int
    public var maxSnoozeCount: Int
    public var maxReAlarmCount: Int
    public var backupChannelPreferred: AlarmChannel
    public var createdAt: Date
    public var updatedAt: Date

    public init(
        id: UUID = UUID(),
        timeOfDay: DateComponents,
        repeatDays: Set<Weekday>,
        timezonePolicy: TimezonePolicy = .deviceLocal,
        label: String,
        soundId: String,
        isEnabled: Bool,
        smartEnabled: Bool,
        requiresWatchArming: Bool,
        snoozeIntervalMin: Int,
        maxSnoozeCount: Int,
        maxReAlarmCount: Int,
        backupChannelPreferred: AlarmChannel,
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.timeOfDay = timeOfDay
        self.repeatDays = repeatDays
        self.timezonePolicy = timezonePolicy
        self.label = label
        self.soundId = soundId
        self.isEnabled = isEnabled
        self.smartEnabled = smartEnabled
        self.requiresWatchArming = requiresWatchArming
        self.snoozeIntervalMin = snoozeIntervalMin
        self.maxSnoozeCount = maxSnoozeCount
        self.maxReAlarmCount = maxReAlarmCount
        self.backupChannelPreferred = backupChannelPreferred
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}

public struct WatchArmingStatus: Codable, Equatable, Sendable {
    public var alarmId: UUID
    public var isArmed: Bool
    public var sessionScheduled: Bool
    public var fallbackChannel: AlarmChannel
    public var failureReason: String?

    public init(
        alarmId: UUID,
        isArmed: Bool,
        sessionScheduled: Bool,
        fallbackChannel: AlarmChannel,
        failureReason: String?
    ) {
        self.alarmId = alarmId
        self.isArmed = isArmed
        self.sessionScheduled = sessionScheduled
        self.fallbackChannel = fallbackChannel
        self.failureReason = failureReason
    }
}

public enum SmartModeStatus: String, Codable, Equatable, Sendable {
    case smartOff
    case needsWatchArming
    case ready
    case fallbackOnly
    case failed
}

public enum SmartModeResolver {
    public static func status(for alarm: Alarm, arming: WatchArmingStatus?) -> SmartModeStatus {
        guard alarm.isEnabled else { return .failed }
        guard alarm.smartEnabled else { return .smartOff }
        guard let arming, arming.alarmId == alarm.id, arming.isArmed else {
            return .needsWatchArming
        }
        return arming.sessionScheduled ? .ready : .fallbackOnly
    }
}

public struct AlarmRun: Identifiable, Codable, Equatable, Sendable {
    public var id: UUID
    public var alarmId: UUID
    public var scheduledAt: Date
    public var createdOnPhoneAt: Date?
    public var watchArmedAt: Date?
    public var sessionScheduledAt: Date?
    public var preMonitorTargetStartAt: Date?
    public var preMonitorActualStartAt: Date?
    public var ringStartedAt: Date?
    public var firstSilencedAt: Date?
    public var completedAt: Date?
    public var silenceReason: String?
    public var snoozeCount: Int
    public var reAlarmCount: Int
    public var fallbackUsed: Bool
    public var outcome: OutcomeKind?
}

public enum OutcomeKind: String, Codable, Sendable {
    case wokeUp
    case falseSilence
    case falseReAlarm
    case missedAlarm
    case userStopped
    case userSnoozed
}

public struct DeviceContext: Codable, Equatable, Sendable {
    public var runId: UUID
    public var iPhoneModel: String
    public var watchModel: String
    public var iOSVersion: String
    public var watchOSVersion: String
    public var watchBatteryAtArm: Double?
    public var watchBatteryAtRing: Double?
    public var phoneBatteryAtRing: Double?
    public var wristSide: String?
    public var watchLocked: Bool
    public var watchWornConfidence: ConfidenceLevel
    public var silentMode: Bool
    public var sleepFocus: Bool
    public var lowPowerMode: Bool
    public var bluetoothConnected: Bool
    public var wifiConnected: Bool
    public var cellularAvailable: Bool
    public var airplaneMode: Bool
}

public struct RuntimeSessionLog: Codable, Equatable, Sendable {
    public var runId: UUID
    public var sessionType: String
    public var scheduledAt: Date
    public var targetStartAt: Date
    public var actualStartAt: Date?
    public var invalidatedAt: Date?
    public var invalidationReason: String?
    public var startLatencySec: Double?
    public var didStartBeforeAlarm: Bool
    public var didReachRingTime: Bool
    public var errorCode: String?
    public var errorMessage: String?
}

public struct AlarmChannelLog: Codable, Equatable, Sendable {
    public var runId: UUID
    public var channel: AlarmChannel
    public var scheduledAt: Date
    public var firedAt: Date?
    public var stoppedAt: Date?
    public var snoozedAt: Date?
    public var cancelledAt: Date?
    public var authorizationState: AuthorizationState
    public var failureReason: String?
    public var userVisibleState: String

    public init(
        runId: UUID,
        channel: AlarmChannel,
        scheduledAt: Date,
        firedAt: Date?,
        stoppedAt: Date?,
        snoozedAt: Date?,
        cancelledAt: Date?,
        authorizationState: AuthorizationState,
        failureReason: String?,
        userVisibleState: String
    ) {
        self.runId = runId
        self.channel = channel
        self.scheduledAt = scheduledAt
        self.firedAt = firedAt
        self.stoppedAt = stoppedAt
        self.snoozedAt = snoozedAt
        self.cancelledAt = cancelledAt
        self.authorizationState = authorizationState
        self.failureReason = failureReason
        self.userVisibleState = userVisibleState
    }
}

public struct SensorFreshness: Codable, Equatable, Sendable {
    public var runId: UUID
    public var timestamp: Date
    public var motionSampleCount: Int
    public var motionLastSampleAgeSec: Double
    public var hrSampleCount: Int
    public var hrLastSampleAgeSec: Double?
    public var baselineHRConfidence: ConfidenceLevel
    public var baselineMotionConfidence: ConfidenceLevel
    public var watchWornConfidence: ConfidenceLevel
    public var sensorConfidence: ConfidenceLevel

    public var motionFresh: Bool {
        motionLastSampleAgeSec <= 2
    }

    public var heartRateUsable: Bool {
        guard let hrLastSampleAgeSec else { return false }
        return hrLastSampleAgeSec <= 120 && baselineHRConfidence >= .medium
    }
}

public struct SensorSummary: Codable, Equatable, Sendable {
    public var runId: UUID
    public var windowStart: Date
    public var windowEnd: Date
    public var baselineHR: Double?
    public var baselineMotion: Double
    public var accelMagnitudeMean: Double
    public var accelMagnitudeStd: Double
    public var gyroMagnitudeMean: Double
    public var gyroPeak: Double
    public var postureDelta: Double
    public var motionContinuitySec: Double
    public var stillnessDurationSec: Double
    public var stepDelta: Int
    public var screenWakeCount: Int
    public var interactionCount: Int
    public var missingDataDurationSec: Double
    public var batteryDelta: Double
    public var hrDeltaFromBaseline: Double?
}

public struct StateTransitionLog: Codable, Equatable, Sendable {
    public var runId: UUID
    public var fromState: SmartAlarmState
    public var toState: SmartAlarmState
    public var timestamp: Date
    public var reason: String
    public var confidence: Double?
    public var featureSnapshotId: String?
    public var errorCode: String?

    public init(
        runId: UUID,
        fromState: SmartAlarmState,
        toState: SmartAlarmState,
        timestamp: Date,
        reason: String,
        confidence: Double?,
        featureSnapshotId: String?,
        errorCode: String?
    ) {
        self.runId = runId
        self.fromState = fromState
        self.toState = toState
        self.timestamp = timestamp
        self.reason = reason
        self.confidence = confidence
        self.featureSnapshotId = featureSnapshotId
        self.errorCode = errorCode
    }
}

public enum GestureType: String, Codable, Sendable {
    case doubleWristRotation
}

public struct GestureEvent: Codable, Equatable, Sendable {
    public var runId: UUID
    public var timestamp: Date
    public var state: SmartAlarmState
    public var gestureType: GestureType
    public var gestureConfidence: Double
    public var rotationPeak: Double
    public var directionConsistency: Double
    public var cooldownPassed: Bool
    public var accepted: Bool
    public var rejectionReason: GestureRejectionReason?
}

public struct OutcomeLabel: Codable, Equatable, Sendable {
    public var runId: UUID
    public var manualStop: Bool
    public var manualSnooze: Bool
    public var gestureSnooze: Bool
    public var autoSilenceAccepted: Bool
    public var falseSilenceReported: Bool
    public var falseReAlarmReported: Bool
    public var missedAlarmReported: Bool
    public var fallbackUsed: Bool
    public var userReportedStillAsleep: Bool
    public var userReportedAwake: Bool
    public var notes: String?
    public var labeledAt: Date
}

#if DEBUG
public extension Alarm {
    static func fixture(smartEnabled: Bool = true) -> Alarm {
        Alarm(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000000001")!,
            timeOfDay: DateComponents(hour: 7, minute: 30),
            repeatDays: [.monday, .tuesday, .wednesday, .thursday, .friday],
            label: "Morning",
            soundId: "default",
            isEnabled: true,
            smartEnabled: smartEnabled,
            requiresWatchArming: true,
            snoozeIntervalMin: 9,
            maxSnoozeCount: 3,
            maxReAlarmCount: 2,
            backupChannelPreferred: .iOSAlarmKit,
            createdAt: Date(timeIntervalSince1970: 0),
            updatedAt: Date(timeIntervalSince1970: 0)
        )
    }
}

public extension SensorFreshness {
    static func fixture(
        motionLastSampleAgeSec: Double,
        hrLastSampleAgeSec: Double?,
        baselineHRConfidence: ConfidenceLevel,
        watchWornConfidence: ConfidenceLevel
    ) -> SensorFreshness {
        SensorFreshness(
            runId: UUID(),
            timestamp: Date(timeIntervalSince1970: 0),
            motionSampleCount: motionLastSampleAgeSec <= 2 ? 60 : 0,
            motionLastSampleAgeSec: motionLastSampleAgeSec,
            hrSampleCount: hrLastSampleAgeSec == nil ? 0 : 1,
            hrLastSampleAgeSec: hrLastSampleAgeSec,
            baselineHRConfidence: baselineHRConfidence,
            baselineMotionConfidence: .high,
            watchWornConfidence: watchWornConfidence,
            sensorConfidence: motionLastSampleAgeSec <= 2 ? .high : .low
        )
    }
}

public extension SensorSummary {
    static func fixture(
        motionContinuitySec: Double,
        postureDelta: Double,
        gyroPeak: Double,
        stepDelta: Int,
        interactionCount: Int,
        hrDeltaFromBaseline: Double?
    ) -> SensorSummary {
        SensorSummary(
            runId: UUID(),
            windowStart: Date(timeIntervalSince1970: 0),
            windowEnd: Date(timeIntervalSince1970: 15),
            baselineHR: 58,
            baselineMotion: 0.05,
            accelMagnitudeMean: motionContinuitySec > 0 ? 1.2 : 0,
            accelMagnitudeStd: motionContinuitySec > 0 ? 0.35 : 0,
            gyroMagnitudeMean: gyroPeak / 2,
            gyroPeak: gyroPeak,
            postureDelta: postureDelta,
            motionContinuitySec: motionContinuitySec,
            stillnessDurationSec: 0,
            stepDelta: stepDelta,
            screenWakeCount: interactionCount > 0 ? 1 : 0,
            interactionCount: interactionCount,
            missingDataDurationSec: 0,
            batteryDelta: 0,
            hrDeltaFromBaseline: hrDeltaFromBaseline
        )
    }
}
#endif

