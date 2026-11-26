import SarrioKit
import SwiftUI

/// Un pico de la biblioteca: relieve 3D que se puede girar y todas las veces que has subido.
struct PeakDetailView: View {
    var group: PeakGroup
    @Environment(LibraryStore.self) private var store

    var body: some View {
        ScrollView {
            VStack(spacing: Theme.Spacing.l) {
                ZStack(alignment: .bottomLeading) {
                    Terrain3DView(center: group.peak.coordinate, distance: 2_600, summits: [group.peak], orbit: true, interactive: true)
                    LinearGradient(colors: [.clear, .black.opacity(0.65)], startPoint: .center, endPoint: .bottom)
                        .allowsHitTesting(false)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(group.peak.displayName).font(.system(size: 26, weight: .heavy)).foregroundStyle(.white)
                        if let ele = group.peak.ele {
                            HStack(alignment: .firstTextBaseline, spacing: 4) {
                                Text(ele.groupedInteger).font(.heroValue).foregroundStyle(.white)
                                Text("m").font(.system(size: 18, weight: .bold)).foregroundStyle(.white.opacity(0.8))
                            }
                        }
                    }
                    .padding(Theme.Spacing.m)
                    .allowsHitTesting(false)
                }
                .frame(height: 420)
                .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.hero, style: .continuous))
                .elevation(.high)
                .padding(.top, Theme.Spacing.s)

                Card(elevation: .medium) {
                    StatRow(stats: [
                        ("Ascensiones", "\(group.ascents.count)", nil),
                        ("Primera", group.ascents.last?.summitedAt.formatted(.dateTime.year()) ?? "–", nil),
                        ("Última", group.ascents.first?.summitedAt.formatted(.dateTime.year()) ?? "–", nil),
                    ])
                }
                .staggeredAppear(1)

                VStack(spacing: Theme.Spacing.s) {
                    SectionHeader(title: "Tus ascensiones")
                    ForEach(Array(group.ascents.enumerated()), id: \.element.id) { index, ascent in
                        ascentRow(ascent).staggeredAppear(index + 2)
                    }
                }
            }
            .padding(.horizontal, Theme.Spacing.m)
            .padding(.bottom, Theme.Spacing.xl)
        }
        .background(Theme.Colors.groupedBackground)
        .navigationBarTitleDisplayMode(.inline)
    }

    @ViewBuilder private func ascentRow(_ ascent: Ascent) -> some View {
        let row = Card(elevation: .low) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(ascent.summitedAt.formatted(date: .long, time: .omitted))
                        .font(.system(size: 16, weight: .semibold)).foregroundStyle(Theme.Colors.textPrimary)
                    Text(ascent.note ?? (ascent.activityId == nil ? "Añadida a mano" : "Desde una actividad"))
                        .font(.system(size: 13)).foregroundStyle(Theme.Colors.textSecondary)
                }
                Spacer()
                if ascent.activityId != nil {
                    Image(systemName: "chevron.right").font(.system(size: 13, weight: .semibold)).foregroundStyle(Theme.Colors.textSecondary)
                }
            }
        }
        if let activityId = ascent.activityId, let activity = store.activities.first(where: { $0.id == activityId }) {
            NavigationLink { ActivityDetailView(activity: activity) } label: { row }.buttonStyle(.pressableCard)
        } else {
            row
        }
    }
}
