import SmartSleepCore
import SwiftUI

@main
struct SmartSleepWatchApp: App {
    var body: some Scene {
        WindowGroup {
            WatchArmingView()
        }
    }
}

private struct WatchArmingView: View {
    @StateObject private var model = WatchAppModel()

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(model.lastConfig?.nextFireAt.formatted(date: .omitted, time: .shortened) ?? "--:--")
                            .font(.system(size: 34, weight: .semibold, design: .rounded))
                            .monospacedDigit()
                        Text("下一次闹铃")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    StatusLine(title: "配置", value: model.lastConfig == nil ? "未收到" : "已收到", systemImage: "antenna.radiowaves.left.and.right")
                    StatusLine(title: "iPhone 兜底", value: "Local Notification", systemImage: "iphone")
                    StatusLine(title: "Runtime", value: model.sessionScheduled ? "已预约" : "待预约", systemImage: "clock.badge.checkmark")

                    if let failureReason = model.failureReason {
                        Text(failureReason)
                            .font(.caption.monospaced())
                            .foregroundStyle(.orange)
                    }

                    Button {
                        model.armCurrentAlarm()
                    } label: {
                        Label(model.sessionScheduled ? "已武装" : "今晚启用", systemImage: model.sessionScheduled ? "checkmark.seal.fill" : "bolt.badge.clock")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(model.sessionScheduled)

                    Divider()

                    RingingControls(
                        currentState: model.currentState,
                        onSimulateRinging: model.simulateRinging,
                        onSnooze: model.snooze,
                        onStop: model.stop
                    )
                }
                .padding(.vertical)
            }
            .navigationTitle("SmartSleep")
        }
    }
}

private struct StatusLine: View {
    let title: String
    let value: String
    let systemImage: String

    var body: some View {
        HStack {
            Label(title, systemImage: systemImage)
            Spacer()
            Text(value)
                .foregroundStyle(.secondary)
        }
        .font(.caption)
    }
}

private struct RingingControls: View {
    let currentState: SmartAlarmState
    let onSimulateRinging: () -> Void
    let onSnooze: () -> Void
    let onStop: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Dogfood 控制")
                .font(.headline)

            HStack {
                Button(action: onSimulateRinging) {
                    Image(systemName: "bell.and.waves.left.and.right")
                }
                .accessibilityLabel("模拟响铃")

                Button(action: onSnooze) {
                    Image(systemName: "zzz")
                }
                .disabled(currentState != .ringing && currentState != .reRinging)
                .accessibilityLabel("贪睡")

                Button(action: onStop) {
                    Image(systemName: "stop.fill")
                }
                .disabled(currentState != .ringing && currentState != .reRinging && currentState != .snoozed)
                .accessibilityLabel("停止")
            }

            Text("状态：\(currentState.rawValue)")
                .font(.caption.monospaced())
                .foregroundStyle(.secondary)
        }
    }
}
