import SarrioKit
import SwiftUI

/// Pestaña Globo: todas tus cumbres sobre la Tierra en 3D. Al tocar una, la cámara vuela hasta
/// ella y aparece su tarjeta.
struct GlobeView: View {
    @Environment(LibraryStore.self) private var library
    @State private var selected: PeakGroup?
    @State private var overviewToken = 0

    var body: some View {
        ZStack(alignment: .bottom) {
            Globe3DMap(groups: library.peakGroups, selected: $selected, overviewToken: overviewToken)
                .ignoresSafeArea()

            VStack(spacing: Theme.Spacing.m) {
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
                .padding(.horizontal, Theme.Spacing.m)
                Spacer()
                if let selected {
                    PeakFlyCard(group: selected) { withAnimation(Theme.Motion.spring) { self.selected = nil } }
                        .padding(.horizontal, Theme.Spacing.m)
                        .padding(.bottom, Theme.Spacing.s)
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                        .id(selected.id)
                } else if library.peakGroups.isEmpty && library.library != nil {
                    Card(elevation: .high) {
                        Text("Aún no hay cumbres en tu globo")
                            .font(.system(size: 17, weight: .bold))
                            .foregroundStyle(Theme.Colors.textPrimary)
                        Text("Conecta Apple Health o Polar, o importa un GPX, y tus cimas aparecerán aquí.")
                            .font(.system(size: 14))
                            .foregroundStyle(Theme.Colors.textSecondary)
                    }
                    .padding(.horizontal, Theme.Spacing.m)
                    .padding(.bottom, Theme.Spacing.s)
                }
            }
            .padding(.top, Theme.Spacing.s)
            .animation(Theme.Motion.spring, value: selected?.id)
        }
        .toolbar(.hidden, for: .navigationBar)
        .task { if library.library == nil { await library.load() } }
    }

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

/// Tarjeta del pico elegido en el globo: flota sobre el mapa con sombra y se inclina al tocarla.
private struct PeakFlyCard: View {
    var group: PeakGroup
    var close: () -> Void

    var body: some View {
        Card(padding: Theme.Spacing.m, elevation: .high) {
            HStack(alignment: .top, spacing: Theme.Spacing.m) {
                PeakBadge(count: group.ascents.count, size: 48)
                VStack(alignment: .leading, spacing: 2) {
                    Text(group.peak.displayName)
                        .font(.system(size: 20, weight: .heavy))
                        .foregroundStyle(Theme.Colors.textPrimary)
                        .lineLimit(1)
                    Text(subtitle)
                        .font(.system(size: 14))
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
            HStack(alignment: .bottom) {
                if let ele = group.peak.ele {
                    HStack(alignment: .firstTextBaseline, spacing: 3) {
                        Text(ele.groupedInteger).font(.heroValue).foregroundStyle(Theme.Colors.textPrimary)
                        Text("m").font(.system(size: 17, weight: .bold)).foregroundStyle(Theme.Colors.textSecondary)
                    }
                }
                Spacer()
                NavigationLink { PeakDetailView(group: group) } label: {
                    Label("Ver pico", systemImage: "arrow.right")
                        .labelStyle(.titleAndIcon)
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 16).padding(.vertical, 10)
                        .background(Theme.Colors.accent, in: Capsule())
                        .elevation(.medium)
                }
                .buttonStyle(.pressableCard)
            }
        }
        .interactiveTilt(maxAngle: 4)
        .frame(height: 170)
        .sensoryFeedback(.selection, trigger: group.id)
    }

    private var subtitle: String {
        let last = group.lastAscent.formatted(date: .abbreviated, time: .omitted)
        return group.ascents.count == 1 ? "Subido el \(last)" : "Subido \(group.ascents.count) veces · última \(last)"
    }
}
