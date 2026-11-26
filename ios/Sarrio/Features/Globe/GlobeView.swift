import SarrioKit
import SwiftUI

/// Pestaña Globo: todas tus cumbres sobre la Tierra en 3D, con un buscador de picos. Al tocar una
/// cumbre (o elegirla en el buscador) la cámara vuela hasta ella y orbita mientras se ve su ficha.
struct GlobeView: View {
    @Environment(LibraryStore.self) private var library
    @Environment(\.peakPackStore) private var peakPackStore
    @State private var selected: GlobeSelection?
    @State private var overviewToken = 0
    @State private var query = ""
    @State private var results: [Peak] = []
    @State private var searching = false
    @FocusState private var searchFocused: Bool

    var body: some View {
        ZStack(alignment: .top) {
            Globe3DMap(groups: library.peakGroups, selected: $selected, overviewToken: overviewToken)
                .ignoresSafeArea()
                // Simultáneo: los toques siguen llegando al mapa (cumbres, burbujas)
                .simultaneousGesture(TapGesture().onEnded { searchFocused = false })

            VStack(spacing: Theme.Spacing.s) {
                searchBar
                if searchFocused && !query.isEmpty {
                    resultsList.transition(.opacity.combined(with: .move(edge: .top)))
                } else {
                    HStack {
                        summaryPill
                        Spacer()
                        if selected != nil || !library.peakGroups.isEmpty {
                            Button {
                                withAnimation(Theme.Motion.spring) { selected = nil }
                                overviewToken += 1
                            } label: {
                                Label("Todas", systemImage: "globe.europe.africa.fill")
                                    .font(.system(size: 14, weight: .semibold))
                                    .foregroundStyle(.white)
                                    .padding(.horizontal, 14).padding(.vertical, 9)
                                    .background(.ultraThinMaterial, in: Capsule())
                                    .environment(\.colorScheme, .dark)
                            }
                        }
                    }
                    .transition(.opacity)
                }
                Spacer()
                if let selected, !searchFocused {
                    PeakFlyCard(selection: selected) { withAnimation(Theme.Motion.spring) { self.selected = nil } }
                        .padding(.bottom, Theme.Spacing.s)
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                        .id(selected.id)
                } else if library.peakGroups.isEmpty && library.library != nil && !searchFocused {
                    Card(elevation: .high) {
                        Text("Aún no hay cumbres en tu globo")
                            .font(.system(size: 17, weight: .bold))
                            .foregroundStyle(Theme.Colors.textPrimary)
                        Text("Conecta Apple Health o Polar, o importa un GPX, y tus cimas aparecerán aquí. Mientras, busca cualquier pico arriba.")
                            .font(.system(size: 14))
                            .foregroundStyle(Theme.Colors.textSecondary)
                    }
                    .padding(.bottom, Theme.Spacing.s)
                }
            }
            .padding(.horizontal, Theme.Spacing.m)
            .padding(.top, Theme.Spacing.s)
            .animation(Theme.Motion.spring, value: selected?.id)
            .animation(Theme.Motion.spring, value: searchFocused)
        }
        .toolbar(.hidden, for: .navigationBar)
        .task { if library.library == nil { await library.load() } }
        .task(id: query) { await search() }
    }

    // MARK: Buscador

    private var searchBar: some View {
        HStack(spacing: Theme.Spacing.s) {
            Image(systemName: "magnifyingglass").font(.system(size: 15, weight: .semibold)).foregroundStyle(.white.opacity(0.8))
            TextField("", text: $query, prompt: Text("Buscar un pico").foregroundStyle(.white.opacity(0.6)))
                .focused($searchFocused)
                .submitLabel(.search)
                .autocorrectionDisabled()
                .foregroundStyle(.white)
                .font(.system(size: 16, weight: .medium))
                .onSubmit { if let first = results.first { choose(first) } }
            if searching { ProgressView().controlSize(.small).tint(.white) }
            if !query.isEmpty {
                Button { query = ""; results = [] } label: {
                    Image(systemName: "xmark.circle.fill").font(.system(size: 16)).foregroundStyle(.white.opacity(0.7))
                }
            }
        }
        .padding(.horizontal, 14)
        .frame(height: 46)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous))
        .environment(\.colorScheme, .dark)
        .elevation(.medium)
    }

    private var resultsList: some View {
        let ascended = Set(library.peakGroups.map(\.id))
        return VStack(spacing: 0) {
            if results.isEmpty && !searching {
                Text(query.count < 2 ? "Escribe al menos dos letras" : "No hay picos con ese nombre")
                    .font(.system(size: 14)).foregroundStyle(Theme.Colors.textSecondary)
                    .frame(maxWidth: .infinity).padding(Theme.Spacing.m)
            }
            ForEach(Array(results.enumerated()), id: \.element.id) { index, peak in
                Button { choose(peak) } label: {
                    HStack(spacing: Theme.Spacing.m) {
                        Image(systemName: ascended.contains(peak.id) ? "checkmark.seal.fill" : "triangle.fill")
                            .font(.system(size: 13, weight: .bold))
                            .foregroundStyle(Theme.Colors.accent)
                            .frame(width: 30, height: 30)
                            .background(Theme.Colors.accent.opacity(0.1), in: Circle())
                        VStack(alignment: .leading, spacing: 1) {
                            Text(peak.displayName).font(.system(size: 16, weight: .semibold)).foregroundStyle(Theme.Colors.textPrimary).lineLimit(1)
                            Text(peak.range ?? (ascended.contains(peak.id) ? "Subido" : " "))
                                .font(.system(size: 12)).foregroundStyle(Theme.Colors.textSecondary)
                        }
                        Spacer(minLength: 0)
                        if let ele = peak.ele {
                            Text("\(ele.groupedInteger) m").font(.system(size: 15, weight: .bold).monospacedDigit()).foregroundStyle(Theme.Colors.textPrimary)
                        }
                    }
                    .padding(.horizontal, Theme.Spacing.m).padding(.vertical, 10)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                if index < results.count - 1 { Divider().padding(.leading, 62) }
            }
        }
        .background(Theme.Colors.surface, in: RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous))
        .elevation(.high)
        .frame(maxHeight: 420, alignment: .top)
    }

    /// Con un pequeño respiro entre teclas (la tarea se cancela si se sigue escribiendo).
    private func search() async {
        let q = query
        guard q.trimmingCharacters(in: .whitespaces).count >= 2 else { results = []; return }
        try? await Task.sleep(for: .milliseconds(180))
        guard !Task.isCancelled else { return }
        searching = true
        let found = await peakPackStore.search(q, preferred: Set(library.peakGroups.map(\.id)), limit: 12)
        guard !Task.isCancelled else { return }
        searching = false
        results = found
    }

    private func choose(_ peak: Peak) {
        let group = library.peakGroups.first { $0.id == peak.id }
        searchFocused = false
        withAnimation(Theme.Motion.spring) { selected = GlobeSelection(peak: group?.peak ?? PeakRef(peak), group: group) }
    }

    // MARK: Resumen

    private var summaryPill: some View {
        let summary = library.library?.summary
        return HStack(spacing: Theme.Spacing.m) {
            stat("\(summary?.uniquePeaks ?? 0)", "picos")
            if let top = summary?.highestPeak?.ele {
                stat(top.groupedInteger, "m máx.")
            }
        }
        .padding(.horizontal, 14).padding(.vertical, 9)
        .background(.ultraThinMaterial, in: Capsule())
        .environment(\.colorScheme, .dark)
    }

    private func stat(_ value: String, _ unit: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 3) {
            Text(value).font(.system(size: 17, weight: .bold).monospacedDigit()).foregroundStyle(.white)
            Text(unit).font(.system(size: 12, weight: .semibold)).foregroundStyle(.white.opacity(0.7))
        }
    }
}

/// Ficha del pico elegido: flota sobre el mapa mientras la cámara orbita la cima.
private struct PeakFlyCard: View {
    var selection: GlobeSelection
    var close: () -> Void

    private var peak: PeakRef { selection.peak }

    var body: some View {
        Card(padding: Theme.Spacing.m, elevation: .high) {
            HStack(alignment: .top, spacing: Theme.Spacing.m) {
                PeakBadge(count: selection.group?.ascents.count ?? 0, size: 48)
                VStack(alignment: .leading, spacing: 2) {
                    Text(peak.displayName)
                        .font(.system(size: 20, weight: .heavy))
                        .foregroundStyle(Theme.Colors.textPrimary)
                        .lineLimit(2)
                    Text(locationLine)
                        .font(.system(size: 13))
                        .foregroundStyle(Theme.Colors.textSecondary)
                }
                Spacer(minLength: 0)
                Button(action: close) {
                    Image(systemName: "xmark")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(Theme.Colors.textSecondary)
                        .frame(width: 28, height: 28)
                        .background(Theme.Colors.groupedBackground, in: Circle())
                }
            }
            HStack(alignment: .firstTextBaseline, spacing: 3) {
                if let ele = peak.ele {
                    Text(ele.groupedInteger).font(.heroValue).foregroundStyle(Theme.Colors.textPrimary)
                    Text("m").font(.system(size: 17, weight: .bold)).foregroundStyle(Theme.Colors.textSecondary)
                }
                Spacer()
            }
            Divider()
            HStack {
                if let group = selection.group {
                    VStack(alignment: .leading, spacing: 1) {
                        Text(group.ascents.count == 1 ? "Subido una vez" : "Subido \(group.ascents.count) veces")
                            .font(.system(size: 15, weight: .semibold)).foregroundStyle(Theme.Colors.textPrimary)
                        Text("Última: \(group.lastAscent.formatted(date: .long, time: .omitted))")
                            .font(.system(size: 13)).foregroundStyle(Theme.Colors.textSecondary)
                    }
                    Spacer()
                    NavigationLink { PeakDetailView(group: group) } label: {
                        Label("Ver pico", systemImage: "arrow.right")
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 16).padding(.vertical, 10)
                            .background(Theme.Colors.accent, in: Capsule())
                            .elevation(.medium)
                    }
                    .buttonStyle(.pressableCard)
                } else {
                    Label("Aún no lo has subido", systemImage: "flag")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(Theme.Colors.textSecondary)
                    Spacer()
                }
            }
        }
        .sensoryFeedback(.selection, trigger: selection.id)
    }

    private var locationLine: String {
        let coords = String(format: "%.4f°, %.4f°", peak.lat, peak.lon)
        return [peak.range, coords].compactMap { $0 }.joined(separator: " · ")
    }
}
