import AppKit
import BryanToolsShared
import ClipboardHistoryCore
import SwiftUI

struct HistoryView: View {
    @ObservedObject var environment: ClipboardHistoryModule
    @FocusState private var searchFocused: Bool
    @State private var selectedID: UUID?

    private var selectedRecord: ClipRecord? {
        environment.searchResults.first { $0.id == selectedID }
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            results
            Divider()
            footer
        }
        .frame(minWidth: 620, minHeight: 420)
        .background(Color(nsColor: .windowBackgroundColor))
        .background(
            KeyEventHandlingView { event in
                handleKey(event)
            }
        )
        .onAppear {
            environment.refreshSearch()
            selectedID = environment.searchResults.first?.id
            focusSearchField()
        }
        .onChange(of: environment.focusRequestID) { _, _ in
            focusSearchField()
        }
        .onChange(of: environment.searchResults) { _, newResults in
            if selectedID == nil || !newResults.contains(where: { $0.id == selectedID }) {
                selectedID = newResults.first?.id
            }
        }
    }

    private var header: some View {
        HStack(spacing: 10) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.secondary)
            TextField("Search clipboard history", text: $environment.searchQuery)
                .textFieldStyle(.plain)
                .focused($searchFocused)
                .font(.system(size: 17))
            if !environment.searchQuery.isEmpty {
                Button {
                    environment.searchQuery = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
                .help("Clear search")
            }

            Menu {
                ClipboardHistoryMenuContent(environment: environment, includeAppCommands: true)
            } label: {
                Image(systemName: "ellipsis.circle")
            }
            .menuStyle(.button)
            .help("Bryan Tools menu")
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 14)
    }

    private var results: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 0) {
                    if environment.searchResults.isEmpty {
                        ContentUnavailableView(
                            environment.searchQuery.isEmpty ? "No Clipboard History" : "No Matches",
                            systemImage: environment.searchQuery.isEmpty ? "clipboard" : "magnifyingglass"
                        )
                        .frame(maxWidth: .infinity, minHeight: 320)
                    } else {
                        ForEach(environment.searchResults) { record in
                            HistoryRow(
                                record: record,
                                thumbnailImage: environment.thumbnailImage(for: record),
                                isSelected: record.id == selectedID,
                                canFloatImage: environment.canFloatImage(record)
                            ) {
                                environment.floatImage(record)
                                environment.closeHistory()
                            } copy: {
                                environment.copyToClipboard(record)
                            } select: {
                                selectedID = record.id
                            }
                            .id(record.id)
                        }
                    }
                }
                .padding(.vertical, 8)
            }
            .onChange(of: selectedID) { _, id in
                if let id {
                    withAnimation(.easeOut(duration: 0.12)) {
                        proxy.scrollTo(id, anchor: .center)
                    }
                }
            }
        }
    }

    private var footer: some View {
        HStack(spacing: 12) {
            if environment.capturePaused {
                Label("Capture paused", systemImage: "pause.circle")
                    .foregroundStyle(.secondary)
            } else {
                Label("\(environment.searchResults.count) shown", systemImage: "clock.arrow.circlepath")
                    .foregroundStyle(.secondary)
            }

            if let message = environment.lastErrorMessage {
                Label(message, systemImage: "exclamationmark.triangle")
                    .foregroundStyle(.red)
                    .lineLimit(1)
            }

            Spacer()

            Button {
                if let selectedRecord {
                    environment.delete(selectedRecord)
                }
            } label: {
                Image(systemName: "trash")
            }
            .disabled(selectedRecord == nil)
            .help("Delete selected item")

            Button {
                if let selectedRecord {
                    environment.copyToClipboard(selectedRecord)
                }
            } label: {
                Label("Copy", systemImage: "doc.on.clipboard")
            }
            .keyboardShortcut(.return, modifiers: [])
            .disabled(selectedRecord == nil)
        }
        .font(.system(size: 12))
        .padding(.horizontal, 18)
        .padding(.vertical, 10)
        .background(Color(nsColor: .controlBackgroundColor))
    }

    private func handleKey(_ event: NSEvent) -> Bool {
        switch event.keyCode {
        case 53:
            environment.closeHistory()
            return true
        case 36, 76:
            if let selectedRecord {
                if event.modifierFlags.contains(.command),
                   environment.canFloatImage(selectedRecord) {
                    environment.floatImage(selectedRecord)
                    environment.closeHistory()
                    return true
                }
                environment.copyToClipboard(selectedRecord)
                return true
            }
        case 125:
            moveSelection(by: 1)
            return true
        case 126:
            moveSelection(by: -1)
            return true
        case 117:
            deleteSelected()
            return true
        default:
            break
        }
        return false
    }

    private func moveSelection(by delta: Int) {
        let records = environment.searchResults
        guard !records.isEmpty else {
            selectedID = nil
            return
        }
        guard let selectedID,
              let currentIndex = records.firstIndex(where: { $0.id == selectedID }) else {
            self.selectedID = records.first?.id
            return
        }
        let nextIndex = min(max(currentIndex + delta, 0), records.count - 1)
        self.selectedID = records[nextIndex].id
    }

    private func deleteSelected() {
        guard let selectedRecord else {
            return
        }
        environment.delete(selectedRecord)
    }

    private func focusSearchField() {
        searchFocused = false
        DispatchQueue.main.async {
            searchFocused = true
        }
    }
}

private struct HistoryRow: View {
    let record: ClipRecord
    let thumbnailImage: NSImage?
    let isSelected: Bool
    let canFloatImage: Bool
    let floatImage: () -> Void
    let copy: () -> Void
    let select: () -> Void

    @State private var showingImagePreview = false

    private var previewSize: CGFloat {
        thumbnailImage == nil ? 48 : 96
    }

    private var hexColor: NSColor? {
        Self.hexColor(from: record.summary)
    }

    var body: some View {
        HStack(spacing: 12) {
            preview
                .frame(width: previewSize, height: previewSize)

            VStack(alignment: .leading, spacing: 5) {
                Text(record.summary)
                    .font(.system(size: 14, weight: .medium))
                    .lineLimit(2)
                    .foregroundStyle(.primary)

                HStack(spacing: 8) {
                    Label(record.primaryKind.displayName, systemImage: record.primaryKind.symbolName)
                    Text(relativeDateString(for: record.createdAt))
                    Text(byteCountString(record.byteCount))
                    if record.itemCount > 1 {
                        Text("\(record.itemCount) items")
                    }
                }
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .lineLimit(1)
            }

            Spacer(minLength: 12)

            if canFloatImage {
                Button {
                    floatImage()
                } label: {
                    Image(systemName: "rectangle.on.rectangle")
                        .font(.system(size: 16, weight: .medium))
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
                .help("Open as ShotFloat")
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .frame(minHeight: previewSize + 16)
        .contentShape(Rectangle())
        .background(isSelected ? Color.accentColor.opacity(0.16) : Color.clear)
        .onTapGesture {
            select()
        }
        .onTapGesture(count: 2) {
            copy()
        }
    }

    @ViewBuilder
    private var preview: some View {
        if let image = thumbnailImage {
            Image(nsImage: image)
                .resizable()
                .scaledToFit()
                .clipShape(RoundedRectangle(cornerRadius: 6))
                .overlay(
                    RoundedRectangle(cornerRadius: 6)
                        .stroke(Color.secondary.opacity(0.2))
                )
                .onHover { isHovered in
                    showingImagePreview = isHovered
                }
                .popover(isPresented: $showingImagePreview, arrowEdge: .trailing) {
                    ClipboardImageHoverPreview(image: image)
                }
        } else if let hexColor {
            RoundedRectangle(cornerRadius: 6)
                .fill(Color(nsColor: hexColor))
                .overlay(
                    RoundedRectangle(cornerRadius: 6)
                        .stroke(Color.secondary.opacity(0.28))
                )
                .overlay {
                    Image(systemName: "number")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(Color(nsColor: contrastingTextColor(for: hexColor)))
                }
        } else {
            RoundedRectangle(cornerRadius: 6)
                .fill(Color.secondary.opacity(0.12))
                .overlay {
                    Image(systemName: record.primaryKind.symbolName)
                        .font(.system(size: 20, weight: .medium))
                        .foregroundStyle(.secondary)
                }
        }
    }

    private func relativeDateString(for date: Date) -> String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .short
        return formatter.localizedString(for: date, relativeTo: Date())
    }

    private func byteCountString(_ bytes: Int64) -> String {
        ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
    }

    private static func hexColor(from string: String) -> NSColor? {
        let trimmed = string.trimmingCharacters(in: .whitespacesAndNewlines)
        let rawHex: String
        if trimmed.hasPrefix("#") {
            rawHex = String(trimmed.dropFirst())
        } else {
            rawHex = trimmed
        }

        guard rawHex.count == 3 || rawHex.count == 6,
              rawHex.allSatisfy({ $0.isHexDigit }) else {
            return nil
        }

        let expandedHex: String
        if rawHex.count == 3 {
            expandedHex = rawHex.map { "\($0)\($0)" }.joined()
        } else {
            expandedHex = rawHex
        }

        guard let value = Int(expandedHex, radix: 16) else {
            return nil
        }

        return NSColor(
            calibratedRed: CGFloat((value >> 16) & 0xff) / 255,
            green: CGFloat((value >> 8) & 0xff) / 255,
            blue: CGFloat(value & 0xff) / 255,
            alpha: 1
        )
    }

    private func contrastingTextColor(for color: NSColor) -> NSColor {
        guard let rgbColor = color.usingColorSpace(.deviceRGB) else {
            return .labelColor
        }
        let luminance = 0.299 * rgbColor.redComponent
            + 0.587 * rgbColor.greenComponent
            + 0.114 * rgbColor.blueComponent
        return luminance > 0.62 ? .black : .white
    }
}

private struct ClipboardImageHoverPreview: View {
    let image: NSImage

    var body: some View {
        Image(nsImage: image)
            .resizable()
            .scaledToFit()
            .frame(width: 520, height: 390)
            .padding(12)
            .background(Color(nsColor: .windowBackgroundColor))
    }
}
