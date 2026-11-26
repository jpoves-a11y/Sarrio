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
                                // Solo el icono: vuelve a ver todas
                                Image(systemName: "globe.europe.africa")
                                    .font(.system(size: 20, weight: .light))
                                    .foregroundStyle(.white)
                                    .shadow(color: .black.opacity(0.5), radius: 3, y: 1)
                                    .frame(width: 40, height: 40)
                                    .contentShape(Rectangle())
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
                            .font(.sarrio(17, .bold))
                            .foregroundStyle(Theme.Colors.textPrimary)
                        Text("Conecta Apple Health o Polar, o importa un GPX, y tus cimas aparecerán aquí. Mientras, busca cualquier pico arriba.")
                            .font(.sarrio(14))
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
            Image(systemName: "magnifyingglass").font(.system(size: 15, weight: .regular)).foregroundStyle(.white.opacity(0.85))
            TextField("", text: $query, prompt: Text("Buscar un pico").foregroundStyle(.white.opacity(0.75)))
                .focused($searchFocused)
                .submitLabel(.search)
                .autocorrectionDisabled()
                .foregroundStyle(.white)
                .font(.sarrio(16, .medium))
                .onSubmit { if let first = results.first { choose(first) } }
            if searching { ProgressView().controlSize(.small).tint(.white) }
            if !query.isEmpty {
                Button { query = ""; results = [] } label: {
                    Image(systemName: "xmark.circle.fill").font(.system(size: 16)).foregroundStyle(.white.opacity(0.7))
                }
            }
        }
        // Barra fina y translúcida, sin cuadro: solo una línea debajo
        .padding(.horizontal, 4)
        .frame(height: 40)
        .overlay(alignment: .bottom) { Rectangle().fill(.white.opacity(searchFocused ? 0.7 : 0.35)).frame(height: 0.5) }
        .shadow(color: .black.opacity(0.35), radius: 3, y: 1)
    }

    private var resultsList: some View {
        let ascended = Set(library.peakGroups.map(\.id))
        return VStack(spacing: 0) {
            if results.isEmpty && !searching {
                Text(query.count < 2 ? "Escribe al menos dos letras" : "No hay picos con ese nombre")
                    .font(.sarrio(14)).foregroundStyle(Theme.Colors.textSecondary)
                    .frame(maxWidth: .infinity).padding(Theme.Spacing.m)
            }
            ForEach(Array(results.enumerated()), id: \.element.id) { index, peak in
                Button { choose(peak) } label: {
                    HStack(spacing: Theme.Spacing.m) {
                        Image(systemName: ascended.contains(peak.id) ? "checkmark.seal.fill" : "triangle.fill")
                            .font(.system(size: 13, weight: .bold))
                            .foregroundStyle(Theme.Colors.accent)
                            .frame(width: 30, height: 30)
                        VStack(alignment: .leading, spacing: 1) {
                            Text(peak.displayName).font(.sarrio(16, .semibold)).foregroundStyle(Theme.Colors.textPrimary).fixedSize(horizontal: false, vertical: true)
                            Text(peak.range ?? (ascended.contains(peak.id) ? "Subido" : " "))
                                .font(.sarrio(12)).foregroundStyle(Theme.Colors.textSecondary)
                        }
                        Spacer(minLength: 0)
                        if let ele = peak.ele {
                            Text("\(ele.groupedInteger) m").font(.sarrio(15, .bold).monospacedDigit()).foregroundStyle(Theme.Colors.textPrimary)
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
        // Texto suelto sobre el mapa, sin caja
        .shadow(color: .black.opacity(0.55), radius: 3, y: 1)
    }

    private func stat(_ value: String, _ unit: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 3) {
            Text(value).font(.sarrio(14, .semibold).monospacedDigit()).foregroundStyle(.white)
            Text(unit).font(.sarrio(12)).foregroundStyle(.white.opacity(0.75))
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
                        .font(.sarrio(20, .semibold))
                        .foregroundStyle(Theme.Colors.textPrimary)
                        .fixedSize(horizontal: false, vertical: true)
                    Text(locationLine)
                        .font(.sarrio(13))
                        .foregroundStyle(Theme.Colors.textSecondary)
                }
                Spacer(minLength: 0)
                Button(action: close) {
                    Image(systemName: "xmark")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(Theme.Colors.textSecondary)
                        .frame(width: 28, height: 28)
                        .background(Theme.Colors.groupedBackground, in: RoundedRectangle(cornerRadius: Theme.Radius.chip, style: .continuous))
                }
            }
            HStack(alignment: .firstTextBaseline, spacing: 3) {
                if let ele = peak.ele {
                    Text(ele.groupedInteger).font(.heroValue).foregroundStyle(Theme.Colors.textPrimary)
                    Text("m").font(.sarrio(17, .bold)).foregroundStyle(Theme.Colors.textSecondary)
                }
                Spacer()
            }
            Divider()
            HStack {
                if let group = selection.group {
                    VStack(alignment: .leading, spacing: 1) {
                        Text(group.ascents.count == 1 ? "Subido una vez" : "Subido \(group.ascents.count) veces")
                            .font(.sarrio(15, .semibold)).foregroundStyle(Theme.Colors.textPrimary)
                        Text("Última: \(group.lastAscent.formatted(date: .long, time: .omitted))")
                            .font(.sarrio(13)).foregroundStyle(Theme.Colors.textSecondary)
                    }
                    Spacer()
                    NavigationLink { PeakDetailView(group: group) } label: {
                        Label("Ver pico", systemImage: "arrow.right")
                            .font(.sarrio(15, .semibold))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 16).padding(.vertical, 10)
                            .background(Theme.Colors.accent, in: RoundedRectangle(cornerRadius: Theme.Radius.chip, style: .continuous))
                            .elevation(.medium)
                    }
                    .buttonStyle(.pressableCard)
                } else {
                    Label("Aún no lo has subido", systemImage: "flag")
                        .font(.sarrio(15, .semibold))
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
