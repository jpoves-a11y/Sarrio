import SarrioKit
import SwiftUI

/// Un pico de la biblioteca. Arriba, el relieve 3D a sangre (sin marco), que gira solo y se puede
/// mover con los dedos; abajo, una hoja blanca que lo solapa con el nombre, una altitud discreta y
/// tus ascensiones. El mapa no aparece hasta tener cargado el detalle (ver `Terrain3DView`).
struct PeakDetailView: View {
    var group: PeakGroup
    @Environment(LibraryStore.self) private var store

    private static let mapHeight: CGFloat = 470
    private static let sheetOverlap: CGFloat = 30

    var body: some View {
        ScrollView {
            VStack(spacing: 0) {
                // Relieve: se estira al tirar hacia abajo
                GeometryReader { geo in
                    let pull = max(0, geo.frame(in: .scrollView).minY)
                    Terrain3DView(center: group.peak.coordinate, distance: 2_400, summits: [group.peak], orbit: true, interactive: true)
                        .frame(height: Self.mapHeight + pull)
                        .offset(y: -pull)
                }
                .frame(height: Self.mapHeight)

                sheet
                    .padding(.top, -Self.sheetOverlap)
            }
        }
        .ignoresSafeArea(edges: .top)
        .background(Theme.Colors.surface)
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(.hidden, for: .navigationBar)
    }

    // MARK: Hoja

    private var sheet: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.l) {
            // Nombre y una altitud discreta
            VStack(alignment: .leading, spacing: Theme.Spacing.s) {
                Capsule().fill(Theme.Colors.separator).frame(width: 36, height: 4).frame(maxWidth: .infinity)
                HStack(alignment: .firstTextBaseline) {
                    Text(group.peak.displayName)
                        .font(.sarrio(28, .semibold))
                        .foregroundStyle(Theme.Colors.textPrimary)
                        .fixedSize(horizontal: false, vertical: true)
                    Spacer(minLength: Theme.Spacing.s)
                    if let ele = group.peak.ele {
                        Text("\(ele.groupedInteger) m")
                            .font(.sarrio(15, .bold).monospacedDigit())
                            .foregroundStyle(Theme.Colors.textSecondary)
                    }
                }
                if let line = subtitle {
                    Text(line).font(.sarrio(14)).foregroundStyle(Theme.Colors.textSecondary)
                }
            }
            .staggeredAppear(0)

            // Cifras sin caja: solo los números
            StatRow(stats: [
                ("Ascensiones", "\(group.ascents.count)", nil),
                ("Primera", group.ascents.last?.summitedAt.formatted(.dateTime.year()) ?? "–", nil),
                ("Última", group.ascents.first?.summitedAt.formatted(.dateTime.year()) ?? "–", nil),
            ])
            .staggeredAppear(1)

            VStack(alignment: .leading, spacing: 0) {
                Text("TUS ASCENSIONES")
                    .font(.statLabel).tracking(0.8)
                    .foregroundStyle(Theme.Colors.textSecondary)
                    .padding(.bottom, Theme.Spacing.s)
                ForEach(Array(group.ascents.enumerated()), id: \.element.id) { index, ascent in
                    ascentRow(ascent)
                    if index < group.ascents.count - 1 { Divider() }
                }
            }
            .staggeredAppear(2)
        }
        .padding(.horizontal, Theme.Spacing.l)
        .padding(.top, Theme.Spacing.s)
        .padding(.bottom, Theme.Spacing.xl)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            UnevenRoundedRectangle(topLeadingRadius: 28, topTrailingRadius: 28, style: .continuous)
                .fill(Theme.Colors.surface)
                .shadow(color: .black.opacity(0.12), radius: 18, y: -6)
        )
    }

    private var subtitle: String? {
        let parts = [group.peak.range, String(format: "%.4f°, %.4f°", group.peak.lat, group.peak.lon)]
        return parts.compactMap { $0 }.joined(separator: " · ")
    }

    @ViewBuilder private func ascentRow(_ ascent: Ascent) -> some View {
        let row = HStack(spacing: Theme.Spacing.m) {
            VStack(alignment: .leading, spacing: 2) {
                Text(ascent.summitedAt.formatted(date: .long, time: .omitted))
                    .font(.sarrio(16, .semibold)).foregroundStyle(Theme.Colors.textPrimary)
                Text(ascent.note ?? (ascent.activityId == nil ? "Añadida a mano" : "Desde una actividad"))
                    .font(.sarrio(13)).foregroundStyle(Theme.Colors.textSecondary)
            }
            Spacer()
            if ascent.activityId != nil {
                Image(systemName: "chevron.right").font(.system(size: 13, weight: .semibold)).foregroundStyle(Theme.Colors.textSecondary)
            }
        }
        .padding(.vertical, 12)
        .contentShape(Rectangle())

        if let activityId = ascent.activityId, let activity = store.activities.first(where: { $0.id == activityId }) {
            NavigationLink { ActivityDetailView(activity: activity) } label: { row }.buttonStyle(.pressableCard)
        } else {
            row
        }
    }
}
