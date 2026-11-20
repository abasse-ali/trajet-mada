import SwiftUI
import TrajetCore
import UIKit

struct LogView: View {
    @Environment(LogStore.self) private var log
    @State private var minLevel: LogLevel = .info
    @State private var category: LogCategory?
    @State private var query = ""
    @State private var confirmClear = false
    @State private var copied = false

    private var filtered: [LogEntry] {
        log.entries.reversed().filter { entry in
            entry.level.rank >= minLevel.rank
                && (category == nil || entry.category == category)
                && (query.isEmpty
                    || entry.message.localizedCaseInsensitiveContains(query)
                    || (entry.details ?? "").localizedCaseInsensitiveContains(query))
        }
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Picker("Niveau minimum", selection: $minLevel) {
                        ForEach(LogLevel.allCases) { level in
                            Text(level.label).tag(level)
                        }
                    }
                    .pickerStyle(.segmented)
                    Picker("Catégorie", selection: $category) {
                        Text("Toutes").tag(LogCategory?.none)
                        ForEach(LogCategory.allCases) { item in
                            Text(item.label).tag(LogCategory?.some(item))
                        }
                    }
                } footer: {
                    Text("Le journal garde les 3 000 derniers événements : appels aux API (sans les clés), erreurs, calculs. Partagez-le pour signaler un problème.")
                }

                Section {
                    if filtered.isEmpty {
                        Text("Aucun événement.")
                            .foregroundStyle(.secondary)
                    }
                    ForEach(filtered) { entry in
                        LogRow(entry: entry)
                    }
                } header: {
                    Text("\(filtered.count) événement\(filtered.count > 1 ? "s" : "")")
                }
            }
            .searchable(text: $query, prompt: "Rechercher dans le journal")
            .navigationTitle("Journal")
            .toolbar {
                ToolbarItemGroup(placement: .topBarTrailing) {
                    ShareLink(item: log.exportText(Array(filtered.reversed()))) {
                        Icon("ui.share", size: 19, color: .accentColor)
                    }
                    .accessibilityLabel("Partager le journal")
                    Button {
                        UIPasteboard.general.string = log.exportText(Array(filtered.reversed()))
                        copied = true
                    } label: {
                        Icon(copied ? "ui.check" : "ui.copy", size: 19, color: .accentColor)
                    }
                    .accessibilityLabel("Copier le journal")
                    Button {
                        confirmClear = true
                    } label: {
                        Icon("ui.trash", size: 19, color: .red)
                    }
                    .accessibilityLabel("Effacer le journal")
                }
            }
            .confirmationDialog("Effacer tout le journal ?", isPresented: $confirmClear, titleVisibility: .visible) {
                Button("Effacer", role: .destructive) { log.clear() }
            }
            .onChange(of: query) { _, _ in copied = false }
        }
    }
}

struct LogRow: View {
    let entry: LogEntry
    @State private var expanded = false

    private static let timeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "fr_FR")
        formatter.dateFormat = "dd/MM HH:mm:ss"
        return formatter
    }()

    private var color: Color {
        switch entry.level {
        case .debug: return .gray
        case .info: return .accentColor
        case .warning: return .orange
        case .error: return .red
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
                Circle()
                    .fill(color)
                    .frame(width: 8, height: 8)
                Text(Self.timeFormatter.string(from: entry.date))
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
                Text(entry.category.label)
                    .font(.caption2.weight(.semibold))
                    .padding(.horizontal, 5)
                    .padding(.vertical, 1)
                    .background(Color.secondary.opacity(0.14), in: Capsule())
                Spacer()
                if entry.details != nil {
                    Icon("ui.chevron", size: 11, color: .secondary)
                        .rotationEffect(.degrees(expanded ? 90 : 0))
                }
            }
            Text(entry.message)
                .font(.footnote)
                .foregroundStyle(entry.level == .error ? Color.red : Color.primary)
            if expanded, let details = entry.details {
                Text(details)
                    .font(.caption2.monospaced())
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
            }
        }
        .contentShape(Rectangle())
        .onTapGesture {
            if entry.details != nil { expanded.toggle() }
        }
    }
}
