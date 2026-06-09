import CoreMotion
import Foundation
import SmartSleepCore

protocol WatchSensorSampling: AnyObject {
    var onFreshness: ((SensorFreshness) -> Void)? { get set }
    var onSummary: ((SensorSummary) -> Void)? { get set }
    func start(runId: UUID)
    func stop()
}

struct MotionWindowSample: Equatable {
    var timestamp: Date
    var accelMagnitude: Double
    var gyroMagnitude: Double
    var attitudeRoll: Double
    var attitudePitch: Double
    var attitudeYaw: Double
}

struct MotionWindowAggregator {
    let runId: UUID
    let windowStart: Date
    private(set) var samples: [MotionWindowSample] = []

    mutating func append(_ sample: MotionWindowSample) {
        samples.append(sample)
    }

    func summary(windowEnd: Date) -> SensorSummary {
        let accel = samples.map(\.accelMagnitude)
        let gyro = samples.map(\.gyroMagnitude)
        let mean = accel.isEmpty ? 0 : accel.reduce(0, +) / Double(accel.count)
        let variance = accel.isEmpty ? 0 : accel.map { pow($0 - mean, 2) }.reduce(0, +) / Double(accel.count)
        let gyroMean = gyro.isEmpty ? 0 : gyro.reduce(0, +) / Double(gyro.count)
        let peak = gyro.max() ?? 0
        let postureDelta = Self.postureDeltaDegrees(samples)
        let motionContinuitySec = samples.contains { $0.accelMagnitude > 0.2 || $0.gyroMagnitude > 0.5 }
            ? windowEnd.timeIntervalSince(windowStart)
            : 0
        let stillnessDurationSec = !samples.isEmpty && samples.allSatisfy { $0.accelMagnitude < 0.05 && $0.gyroMagnitude < 0.1 }
            ? windowEnd.timeIntervalSince(windowStart)
            : 0

        return SensorSummary(
            runId: runId,
            windowStart: windowStart,
            windowEnd: windowEnd,
            baselineHR: nil,
            baselineMotion: mean,
            accelMagnitudeMean: mean,
            accelMagnitudeStd: sqrt(variance),
            gyroMagnitudeMean: gyroMean,
            gyroPeak: peak,
            postureDelta: postureDelta,
            motionContinuitySec: motionContinuitySec,
            stillnessDurationSec: stillnessDurationSec,
            stepDelta: 0,
            screenWakeCount: 0,
            interactionCount: 0,
            missingDataDurationSec: 0,
            batteryDelta: 0,
            hrDeltaFromBaseline: nil
        )
    }

    private static func postureDeltaDegrees(_ samples: [MotionWindowSample]) -> Double {
        guard let first = samples.first, let last = samples.last else { return 0 }
        let delta = abs(last.attitudeRoll - first.attitudeRoll)
            + abs(last.attitudePitch - first.attitudePitch)
            + abs(last.attitudeYaw - first.attitudeYaw)
        return delta * 180 / .pi
    }
}

final class CoreMotionWatchSensorSampler: WatchSensorSampling {
    var onFreshness: ((SensorFreshness) -> Void)?
    var onSummary: ((SensorSummary) -> Void)?

    private let motionManager = CMMotionManager()
    private var freshnessTask: Task<Void, Never>?
    private var runId: UUID?
    private var sampleCount = 0
    private var lastSampleAt: Date?
    private var aggregator: MotionWindowAggregator?
    private var lastSummaryAt: Date?
    private let summaryWindowSec: TimeInterval = 3

    func start(runId: UUID) {
        self.runId = runId
        sampleCount = 0
        lastSampleAt = nil
        let start = Date()
        lastSummaryAt = start
        aggregator = MotionWindowAggregator(runId: runId, windowStart: start)

        motionManager.deviceMotionUpdateInterval = 0.2
        motionManager.startDeviceMotionUpdates(to: .main) { [weak self] motion, _ in
            guard let self, let motion, let runId = self.runId else { return }
            let now = Date()
            self.sampleCount += 1
            self.lastSampleAt = now
            let accel = motion.userAcceleration
            let accelMagnitude = sqrt(accel.x * accel.x + accel.y * accel.y + accel.z * accel.z)
            let rotation = motion.rotationRate
            let gyroMagnitude = sqrt(rotation.x * rotation.x + rotation.y * rotation.y + rotation.z * rotation.z)
            self.aggregator?.append(MotionWindowSample(
                timestamp: now,
                accelMagnitude: accelMagnitude,
                gyroMagnitude: gyroMagnitude,
                attitudeRoll: motion.attitude.roll,
                attitudePitch: motion.attitude.pitch,
                attitudeYaw: motion.attitude.yaw
            ))

            if let lastSummaryAt = self.lastSummaryAt,
               now.timeIntervalSince(lastSummaryAt) >= self.summaryWindowSec,
               let summary = self.aggregator?.summary(windowEnd: now),
               !summary.isHighConfidenceEmptyWindow {
                self.onSummary?(summary)
                self.lastSummaryAt = now
                self.aggregator = MotionWindowAggregator(runId: runId, windowStart: now)
            }

            let freshness = SensorFreshness(
                runId: runId,
                timestamp: now,
                motionSampleCount: self.sampleCount,
                motionLastSampleAgeSec: 0,
                hrSampleCount: 0,
                hrLastSampleAgeSec: nil,
                baselineHRConfidence: .none,
                baselineMotionConfidence: self.sampleCount >= 10 ? .medium : .low,
                watchWornConfidence: .medium,
                sensorConfidence: self.sampleCount >= 10 ? .medium : .low
            )
            self.onFreshness?(freshness)
        }

        freshnessTask?.cancel()
        freshnessTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 1_000_000_000)
                guard let strongSelf = self else { return }
                await MainActor.run { [strongSelf] in
                    guard let runId = strongSelf.runId else { return }
                    let now = Date()
                    let age = strongSelf.lastSampleAt.map { now.timeIntervalSince($0) } ?? .infinity
                    let confidence: ConfidenceLevel = age <= 2 ? .medium : .low
                    strongSelf.onFreshness?(SensorFreshness(
                        runId: runId,
                        timestamp: now,
                        motionSampleCount: strongSelf.sampleCount,
                        motionLastSampleAgeSec: age,
                        hrSampleCount: 0,
                        hrLastSampleAgeSec: nil,
                        baselineHRConfidence: .none,
                        baselineMotionConfidence: confidence,
                        watchWornConfidence: .medium,
                        sensorConfidence: confidence
                    ))
                }
            }
        }
    }

    func stop() {
        freshnessTask?.cancel()
        freshnessTask = nil
        motionManager.stopDeviceMotionUpdates()
        aggregator = nil
        lastSummaryAt = nil
        runId = nil
    }
}

private extension SensorSummary {
    var isHighConfidenceEmptyWindow: Bool {
        motionContinuitySec == 0
            && accelMagnitudeMean == 0
            && gyroMagnitudeMean == 0
            && gyroPeak == 0
            && postureDelta == 0
    }
}
