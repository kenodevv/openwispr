import SwiftData
import SwiftUI

struct HistoryView: View {
    @Query(sort: \DictationEntry.date, order: .reverse) private var entries: [DictationEntry]
    @Environment(\.modelContext) private var context
    @State private var search = ""
    @State private var selection: DictationEntry.ID?

    private var filtered: [DictationEntry] {
        guard !search.isEmpty else { return entries }
        return entries.filter {
            $0.finalText.localizedCaseInsensitiveContains(search) || $0.rawTranscript.localizedCaseInsensitiveContains(search) || $0.appName.localizedCaseInsensitiveContains(search)
        }
    }

    private var selectedEntry: DictationEntry? {
        filtered.first { $0.id == selection }
    }

    var body: some View {
        VStack(spacing: 0) {
            StatsView(stats: Store.stats(for: entries))
                .padding()
            Divider()
            HSplitView {
                List(filtered, selection: $selection) { entry in
                    VStack(alignment: .leading, spacing: 3) {
                        Text(entry.finalText.isEmpty ? "—" : entry.finalText)
                            .lineLimit(2)
                        HStack(spacing: 6) {
                            Text(entry.date, format: .dateTime.day().month().hour().minute())
                            Text("·")
                            Text(entry.appName.isEmpty ? "Unknown app" : entry.appName)
                            if entry.mode == DictationMode.command.rawValue {
                                Text("· command")
                            }
                        }
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    }
                    .padding(.vertical, 3)
                    .tag(entry.id)
                }
                .frame(minWidth: 320)
                .searchable(text: $search, placement: .sidebar, prompt: "Search")

                Group {
                    if let entry = selectedEntry {
                        EntryDetailView(entry: entry, onDelete: {
                            context.delete(entry)
                            try? context.save()
                            selection = nil
                        })
                    } else {
                        ContentUnavailableView("Nothing selected", systemImage: "text.quote",
                                               description: Text(entries.isEmpty ? "No dictations yet. Hold Fn and speak." : "Pick a dictation on the left."))
                    }
                }
                .frame(minWidth: 380, maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .frame(minWidth: 820, minHeight: 500)
    }
}

struct StatsView: View {
    let stats: DictationStats

    var body: some View {
        HStack(spacing: 28) {
            stat("Dictations", "\(stats.dictations)")
            stat("Words", "\(stats.words)")
            stat("Avg words/min", String(format: "%.0f", stats.averageWPM))
            stat("Time saved", formattedMinutes(stats.minutesSaved))
            Spacer()
        }
    }

    private func stat(_ label: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(value).font(.system(size: 22, weight: .semibold, design: .rounded))
            Text(label).font(.caption).foregroundStyle(.secondary)
        }
    }

    private func formattedMinutes(_ minutes: Double) -> String {
        if minutes < 60 { return String(format: "%.0f min", minutes) }
        return String(format: "%.1f h", minutes / 60)
    }
}

private struct EntryDetailView: View {
    let entry: DictationEntry
    let onDelete: () -> Void

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(entry.appName.isEmpty ? "Unknown app" : entry.appName).font(.headline)
                        Text("\(entry.date.formatted(date: .abbreviated, time: .shortened)) · \(String(format: "%.1f", entry.audioSeconds)) s audio · \(entry.latencyMs) ms · \(entry.model)")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button(role: .destructive, action: onDelete) { Image(systemName: "trash") }
                }
                section("Result", entry.finalText)
                section("Raw transcript", entry.rawTranscript)
            }
            .padding()
        }
    }

    private func section(_ title: String, _ text: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(title).font(.subheadline.weight(.semibold))
                Spacer()
                Button("Copy") {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(text, forType: .string)
                }
                .controlSize(.small)
            }
            Text(text.isEmpty ? "—" : text)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(10)
                .background(RoundedRectangle(cornerRadius: 8).fill(Color(nsColor: .controlBackgroundColor)))
        }
    }
}
