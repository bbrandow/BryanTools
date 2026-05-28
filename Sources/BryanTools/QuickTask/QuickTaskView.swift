import AppKit
import BryanToolsShared
import Carbon
import SwiftUI

struct QuickTaskView: View {
    @ObservedObject var environment: QuickTaskModule
    @FocusState private var searchFocused: Bool
    @State private var selectedApplicationID: String?

    private var selectedApplication: QuickTaskApplication? {
        environment.matches.first { $0.id == selectedApplicationID }
    }

    var body: some View {
        VStack(spacing: 0) {
            inputBar

            if shouldShowResults {
                Divider()
                    .padding(.horizontal, 14)

                results
            }
        }
        .frame(
            minWidth: QuickTaskModule.minimumPanelSize.width,
            idealWidth: QuickTaskModule.barOnlyPanelSize.width,
            maxWidth: .infinity,
            minHeight: QuickTaskModule.minimumPanelSize.height,
            maxHeight: .infinity,
            alignment: .top
        )
        .background(
            RoundedRectangle(cornerRadius: 18)
                .fill(Color(nsColor: .windowBackgroundColor))
                .shadow(color: Color.black.opacity(0.22), radius: 20, x: 0, y: 10)
        )
        .clipShape(RoundedRectangle(cornerRadius: 18))
        .overlay(
            RoundedRectangle(cornerRadius: 18)
                .stroke(Color.secondary.opacity(0.18))
        )
        .background(
            KeyEventHandlingView { event in
                handleKey(event)
            }
        )
        .onAppear {
            focusSearchField()
        }
        .onChange(of: environment.focusRequestID) { _, _ in
            focusSearchField()
        }
        .onChange(of: environment.query) { _, _ in
            selectedApplicationID = nil
        }
        .onChange(of: environment.matches) { _, matches in
            if let selectedApplicationID,
               !matches.contains(where: { $0.id == selectedApplicationID }) {
                self.selectedApplicationID = nil
            }
        }
    }

    private var shouldShowResults: Bool {
        environment.commandResult != nil || environment.calculationResult != nil || !environment.matches.isEmpty
    }

    private var inputBar: some View {
        HStack(spacing: 14) {
            leadingIcon
                .frame(width: 28, height: 28)

            TextField(placeholderText, text: $environment.query)
                .textFieldStyle(.plain)
                .font(.system(size: 30, weight: .regular))
                .focused($searchFocused)
                .onSubmit {
                    submit()
                }

            if !environment.query.isEmpty {
                Button {
                    environment.query = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 17))
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
                .help("Clear")
            }
        }
        .padding(.horizontal, 22)
        .frame(height: QuickTaskModule.barOnlyPanelSize.height)
    }

    @ViewBuilder
    private var leadingIcon: some View {
        if environment.mode == .commandLine {
            Text(">")
                .font(.system(size: 28, weight: .semibold, design: .monospaced))
                .foregroundStyle(.secondary)
        } else if environment.calculationResult != nil {
            Image(systemName: "function")
                .foregroundStyle(.secondary)
        } else {
            Image(systemName: "command")
                .font(.system(size: 25, weight: .regular))
                .foregroundStyle(.secondary)
        }
    }

    private var placeholderText: String {
        environment.mode == .commandLine ? "Run shell command" : "Search apps or calculate"
    }

    @ViewBuilder
    private var results: some View {
        VStack(alignment: .leading, spacing: 0) {
            if let commandResult = environment.commandResult {
                QuickTaskCommandResultRow(result: commandResult)
            } else if let calculationResult = environment.calculationResult {
                QuickTaskCalculationRow(expression: environment.query, result: calculationResult)
            } else if !environment.matches.isEmpty {
                ForEach(environment.matches) { app in
                    QuickTaskApplicationRow(
                        application: app,
                        isSelected: app.id == selectedApplicationID
                    ) {
                        environment.launch(app)
                    }
                    if app.id != environment.matches.last?.id {
                        Divider()
                    }
                }
            }
        }
        .padding(.bottom, environment.resultBottomPadding)
        .frame(height: environment.resultContentHeight, alignment: .top)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private func handleKey(_ event: NSEvent) -> Bool {
        if environment.mode == .search,
           environment.query.isEmpty,
           event.characters == ">" {
            environment.enterCommandLineMode()
            return true
        }

        switch event.keyCode {
        case UInt16(kVK_Escape):
            environment.dismissQuickTask()
            return true
        case UInt16(kVK_Return), UInt16(kVK_ANSI_KeypadEnter):
            submit()
            return true
        case UInt16(kVK_Delete), UInt16(kVK_ForwardDelete):
            return environment.exitCommandLineModeIfEmpty()
        case UInt16(kVK_Tab), UInt16(kVK_DownArrow):
            selectNextApplication()
            return true
        case UInt16(kVK_UpArrow):
            selectPreviousApplication()
            return true
        default:
            return false
        }
    }

    private func submit() {
        if let selectedApplication {
            environment.launch(selectedApplication)
        } else {
            environment.submitQuery()
        }
    }

    private func focusSearchField() {
        searchFocused = false
        DispatchQueue.main.async {
            searchFocused = true
        }
    }

    private func selectNextApplication() {
        guard !environment.matches.isEmpty else {
            selectedApplicationID = nil
            return
        }
        guard let selectedApplicationID,
              let index = environment.matches.firstIndex(where: { $0.id == selectedApplicationID }) else {
            selectedApplicationID = environment.matches.first?.id
            return
        }
        let nextIndex = min(index + 1, environment.matches.count - 1)
        self.selectedApplicationID = environment.matches[nextIndex].id
    }

    private func selectPreviousApplication() {
        guard !environment.matches.isEmpty else {
            selectedApplicationID = nil
            return
        }
        guard let selectedApplicationID,
              let index = environment.matches.firstIndex(where: { $0.id == selectedApplicationID }) else {
            selectedApplicationID = environment.matches.last?.id
            return
        }
        let previousIndex = max(index - 1, 0)
        self.selectedApplicationID = environment.matches[previousIndex].id
    }
}

private struct QuickTaskCommandResultRow: View {
    let result: QuickTaskCommandResult

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: "terminal")
                .foregroundStyle(.secondary)
                .frame(width: 30)

            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 8) {
                    Text(result.command)
                        .font(.system(.caption, design: .monospaced))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)

                    Spacer()

                    if result.isRunning {
                        ProgressView()
                            .scaleEffect(0.55)
                            .frame(width: 18, height: 18)
                    } else {
                        Text("exit \(result.exitCodeDescription)")
                            .font(.caption)
                            .foregroundStyle(result.exitCode == 0 ? Color.secondary : Color.red)
                    }
                }

                ScrollView {
                    Text(outputText)
                        .font(.system(.caption, design: .monospaced))
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .frame(maxHeight: .infinity, alignment: .top)
            }
        }
        .padding(16)
        .frame(height: QuickTaskModule.commandResultRowHeight)
    }

    private var outputText: String {
        if result.isRunning {
            return "Running..."
        }
        if result.output.isEmpty {
            return "No output"
        }
        return result.output
    }
}

private struct QuickTaskApplicationRow: View {
    let application: QuickTaskApplication
    let isSelected: Bool
    let launch: () -> Void

    var body: some View {
        Button {
            launch()
        } label: {
            HStack(spacing: 12) {
                if let icon = application.icon {
                    Image(nsImage: icon)
                        .resizable()
                        .frame(width: 30, height: 30)
                } else {
                    Image(systemName: "app")
                        .frame(width: 30, height: 30)
                }

                Text(application.name)
                    .font(.system(size: 15, weight: .medium))

                Spacer()

                Text(application.url.deletingLastPathComponent().path)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .frame(height: QuickTaskModule.applicationRowHeight)
            .contentShape(Rectangle())
            .background(isSelected ? Color.accentColor.opacity(0.16) : Color.clear)
        }
        .buttonStyle(.plain)
    }
}

private struct QuickTaskCalculationRow: View {
    let expression: String
    let result: String

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "function")
                .foregroundStyle(.secondary)
                .frame(width: 30)
            VStack(alignment: .leading, spacing: 4) {
                Text(result)
                    .font(.system(size: 24, weight: .semibold, design: .monospaced))
                    .textSelection(.enabled)
                Text(expression)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer()
        }
        .padding(16)
        .frame(height: QuickTaskModule.calculationRowHeight)
    }
}
