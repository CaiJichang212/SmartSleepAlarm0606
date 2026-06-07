import Foundation
import SmartSleepCore
import SwiftUI

@MainActor
final class AlarmDashboardModel: ObservableObject {
    @Published private(set) var alarms: [AlarmCardState] = []
    @Published var exportedLogText = ""
    @Published var userVisibleWarning: String?

    private let repository: AlarmRepository

    init(repository: AlarmRepository) {
        self.repository = repository
        reload()
    }

    convenience init() {
        do {
            try self.init(repository: AlarmFileRepositoryAdapter.appStorage())
        } catch {
            self.init(repository: MemoryAlarmRepository())
            self.userVisibleWarning = "Alarm storage unavailable; using temporary alarms."
        }
    }

    func reload() {
        do {
            let persisted = try repository.list()
            alarms = persisted.map { AlarmCardState.from(alarm: $0) }
            if alarms.isEmpty {
                alarms = AlarmCardState.seed
                for item in alarms {
                    try repository.save(item.alarm)
                }
            }
            userVisibleWarning = nil
        } catch {
            userVisibleWarning = "Failed to load alarms."
        }
    }

    func create(_ alarm: AlarmCardState) {
        do {
            try repository.save(alarm.alarm)
            reload()
        } catch {
            userVisibleWarning = "Failed to save alarm."
            exportedLogText = #"{"error":"failed_to_save_alarm"}"#
        }
    }

    func delete(at offsets: IndexSet) {
        let ids = offsets.map { alarms[$0].id }
        do {
            for id in ids {
                try repository.delete(id: id)
            }
            reload()
        } catch {
            userVisibleWarning = "Failed to delete alarm."
            exportedLogText = #"{"error":"failed_to_delete_alarm"}"#
        }
    }

    func exportPreview() {
        exportedLogText = LogPreviewBuilder.makePreview(for: alarms)
    }
}
