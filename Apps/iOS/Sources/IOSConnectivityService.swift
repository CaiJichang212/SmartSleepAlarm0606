import Foundation
import SmartSleepCore
import WatchConnectivity

protocol PhoneConnectivityClient: AnyObject {
    var lastArmingStatus: WatchArmingStatus? { get }
    var onArmingStatusChanged: ((WatchArmingStatus?) -> Void)? { get set }
    var outboundOutbox: [SmartSleepConnectivityMessage] { get }
    func sendAlarmConfig(_ payload: AlarmConfigPayload)
    func cancelAlarm(id: UUID)
}

final class FakePhoneConnectivityClient: PhoneConnectivityClient {
    private(set) var lastArmingStatus: WatchArmingStatus?
    var onArmingStatusChanged: ((WatchArmingStatus?) -> Void)?
    private(set) var outboundOutbox: [SmartSleepConnectivityMessage] = []

    func sendAlarmConfig(_ payload: AlarmConfigPayload) {
        outboundOutbox.append(.alarmConfig(payload))
    }

    func cancelAlarm(id: UUID) {
        outboundOutbox.append(.alarmCancelled(alarmId: id))
    }

    func deliverArmingStatus(_ status: WatchArmingStatus) {
        lastArmingStatus = status
        onArmingStatusChanged?(status)
    }
}

final class IOSConnectivityService: NSObject, ObservableObject, PhoneConnectivityClient {
    @Published private(set) var lastArmingStatus: WatchArmingStatus?
    @Published private(set) var outboundOutbox: [SmartSleepConnectivityMessage] = []
    var onArmingStatusChanged: ((WatchArmingStatus?) -> Void)?

    private let session: WCSession?
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    override init() {
        self.session = WCSession.isSupported() ? WCSession.default : nil
        super.init()
        self.session?.delegate = self
        self.session?.activate()
    }

    func sendAlarmConfig(_ payload: AlarmConfigPayload) {
        send(.alarmConfig(payload))
    }

    func cancelAlarm(id: UUID) {
        send(.alarmCancelled(alarmId: id))
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
        if case let .armingResult(payload) = message {
            lastArmingStatus = payload.status
            onArmingStatusChanged?(payload.status)
        }
    }
}

extension IOSConnectivityService: WCSessionDelegate {
    nonisolated func session(
        _ session: WCSession,
        activationDidCompleteWith activationState: WCSessionActivationState,
        error: Error?
    ) {}

    nonisolated func sessionDidBecomeInactive(_ session: WCSession) {}

    nonisolated func sessionDidDeactivate(_ session: WCSession) {
        session.activate()
    }

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
