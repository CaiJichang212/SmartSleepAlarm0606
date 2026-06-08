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
    @StateObject private var model = AlarmDashboardModel()
    @State private var editorAlarm: AlarmCardState?

    var body: some View {
        NavigationStack {
            List {
                if let warning = model.userVisibleWarning {
                    Section {
                        Label(warning, systemImage: "exclamationmark.triangle")
                    }
                }

                Section("通知") {
                    LabeledContent("iPhone 兜底", value: notificationStatusText)

                    if model.notificationAuthorizationState != .authorized {
                        Button {
                            Task {
                                await model.requestNotificationAuthorization()
                            }
                        } label: {
                            Label("允许通知", systemImage: "bell.badge")
                        }
                    }
                }

                Section {
                    ForEach(model.alarms) { alarm in
                        AlarmCard(alarm: alarm)
                            .onTapGesture {
                                editorAlarm = alarm
                            }
                    }
                    .onDelete(perform: model.delete)
                }

                Section("内部测试预览") {
                    Button {
                        model.exportPreview()
                    } label: {
                        Label("导出闹铃 JSON 预览", systemImage: "square.and.arrow.up")
                    }

                    Button {
                        model.recordFeedback(.wokeUp, notes: "User reported awake during dogfood.")
                    } label: {
                        Label("标注：已醒", systemImage: "checkmark.circle")
                    }

                    Button {
                        model.recordFeedback(.falseSilence, notes: "User reported false silence during dogfood.")
                    } label: {
                        Label("标注：误静音", systemImage: "exclamationmark.circle")
                    }

                    Button {
                        model.recordFeedback(.falseReAlarm, notes: "User reported false re-alarm during dogfood.")
                    } label: {
                        Label("标注：误重响", systemImage: "bell.badge")
                    }

                    Button {
                        model.recordFeedback(.missedAlarm, notes: "User reported missed alarm during dogfood.")
                    } label: {
                        Label("标注：没响", systemImage: "xmark.octagon")
                    }

                    if !model.exportedLogText.isEmpty {
                        Text(model.exportedLogText)
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
                        editorAlarm = AlarmCardState.make(
                            nextFireAt: Date.now.addingTimeInterval(3600),
                            label: "Morning",
                            smartEnabled: true,
                            snoozeMinutes: 9
                        )
                    } label: {
                        Label("新增闹铃", systemImage: "plus")
                    }
                }
            }
            .sheet(item: $editorAlarm) { alarm in
                EditAlarmView(alarm: alarm) { edited in
                    if model.alarms.contains(where: { $0.id == edited.id }) {
                        model.update(edited)
                    } else {
                        model.create(edited)
                    }
                }
            }
        }
    }

    private var notificationStatusText: String {
        switch model.notificationAuthorizationState {
        case .authorized:
            return "已授权"
        case .denied:
            return "已拒绝"
        case .notDetermined:
            return "待确认"
        case .unavailable:
            return "不可用"
        case .unknown:
            return "未知"
        }
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
                if !alarm.alarm.isEnabled {
                    Label("Disabled", systemImage: "power")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
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

private struct EditAlarmView: View {
    @Environment(\.dismiss) private var dismiss

    @State private var nextFireAt: Date
    @State private var label: String
    @State private var isEnabled: Bool
    @State private var smartEnabled: Bool
    @State private var snoozeMinutes: Int

    let alarm: AlarmCardState
    let onSave: (AlarmCardState) -> Void

    init(alarm: AlarmCardState, onSave: @escaping (AlarmCardState) -> Void) {
        self.alarm = alarm
        self.onSave = onSave
        _nextFireAt = State(initialValue: alarm.nextFireAt)
        _label = State(initialValue: alarm.label)
        _isEnabled = State(initialValue: alarm.alarm.isEnabled)
        _smartEnabled = State(initialValue: alarm.alarm.smartEnabled)
        _snoozeMinutes = State(initialValue: alarm.alarm.snoozeIntervalMin)
    }

    var body: some View {
        NavigationStack {
            Form {
                DatePicker("时间", selection: $nextFireAt, displayedComponents: .hourAndMinute)
                TextField("标签", text: $label)
                Toggle("启用", isOn: $isEnabled)
                Toggle("Smart Mode", isOn: $smartEnabled)
                Stepper("贪睡 \(snoozeMinutes) 分钟", value: $snoozeMinutes, in: 5...20)

                Section("就绪规则") {
                    LabeledContent("Watch 启用确认", value: smartEnabled ? "创建后需要确认" : "不需要")
                    LabeledContent("兜底通道", value: "iPhone 本地通知")
                }
            }
            .navigationTitle("闹铃")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") {
                        dismiss()
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("保存") {
                        var edited = AlarmCardState.make(
                            id: alarm.id,
                            nextFireAt: nextFireAt,
                            label: label,
                            smartEnabled: smartEnabled,
                            snoozeMinutes: snoozeMinutes
                        )
                        edited.alarm.isEnabled = isEnabled
                        edited.alarm.updatedAt = Date()
                        onSave(edited)
                        dismiss()
                    }
                }
            }
        }
    }
}

struct AlarmCardState: Identifiable, Equatable {
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
        case .ready: "Watch 已就绪"
        case .needsWatchArming: "等待 Watch 确认"
        case .fallbackOnly: "Runtime failed"
        case .failed: "Unavailable"
        case .smartOff: "Smart disabled"
        }
    }

    var watchIcon: String {
        smartStatus == .ready ? "applewatch.radiowaves.left.and.right" : "applewatch"
    }

    var requiredBackupChannel: AlarmChannel {
        AlarmSchedulerPolicy().decision(for: alarm, arming: armingStatus).requiredBackupChannel
    }

    var backupLabel: String {
        "Backup: \(requiredBackupChannel.rawValue)"
    }

    static func from(
        alarm: Alarm,
        armingStatus: WatchArmingStatus? = nil,
        calendar: Calendar = .current,
        now: Date = Date()
    ) -> AlarmCardState {
        let hour = alarm.timeOfDay.hour ?? 7
        let minute = alarm.timeOfDay.minute ?? 30
        let base = calendar.startOfDay(for: now)
        let candidate = calendar.date(bySettingHour: hour, minute: minute, second: 0, of: base) ?? now
        let nextFireAt = candidate > now ? candidate : calendar.date(byAdding: .day, value: 1, to: candidate) ?? candidate
        return AlarmCardState(id: alarm.id, alarm: alarm, armingStatus: armingStatus, nextFireAt: nextFireAt)
    }

    static func make(
        id: UUID,
        nextFireAt: Date,
        label: String,
        smartEnabled: Bool,
        snoozeMinutes: Int
    ) -> AlarmCardState {
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
            backupChannelPreferred: .iOSLocalNotification
        )
        return AlarmCardState(id: id, alarm: alarm, armingStatus: nil, nextFireAt: nextFireAt)
    }

    static func make(nextFireAt: Date, label: String, smartEnabled: Bool, snoozeMinutes: Int) -> AlarmCardState {
        make(
            id: UUID(),
            nextFireAt: nextFireAt,
            label: label,
            smartEnabled: smartEnabled,
            snoozeMinutes: snoozeMinutes
        )
    }

    static let seed: [AlarmCardState] = {
        let calendar = Calendar.current
        let tomorrow = calendar.date(byAdding: .day, value: 1, to: .now) ?? .now
        var ready = make(nextFireAt: calendar.date(bySettingHour: 7, minute: 30, second: 0, of: tomorrow) ?? tomorrow, label: "Workday", smartEnabled: true, snoozeMinutes: 9)
        ready.armingStatus = WatchArmingStatus(
            alarmId: ready.id,
            isArmed: true,
            sessionScheduled: true,
            fallbackChannel: .iOSLocalNotification,
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

enum LogPreviewBuilder {
    static func makePreview(for alarms: [AlarmCardState]) -> String {
        let payload = alarms.map { alarm in
            [
                "alarmId": alarm.id.uuidString,
                "label": alarm.label,
                "smartStatus": alarm.smartStatus.rawValue,
                "requiredBackupChannel": alarm.requiredBackupChannel.rawValue
            ]
        }
        guard let data = try? JSONSerialization.data(withJSONObject: payload, options: [.prettyPrinted, .sortedKeys]),
              let text = String(data: data, encoding: .utf8) else {
            return "[]"
        }
        return text
    }
}
