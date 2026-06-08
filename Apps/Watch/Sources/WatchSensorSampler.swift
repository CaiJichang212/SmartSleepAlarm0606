import CoreMotion
import Foundation
import SmartSleepCore

protocol WatchSensorSampling: AnyObject {
    var onFreshness: ((SensorFreshness) -> Void)? { get set }
    var onSummary: ((SensorSummary) -> Void)? { get set }
    func start(runId: UUID)
    func stop()
}

final class FakeWatchSensorSampler: WatchSensorSampling {
    var onFreshness: ((SensorFreshness) -> Void)?
    var onSummary: ((SensorSummary) -> Void)?
    private(set) var activeRunId: UUID?

    func start(runId: UUID) {
        activeRunId = runId
    }

    func stop() {
        activeRunId = nil
    }

    func emitFreshness(_ freshness: SensorFreshness) {
        onFreshness?(freshness)
    }

    func emitSummary(_ summary: SensorSummary) {
        onSummary?(summary)
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
    private var windowStart: Date?
    private var gyroPeak = 0.0
    private var accelValues: [Double] = []

    func start(runId: UUID) {
        self.runId = runId
        sampleCount = 0
        lastSampleAt = nil
        windowStart = Date()
        gyroPeak = 0
        accelValues = []

        motionManager.deviceMotionUpdateInterval = 0.2
        motionManager.startDeviceMotionUpdates(to: .main) { [weak self] motion, _ in
            guard let self, let motion, let runId = self.runId else { return }
            let now = Date()
            self.sampleCount += 1
            self.lastSampleAt = now
            let accel = motion.userAcceleration
            let accelMagnitude = sqrt(accel.x * accel.x + accel.y * accel.y + accel.z * accel.z)
            self.accelValues.append(accelMagnitude)
            let rotation = motion.rotationRate
            let gyroMagnitude = sqrt(rotation.x * rotation.x + rotation.y * rotation.y + rotation.z * rotation.z)
            self.gyroPeak = max(self.gyroPeak, gyroMagnitude)

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
        runId = nil
    }
}
