import BryanToolsShared
import SwiftUI

struct UTCHourPopoverView: View {
    @ObservedObject var environment: UTCHourModule

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            VStack(alignment: .leading, spacing: 3) {
                Text("UTC Hour Lookup")
                    .font(.system(size: 16, weight: .semibold))
                Text("72 hours back and 72 hours forward")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            HStack(spacing: 0) {
                tableHeader("UTC", alignment: .leading)
                tableHeader("Pacific", alignment: .trailing)
            }

            Divider()

            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(environment.lookupRows) { row in
                            rowView(row)
                                .id(row.id)
                        }
                    }
                }
                .background {
                    RoundedRectangle(cornerRadius: 7)
                        .fill(Color.secondary.opacity(0.07))
                }
                .clipShape(RoundedRectangle(cornerRadius: 7))
                .onAppear {
                    scrollToCurrentHour(proxy)
                }
                .onChange(of: environment.currentHour) { _, _ in
                    scrollToCurrentHour(proxy)
                }
            }
        }
        .padding(14)
        .frame(width: 410, height: 420, alignment: .topLeading)
        .background(Color(nsColor: .windowBackgroundColor))
    }

    private func tableHeader(_ title: String, alignment: Alignment) -> some View {
        Text(title)
            .font(.system(size: 12, weight: .semibold))
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, alignment: alignment)
            .padding(.horizontal, 10)
    }

    private func rowView(_ row: UTCHourRow) -> some View {
        Button {
            environment.copyUTCToClipboard(row)
        } label: {
            HStack(spacing: 0) {
                Text(row.utcTitle)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 10)
                Text(row.pacificTitle)
                    .frame(maxWidth: .infinity, alignment: .trailing)
                    .padding(.horizontal, 10)
            }
            .frame(maxWidth: .infinity)
        }
        .buttonStyle(.plain)
        .font(.system(size: 13, weight: row.isCurrentHour ? .semibold : .regular, design: .monospaced))
        .foregroundStyle(row.isCurrentHour ? Color.primary : Color.secondary)
        .frame(maxWidth: .infinity, minHeight: 28, maxHeight: 28)
        .contentShape(Rectangle())
        .help("Copy \(row.utcTitle)")
        .background {
            ZStack {
                if row.isCurrentHour {
                    RoundedRectangle(cornerRadius: 6)
                        .fill(Color.accentColor.opacity(0.16))
                        .padding(.horizontal, 4)
                        .padding(.vertical, 2)
                }

                if row.isPacificMidnight {
                    RoundedRectangle(cornerRadius: 6)
                        .stroke(Color.secondary.opacity(0.55), lineWidth: 1)
                        .padding(.horizontal, 4)
                        .padding(.vertical, 2)
                }
            }
        }
    }

    private func scrollToCurrentHour(_ proxy: ScrollViewProxy) {
        DispatchQueue.main.async {
            proxy.scrollTo(environment.currentHour, anchor: .center)
        }
    }
}
