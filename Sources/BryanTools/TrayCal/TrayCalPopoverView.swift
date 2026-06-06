import AppKit
import BryanToolsShared
import SwiftUI

struct TrayCalPopoverView: View {
    @ObservedObject var environment: TrayCalModule
    @State private var showingMonthPicker = false
    @State private var editingYear = false
    @State private var yearText = ""

    private let columns = Array(repeating: GridItem(.fixed(27), spacing: 4), count: 7)
    private let monthColumns = Array(repeating: GridItem(.fixed(48), spacing: 6), count: 3)
    private let weekdays = ["S", "M", "T", "W", "T", "F", "S"]

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            header

            VStack(spacing: 5) {
                weekdayHeader
                dayGrid
            }

            Spacer(minLength: 0)

            HStack {
                iconButton(systemImage: "power", size: 16, action: environment.quit)
                    .padding(3)
                    .background(Color(nsColor: .controlBackgroundColor).opacity(0.7))

                Spacer()

                Capsule()
                    .fill(Color.secondary.opacity(0.15))
                    .frame(width: 34, height: 5)

                Spacer()

                iconButton(systemImage: "gearshape.fill", size: 20, action: environment.openSettings)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.top, 14)
        .padding(.horizontal, 14)
        .padding(.bottom, 14)
        .frame(width: 248, height: 314, alignment: .topLeading)
        .background(Color(nsColor: .windowBackgroundColor))
    }

    private var header: some View {
        HStack(alignment: .center, spacing: 8) {
            HStack(spacing: 3) {
                headerPickerButton(environment.displayedMonthName) {
                    showingMonthPicker = true
                }
                .popover(isPresented: $showingMonthPicker, arrowEdge: .top) {
                    monthPicker
                }

                if editingYear {
                    TrayCalYearField(
                        text: $yearText,
                        onCommit: commitYearEdit(_:),
                        onCancel: cancelYearEdit
                    )
                    .frame(width: 48, height: 24)
                } else {
                    headerPickerButton("\(environment.displayedYear)") {
                        beginYearEdit()
                    }
                }
            }
            .lineLimit(1)
            .minimumScaleFactor(0.72)

            Spacer()

            iconButton(systemImage: "chevron.left", size: 12, hitSize: 30, action: environment.showPreviousMonth)
                .foregroundStyle(.secondary)

            Button(action: environment.returnToToday) {
                Circle()
                    .fill(Color.secondary)
                    .frame(width: 10, height: 10)
            }
            .buttonStyle(.plain)
            .help("Today")

            iconButton(systemImage: "chevron.right", size: 12, hitSize: 30, action: environment.showNextMonth)
                .foregroundStyle(.secondary)
        }
    }

    private var monthPicker: some View {
        LazyVGrid(columns: monthColumns, spacing: 6) {
            ForEach(Array(environment.monthSymbols.enumerated()), id: \.offset) { offset, month in
                Button {
                    environment.showMonth(offset + 1)
                    showingMonthPicker = false
                } label: {
                    Text(month)
                        .font(.system(size: 13, weight: environment.displayedMonthNumber == offset + 1 ? .semibold : .regular))
                        .frame(width: 48, height: 28)
                        .background {
                            if environment.displayedMonthNumber == offset + 1 {
                                RoundedRectangle(cornerRadius: 5)
                                    .fill(Color.accentColor.opacity(0.18))
                            }
                        }
                }
                .buttonStyle(.plain)
            }
        }
        .padding(10)
        .frame(width: 176)
    }

    private var weekdayHeader: some View {
        LazyVGrid(columns: columns, spacing: 0) {
            ForEach(Array(weekdays.enumerated()), id: \.offset) { _, weekday in
                Text(weekday)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(.primary)
                    .frame(width: 27, height: 18)
            }
        }
    }

    private var dayGrid: some View {
        LazyVGrid(columns: columns, spacing: 4) {
            ForEach(environment.calendarCells) { cell in
                dayCell(cell)
            }
        }
    }

    private func dayCell(_ cell: TrayCalDayCell) -> some View {
        VStack(spacing: 0) {
            Text("\(cell.day)")
                .font(.system(size: 16, weight: cell.isToday ? .semibold : .regular))
                .foregroundStyle(cell.isInDisplayedMonth ? Color.primary : Color.secondary.opacity(0.45))
                .frame(width: 27, height: 20)
                .overlay {
                    if cell.isToday {
                        RoundedRectangle(cornerRadius: 5)
                            .stroke(Color.accentColor, lineWidth: 2)
                            .frame(width: 24, height: 20)
                    }
                }

            Circle()
                .fill(Color.green)
                .frame(width: 4, height: 4)
                .opacity(cell.isPayday ? (cell.isInDisplayedMonth ? 1 : 0.45) : 0)
        }
        .frame(width: 27, height: 25)
    }

    private func headerPickerButton(_ title: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(.primary)
                .padding(.horizontal, 2)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func iconButton(
        systemImage: String,
        size: CGFloat,
        hitSize: CGFloat? = nil,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: size, weight: .semibold))
                .frame(width: hitSize ?? max(22, size + 6), height: hitSize ?? max(22, size + 6))
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func beginYearEdit() {
        yearText = "\(environment.displayedYear)"
        editingYear = true
    }

    private func commitYearEdit(_ value: String) {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        if let year = Int(trimmed), (1...9999).contains(year) {
            environment.showYear(year)
        }
        editingYear = false
    }

    private func cancelYearEdit() {
        yearText = "\(environment.displayedYear)"
        editingYear = false
    }
}

private struct TrayCalYearField: NSViewRepresentable {
    @Binding var text: String
    let onCommit: (String) -> Void
    let onCancel: () -> Void

    func makeNSView(context: Context) -> NSTextField {
        let textField = TrayCalYearTextField()
        textField.delegate = context.coordinator
        textField.stringValue = text
        textField.font = NSFont.systemFont(ofSize: 18, weight: .semibold)
        textField.alignment = .left
        textField.isBordered = false
        textField.drawsBackground = true
        textField.backgroundColor = .controlBackgroundColor
        textField.focusRingType = .default
        textField.lineBreakMode = .byClipping
        textField.onCommit = { value in
            text = value
            onCommit(value)
        }
        textField.onCancel = onCancel

        DispatchQueue.main.async {
            textField.window?.makeFirstResponder(textField)
            textField.currentEditor()?.selectAll(nil)
        }
        return textField
    }

    func updateNSView(_ nsView: NSTextField, context: Context) {
        if nsView.stringValue != text {
            nsView.stringValue = text
        }
        if let textField = nsView as? TrayCalYearTextField {
            textField.onCommit = { value in
                text = value
                onCommit(value)
            }
            textField.onCancel = onCancel
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(text: $text, onCancel: onCancel)
    }

    final class Coordinator: NSObject, NSTextFieldDelegate {
        @Binding private var text: String
        private let onCancel: () -> Void

        init(text: Binding<String>, onCancel: @escaping () -> Void) {
            self._text = text
            self.onCancel = onCancel
        }

        func controlTextDidChange(_ notification: Notification) {
            guard let textField = notification.object as? NSTextField else {
                return
            }
            let filtered = textField.stringValue.filter(\.isNumber)
            let limited = String(filtered.prefix(4))
            if textField.stringValue != limited {
                textField.stringValue = limited
            }
            text = limited
        }

        func controlTextDidEndEditing(_ notification: Notification) {
            guard let textField = notification.object as? NSTextField else {
                return
            }
            text = textField.stringValue
            guard let yearTextField = textField as? TrayCalYearTextField,
                  !yearTextField.didHandleExplicitExit else {
                return
            }
            yearTextField.onCommit?(textField.stringValue)
        }
    }
}

private final class TrayCalYearTextField: NSTextField {
    var onCommit: ((String) -> Void)?
    var onCancel: (() -> Void)?
    var didHandleExplicitExit = false

    override func keyDown(with event: NSEvent) {
        switch event.keyCode {
        case 36, 48, 76:
            didHandleExplicitExit = true
            onCommit?(stringValue)
        case 53:
            didHandleExplicitExit = true
            onCancel?()
        default:
            super.keyDown(with: event)
        }
    }
}
