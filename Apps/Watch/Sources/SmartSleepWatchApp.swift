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
    @State private var isArmed = false
    @State private var sessionScheduled = false
    @State private var currentState = SmartAlarmState.needsWatchArming

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("07:30")
                            .font(.system(size: 34, weight: .semibold, design: .rounded))
                            .monospacedDigit()
                        Text("下一次闹铃")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    StatusLine(title: "佩戴状态", value: "可用", systemImage: "applewatch")
                    StatusLine(title: "Motion", value: "已启用", systemImage: "sensor.tag.radiowaves.forward")
                    StatusLine(title: "iPhone 兜底", value: "AlarmKit", systemImage: "iphone")
                    StatusLine(title: "Runtime", value: sessionScheduled ? "已预约" : "待预约", systemImage: "clock.badge.checkmark")

                    Button {
                        isArmed = true
                        sessionScheduled = true
                        currentState = .sessionScheduled
                    } label: {
                        Label(isArmed ? "已武装" : "今晚启用", systemImage: isArmed ? "checkmark.seal.fill" : "bolt.badge.clock")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(isArmed)

                    Divider()

                    RingingControls(currentState: $currentState)
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
    @Binding var currentState: SmartAlarmState

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Dogfood 控制")
                .font(.headline)

            HStack {
                Button {
                    currentState = .ringing
                } label: {
                    Image(systemName: "bell.and.waves.left.and.right")
                }
                .accessibilityLabel("模拟响铃")

                Button {
                    currentState = .snoozed
                } label: {
                    Image(systemName: "zzz")
                }
                .disabled(currentState != .ringing && currentState != .reRinging)
                .accessibilityLabel("贪睡")

                Button {
                    currentState = .completed
                } label: {
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

