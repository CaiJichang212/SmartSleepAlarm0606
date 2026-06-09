import Foundation
import HealthKit
import SmartSleepCore

protocol WatchHeartRateSampling: AnyObject {
    var latestHeartRateSample: HeartRateSample? { get }
    func authorizationState() async -> AuthorizationState
    func start()
    func stop()
}

struct HeartRateSample: Equatable, Sendable {
    var bpm: Double
    var sampledAt: Date
    var baselineBPM: Double?
    var baselineConfidence: ConfidenceLevel
}

enum HeartRateFreshnessMapper {
    static func freshness(
        runId: UUID,
        now: Date,
        sample: HeartRateSample?,
        motionSampleCount: Int,
        motionLastSampleAgeSec: Double,
        watchWornConfidence: ConfidenceLevel
    ) -> SensorFreshness {
        SensorFreshness(
            runId: runId,
            timestamp: now,
            motionSampleCount: motionSampleCount,
            motionLastSampleAgeSec: motionLastSampleAgeSec,
            hrSampleCount: sample == nil ? 0 : 1,
            hrLastSampleAgeSec: sample.map { now.timeIntervalSince($0.sampledAt) },
            baselineHRConfidence: sample?.baselineConfidence ?? .none,
            baselineMotionConfidence: motionSampleCount >= 10 ? .medium : .low,
            watchWornConfidence: watchWornConfidence,
            sensorConfidence: motionLastSampleAgeSec <= 2 ? .medium : .low
        )
    }
}

final class WatchHealthKitHeartRateSampler: WatchHeartRateSampling {
    private let healthStore = HKHealthStore()
    private var query: HKSampleQuery?
    private(set) var latestHeartRateSample: HeartRateSample?

    func authorizationState() async -> AuthorizationState {
        guard HKHealthStore.isHealthDataAvailable(),
              let type = HKObjectType.quantityType(forIdentifier: .heartRate) else {
            return .unavailable
        }

        switch healthStore.authorizationStatus(for: type) {
        case .notDetermined:
            return .notDetermined
        case .sharingAuthorized:
            return .authorized
        case .sharingDenied:
            return .denied
        @unknown default:
            return .unknown
        }
    }

    func start() {
        guard HKHealthStore.isHealthDataAvailable(),
              let type = HKObjectType.quantityType(forIdentifier: .heartRate) else {
            latestHeartRateSample = nil
            return
        }

        let sort = NSSortDescriptor(key: HKSampleSortIdentifierEndDate, ascending: false)
        let query = HKSampleQuery(sampleType: type, predicate: nil, limit: 1, sortDescriptors: [sort]) { [weak self] _, samples, _ in
            guard let quantitySample = samples?.first as? HKQuantitySample else { return }
            let bpm = quantitySample.quantity.doubleValue(for: HKUnit.count().unitDivided(by: .minute()))
            self?.latestHeartRateSample = HeartRateSample(
                bpm: bpm,
                sampledAt: quantitySample.endDate,
                baselineBPM: nil,
                baselineConfidence: .low
            )
        }
        self.query = query
        healthStore.execute(query)
    }

    func stop() {
        if let query {
            healthStore.stop(query)
        }
        query = nil
    }
}
