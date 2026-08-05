import AppKit
import BryanToolsShared
import SwiftUI

struct AlarmConfigurationView: View {
    private enum InputMode: String, CaseIterable, Identifiable {
        case duration = "In"
        case exactTime = "At"

        var id: String { rawValue }
    }

    @ObservedObject var environment: AlarmModule
    @State private var inputMode = InputMode.duration
    @State private var durationHours = "0"
    @State private var durationMinutes = "15"
    @State private var exactTime = Date().addingTimeInterval(15 * 60)

    var body: some View {
        Group {
            if environment.isActive {
                activeAlarm
            } else {
                alarmSetup
            }
        }
        .padding(22)
        .frame(width: 360, height: 250, alignment: .topLeading)
        .background(Color(nsColor: .windowBackgroundColor))
    }

    private var alarmSetup: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(spacing: 10) {
                Image(systemName: "alarm")
                    .font(.system(size: 22, weight: .semibold))
                    .foregroundStyle(Color.accentColor)

                Text("Set Alarm")
                    .font(.system(size: 22, weight: .semibold))
            }

            Picker("Alarm input", selection: $inputMode) {
                ForEach(InputMode.allCases) { mode in
                    Text(mode.rawValue).tag(mode)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()

            Group {
                switch inputMode {
                case .duration:
                    durationFields
                case .exactTime:
                    exactTimeField
                }
            }
            .frame(maxWidth: .infinity, minHeight: 38, alignment: .leading)

            if let message = validationError?.localizedDescription {
                Text(message)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                Text("Alarm will fire today at \(targetTitle).")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer(minLength: 0)

            HStack {
                Spacer()
                Button("Set Alarm") {
                    setAlarm()
                }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.defaultAction)
                .disabled(proposedTarget == nil)
            }
        }
    }

    private var activeAlarm: some View {
        VStack(spacing: 16) {
            Image(systemName: "alarm.fill")
                .font(.system(size: 28, weight: .semibold))
                .foregroundStyle(Color.accentColor)

            Text(environment.isFiring ? "Alarm is due" : "Alarm set for \(scheduledTimeTitle)")
                .font(.system(size: 18, weight: .semibold))

            Text(environment.remainingText)
                .font(.system(size: 30, weight: .semibold, design: .monospaced))
                .contentTransition(.numericText())

            Spacer(minLength: 0)

            Button(role: .destructive) {
                if environment.isFiring {
                    environment.dismissAlarm()
                } else {
                    environment.cancelAlarm()
                }
            } label: {
                Label(environment.isFiring ? "Dismiss Alarm" : "Cancel Alarm", systemImage: "xmark")
            }
            .buttonStyle(.borderedProminent)
            .tint(.red)
        }
        .frame(maxWidth: .infinity)
    }

    private var durationFields: some View {
        HStack(spacing: 8) {
            numericField("0", text: $durationHours, maximumLength: 2)
            Text("hours")
                .foregroundStyle(.secondary)

            numericField("15", text: $durationMinutes, maximumLength: 2)
            Text("minutes")
                .foregroundStyle(.secondary)
        }
    }

    private var exactTimeField: some View {
        HStack {
            Text("Today at")
                .foregroundStyle(.secondary)
            DatePicker("Alarm time", selection: $exactTime, displayedComponents: .hourAndMinute)
                .labelsHidden()
        }
    }

    private func numericField(
        _ placeholder: String,
        text: Binding<String>,
        maximumLength: Int
    ) -> some View {
        TextField(placeholder, text: text)
            .textFieldStyle(.roundedBorder)
            .multilineTextAlignment(.trailing)
            .font(.system(.body, design: .monospaced))
            .frame(width: 48)
            .onChange(of: text.wrappedValue) { _, newValue in
                let filtered = String(newValue.filter(\.isNumber).prefix(maximumLength))
                if filtered != newValue {
                    text.wrappedValue = filtered
                }
            }
    }

    private var proposedResult: Result<Date, AlarmValidationError> {
        let currentDate = Date()
        switch inputMode {
        case .duration:
            guard let hours = Int(durationHours), let minutes = Int(durationMinutes) else {
                return .failure(.invalidDuration)
            }
            return AlarmSchedule.target(afterHours: hours, minutes: minutes, now: currentDate)
        case .exactTime:
            return AlarmSchedule.targetToday(matching: exactTime, now: currentDate)
        }
    }

    private var proposedTarget: Date? {
        guard case .success(let target) = proposedResult else {
            return nil
        }
        return target
    }

    private var validationError: AlarmValidationError? {
        guard case .failure(let error) = proposedResult else {
            return nil
        }
        return error
    }

    private var targetTitle: String {
        proposedTarget.map { AlarmSchedule.timeTitle(for: $0) } ?? ""
    }

    private var scheduledTimeTitle: String {
        environment.targetDate.map { AlarmSchedule.timeTitle(for: $0) } ?? ""
    }

    private func setAlarm() {
        guard let proposedTarget else {
            return
        }
        environment.setAlarm(targetDate: proposedTarget)
    }
}
