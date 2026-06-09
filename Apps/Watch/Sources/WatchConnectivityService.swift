import Foundation
import SmartSleepCore
import WatchConnectivity

protocol WatchConnectivityClient: AnyObject {
    var latestAlarmConfig: AlarmConfigPayload? { get }
    var onConfigChanged: ((AlarmConfigPayload?) -> Void)? { get set }
    func sendArmingResult(_ payload: ArmingResultPayload)
    func sendSessionResult(_ payload: SessionResultPayload)
    func sendRunLogSummary(_ payload: RunLogSummaryPayload)
}

final class WatchConnectivityService: NSObject, ObservableObject, WatchConnectivityClient {
    @Published private(set) var latestAlarmConfig: AlarmConfigPayload? {
        didSet { onConfigChanged?(latestAlarmConfig) }
    }
    @Published private(set) var outboundOutbox: [SmartSleepConnectivityMessage] = []

    var onConfigChanged: ((AlarmConfigPayload?) -> Void)?

    private let session: WCSession?
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    override init() {
        self.session = WCSession.isSupported() ? WCSession.default : nil
        super.init()
        self.session?.delegate = self
        self.session?.activate()
    }

    func sendArmingResult(_ payload: ArmingResultPayload) {
        send(.armingResult(payload))
    }

    func sendSessionResult(_ payload: SessionResultPayload) {
        send(.sessionResult(payload))
    }

    func sendRunLogSummary(_ payload: RunLogSummaryPayload) {
        send(.runLogSummary(payload))
    }

    private func send(_ message: SmartSleepConnectivityMessage) {
        guard let data = try? encoder.encode(message), let session else {
            outboundOutbox.append(message)
            return
        }

        if session.isReachable {
            session.sendMessageData(data, replyHandler: nil) { [weak self] _ in
                Task { @MainActor in
                    self?.outboundOutbox.append(message)
                }
            }
        } else {
            do {
                try session.updateApplicationContext(["message": data])
            } catch {
                outboundOutbox.append(message)
            }
        }
    }

    @MainActor
    private func receive(_ data: Data) {
        guard let message = try? decoder.decode(SmartSleepConnectivityMessage.self, from: data) else { return }
        switch message {
        case let .alarmConfig(payload):
            latestAlarmConfig = payload
        case let .alarmCancelled(alarmId):
            if latestAlarmConfig?.alarm.id == alarmId {
                latestAlarmConfig = nil
            }
        case .armingResult, .sessionResult, .runLogSummary:
            break
        }
    }
}

extension WatchConnectivityService: WCSessionDelegate {
    nonisolated func session(
        _ session: WCSession,
        activationDidCompleteWith activationState: WCSessionActivationState,
        error: Error?
    ) {}

    nonisolated func session(_ session: WCSession, didReceiveMessageData messageData: Data) {
        Task { @MainActor in
            self.receive(messageData)
        }
    }

    nonisolated func session(_ session: WCSession, didReceiveApplicationContext applicationContext: [String : Any]) {
        guard let data = applicationContext["message"] as? Data else { return }
        Task { @MainActor in
            self.receive(data)
        }
    }
}
