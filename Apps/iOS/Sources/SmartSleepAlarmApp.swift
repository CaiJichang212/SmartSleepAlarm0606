import SmartSleepCore
import SwiftUI

@main
struct SmartSleepAlarmApp: App {
    var body: some Scene {
        WindowGroup {
            AlarmDashboardView()
        }
    }
}

private struct AlarmDashboardView: View {
    @State private var alarms: [AlarmCardState] = AlarmCardState.seed
    @State private var isCreatingAlarm = false
    @State private var exportedLogText = ""

    var body: some View {
        NavigationStack {
            List {
                Section {
                    ForEach(alarms) { alarm in
                        AlarmCard(alarm: alarm)
                    }
                    .onDelete(perform: deleteAlarm)
                }

                Section("内部测试日志") {
                    Button {
                        exportedLogText = LogPreviewBuilder.makePreview(for: alarms)
                    } label: {
                        Label("导出本地 JSON 预览", systemImage: "square.and.arrow.up")
                    }

                    if !exportedLogText.isEmpty {
                        Text(exportedLogText)
                            .font(.caption.monospaced())
                            .textSelection(.enabled)
                            .lineLimit(8)
                    }
                }
            }
            .navigationTitle("SmartSleep")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        isCreatingAlarm = true
                    } label: {
                        Label("新增闹铃", systemImage: "plus")
                    }
                }
            }
            .sheet(isPresented: $isCreatingAlarm) {
                CreateAlarmView { alarm in
                    alarms.append(alarm)
                    alarms.sort { $0.nextFireAt < $1.nextFireAt }
                }
            }
        }
    }

    private func deleteAlarm(at offsets: IndexSet) {
        alarms.remove(atOffsets: offsets)
    }
}

private struct AlarmCard: View {
    let alarm: AlarmCardState

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                Text(alarm.timeLabel)
                    .font(.system(size: 42, weight: .semibold, design: .rounded))
                    .monospacedDigit()
                Spacer()
                StatusBadge(status: alarm.smartStatus)
            }

            Text(alarm.label)
                .font(.headline)

            HStack(spacing: 8) {
                Label(alarm.watchStatusLabel, systemImage: alarm.watchIcon)
                Label(alarm.backupLabel, systemImage: "iphone")
            }
            .font(.caption)
            .foregroundStyle(.secondary)
        }
        .padding(.vertical, 8)
    }
}

private struct StatusBadge: View {
    let status: SmartModeStatus

    var body: some View {
        Label(title, systemImage: icon)
            .font(.caption.weight(.semibold))
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .foregroundStyle(foreground)
            .background(background, in: Capsule())
            .accessibilityLabel(title)
    }

    private var title: String {
        switch status {
        case .smartOff: "Smart Off"
        case .needsWatchArming: "Needs Watch"
        case .ready: "Ready"
        case .fallbackOnly: "Fallback"
        case .failed: "Failed"
        }
    }

    private var icon: String {
        switch status {
        case .smartOff: "moon.zzz"
        case .needsWatchArming: "applewatch"
        case .ready: "checkmark.seal"
        case .fallbackOnly: "exclamationmark.triangle"
        case .failed: "xmark.octagon"
        }
    }

    private var foreground: Color {
        switch status {
        case .ready: .green
        case .fallbackOnly, .needsWatchArming: .orange
        case .failed: .red
        case .smartOff: .secondary
        }
    }

    private var background: Color {
        foreground.opacity(0.14)
    }
}

private struct CreateAlarmView: View {
    @Environment(\.dismiss) private var dismiss

    @State private var nextFireAt = Date.now.addingTimeInterval(3600)
    @State private var label = "Morning"
    @State private var smartEnabled = true
    @State private var snoozeMinutes = 9

    let onCreate: (AlarmCardState) -> Void

    var body: some View {
        NavigationStack {
            Form {
                DatePicker("时间", selection: $nextFireAt, displayedComponents: .hourAndMinute)
                TextField("标签", text: $label)
                Toggle("Smart Mode", isOn: $smartEnabled)
                Stepper("贪睡 \(snoozeMinutes) 分钟", value: $snoozeMinutes, in: 5...20)

                Section("就绪规则") {
                    LabeledContent("Watch 武装", value: smartEnabled ? "创建后需要确认" : "不需要")
                    LabeledContent("兜底通道", value: "iPhone AlarmKit 优先")
                }
            }
            .navigationTitle("新增闹铃")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") {
                        dismiss()
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("创建") {
                        onCreate(AlarmCardState.make(
                            nextFireAt: nextFireAt,
                            label: label,
                            smartEnabled: smartEnabled,
                            snoozeMinutes: snoozeMinutes
                        ))
                        dismiss()
                    }
                }
            }
        }
    }
}

private struct AlarmCardState: Identifiable, Equatable {
    var id: UUID
    var alarm: Alarm
    var armingStatus: WatchArmingStatus?
    var nextFireAt: Date

    var smartStatus: SmartModeStatus {
        SmartModeResolver.status(for: alarm, arming: armingStatus)
    }

    var timeLabel: String {
        nextFireAt.formatted(date: .omitted, time: .shortened)
    }

    var label: String {
        alarm.label
    }

    var watchStatusLabel: String {
        switch smartStatus {
        case .ready: "Watch armed"
        case .needsWatchArming: "Watch needs arming"
        case .fallbackOnly: "Runtime failed"
        case .failed: "Unavailable"
        case .smartOff: "Smart disabled"
        }
    }

    var watchIcon: String {
        smartStatus == .ready ? "applewatch.radiowaves.left.and.right" : "applewatch"
    }

    var backupLabel: String {
        "Backup: \(alarm.backupChannelPreferred.rawValue)"
    }

    static func make(nextFireAt: Date, label: String, smartEnabled: Bool, snoozeMinutes: Int) -> AlarmCardState {
        let id = UUID()
        let components = Calendar.current.dateComponents([.hour, .minute], from: nextFireAt)
        let alarm = Alarm(
            id: id,
            timeOfDay: components,
            repeatDays: [],
            label: label.isEmpty ? "Alarm" : label,
            soundId: "default",
            isEnabled: true,
            smartEnabled: smartEnabled,
            requiresWatchArming: smartEnabled,
            snoozeIntervalMin: snoozeMinutes,
            maxSnoozeCount: 3,
            maxReAlarmCount: 2,
            backupChannelPreferred: .iOSAlarmKit
        )
        return AlarmCardState(id: id, alarm: alarm, armingStatus: nil, nextFireAt: nextFireAt)
    }

    static let seed: [AlarmCardState] = {
        let calendar = Calendar.current
        let tomorrow = calendar.date(byAdding: .day, value: 1, to: .now) ?? .now
        var ready = make(nextFireAt: calendar.date(bySettingHour: 7, minute: 30, second: 0, of: tomorrow) ?? tomorrow, label: "Workday", smartEnabled: true, snoozeMinutes: 9)
        ready.armingStatus = WatchArmingStatus(
            alarmId: ready.id,
            isArmed: true,
            sessionScheduled: true,
            fallbackChannel: .iOSAlarmKit,
            failureReason: nil
        )

        let needsWatch = make(nextFireAt: calendar.date(bySettingHour: 8, minute: 15, second: 0, of: tomorrow) ?? tomorrow, label: "Weekend", smartEnabled: true, snoozeMinutes: 10)
        var fallback = make(nextFireAt: calendar.date(bySettingHour: 6, minute: 45, second: 0, of: tomorrow) ?? tomorrow, label: "Flight", smartEnabled: true, snoozeMinutes: 5)
        fallback.armingStatus = WatchArmingStatus(
            alarmId: fallback.id,
            isArmed: true,
            sessionScheduled: false,
            fallbackChannel: .iOSLocalNotification,
            failureReason: "runtime session unavailable"
        )
        return [fallback, ready, needsWatch].sorted { $0.nextFireAt < $1.nextFireAt }
    }()
}

private enum LogPreviewBuilder {
    static func makePreview(for alarms: [AlarmCardState]) -> String {
        let payload = alarms.map { alarm in
            [
                "alarmId": alarm.id.uuidString,
                "label": alarm.label,
                "smartStatus": alarm.smartStatus.rawValue,
                "backupChannel": alarm.alarm.backupChannelPreferred.rawValue
            ]
        }
        guard let data = try? JSONSerialization.data(withJSONObject: payload, options: [.prettyPrinted, .sortedKeys]),
              let text = String(data: data, encoding: .utf8) else {
            return "[]"
        }
        return text
    }
}

