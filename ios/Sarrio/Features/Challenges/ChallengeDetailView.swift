import SwiftUI

/// Detalle de un reto: el progreso en grande, el periodo y, en los de lista, cada cima con su
/// estado y el globo con tus banderas y las que faltan en gris.
struct ChallengeDetailView: View {
    var challenge: Challenge
    @Environment(AchievementsStore.self) private var store
    @Environment(SessionStore.self) private var session
    @Environment(\.apiClient) private var api
    @Environment(\.dismiss) private var dismiss
    @State private var detail: ChallengeDetail?
    @State private var errorMessage: String?
    @State private var working = false
    @State private var showGlobe = false
    @State private var confirmDelete = false

    private var current: Challenge { detail?.challenge ?? challenge }
    private var isMine: Bool { current.creatorId != nil && current.creatorId == session.me?.id }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Theme.Spacing.l) {
                header
                progressBlock
                if current.kind == .peaks { peaksBlock }
                actions
            }
            .padding(Theme.Spacing.m)
        }
        .background(Theme.Colors.page)
        .navigationTitle("")
        .navigationBarTitleDisplayMode(.inline)
        .task { await load() }
        .refreshable { await load() }
        .fullScreenCover(isPresented: $showGlobe) {
            if let detail { ChallengeGlobeView(title: current.title, peaks: detail.peaks) }
        }
        .confirmationDialog("¿Borrar este reto?", isPresented: $confirmDelete, titleVisibility: .visible) {
            Button("Borrar reto", role: .destructive) {
                Task {
                    await store.delete(current)
                    dismiss()
                }
            }
        }
    }

    // MARK: Partes

    private var header: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.s) {
            if let badgeId = current.badgeId {
                // Leyenda: el medallón en grande, que se inclina al dedo
                HStack {
                    Spacer()
                    BadgeMedal(icon: "badge-\(badgeId)", earned: true, size: 170, shine: current.progress?.done == true)
                        .opacity(current.progress?.done == true ? 1 : 0.75)
                        .elevation(.high)
                        .interactiveTilt(maxAngle: 14)
                        .frame(width: 170, height: 170)
                    Spacer()
                }
                .padding(.vertical, Theme.Spacing.m)
            }
            Text((current.isLegend ? "Leyenda" : current.official ? "Reto de Sarrio" : "Reto de \(current.creator?.displayName ?? "un amigo")").uppercased())
                .font(.sarrio(12, .semibold))
                .tracking(1.4)
                .foregroundStyle(current.isLegend ? LegendColors.gold.opacity(0.9) : Theme.Colors.textSecondary)
            Text(current.title)
                .font(.screenTitle)
                .foregroundStyle(Theme.Colors.textPrimary)
                .fixedSize(horizontal: false, vertical: true)
            if let description = current.description {
                Text(description)
                    .font(.sarrio(16))
                    .foregroundStyle(Theme.Colors.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            HStack(spacing: Theme.Spacing.m) {
                Label(current.periodKind, systemImage: "calendar").labelStyle(DetailLabelStyle())
                if let n = current.participants, n > 0 {
                    Label(n == 1 ? "1 persona" : "\(n) personas", systemImage: "person.2").labelStyle(DetailLabelStyle())
                }
            }
            .padding(.top, 2)
        }
    }

    private var progressBlock: some View {
        let text = current.valueText
        let p = current.progress
        return VStack(alignment: .leading, spacing: Theme.Spacing.s) {
            SectionHeader(title: current.isJoined || current.isLegend ? "Tu progreso" : "Llevarías")
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text(text.value)
                    .font(.sarrio(56, .semibold).monospacedDigit())
                    .foregroundStyle(Theme.Colors.textPrimary)
                    .minimumScaleFactor(0.5)
                Text("/ \(text.target) \(text.unit)")
                    .font(.sarrio(17, .medium))
                    .foregroundStyle(Theme.Colors.textSecondary)
                    .minimumScaleFactor(0.7)
            }
            ProgressBar(fraction: p?.fraction ?? 0, height: 4)
            HStack {
                if p?.done == true {
                    Label("¡Conseguido!", systemImage: "checkmark")
                        .font(.sarrio(14, .semibold))
                        .foregroundStyle(Theme.Colors.accent)
                } else {
                    Text("\(Int(((p?.fraction ?? 0) * 100).rounded())) %")
                        .font(.sarrio(14, .semibold).monospacedDigit())
                        .foregroundStyle(Theme.Colors.textPrimary)
                }
                Spacer()
                if let period = current.periodText {
                    Text(period).font(.sarrio(14)).foregroundStyle(Theme.Colors.textSecondary)
                }
            }
        }
    }

    @ViewBuilder private var peaksBlock: some View {
        if let peaks = detail?.peaks, !peaks.isEmpty {
            VStack(alignment: .leading, spacing: Theme.Spacing.s) {
                HStack {
                    SectionHeader(title: "Cimas")
                    Button { showGlobe = true } label: {
                        Label("Ver en el globo", systemImage: "globe.europe.africa")
                            .font(.sarrio(14, .semibold))
                            .foregroundStyle(Theme.Colors.accent)
                    }
                    .fixedSize()
                }
                ForEach(peaks.sorted { ($0.done ? 0 : 1, -($0.ele ?? 0)) < ($1.done ? 0 : 1, -($1.ele ?? 0)) }) { peak in
                    HStack(spacing: Theme.Spacing.m) {
                        Image(systemName: peak.done ? "checkmark.square.fill" : "square")
                            .font(.system(size: 18, weight: .light))
                            .foregroundStyle(peak.done ? Theme.Colors.accent : Theme.Colors.textSecondary.opacity(0.6))
                        Text(peak.nameEs ?? peak.name)
                            .font(.sarrio(16, peak.done ? .semibold : .regular))
                            .foregroundStyle(peak.done ? Theme.Colors.textPrimary : Theme.Colors.textSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                        Spacer(minLength: Theme.Spacing.s)
                        if let ele = peak.ele {
                            Text("\(ele.groupedInteger) m")
                                .font(.sarrio(15, .medium).monospacedDigit())
                                .foregroundStyle(Theme.Colors.textSecondary)
                        }
                    }
                    .padding(.vertical, 10)
                    .overlay(alignment: .bottom) { Rectangle().fill(Theme.Colors.separator).frame(height: 0.5) }
                }
            }
        } else if detail == nil, errorMessage == nil {
            ProgressView().frame(maxWidth: .infinity)
        }
    }

    private var actions: some View {
        VStack(spacing: Theme.Spacing.s) {
            if let errorMessage {
                Text(errorMessage).font(.sarrio(14)).foregroundStyle(.red).fixedSize(horizontal: false, vertical: true)
            }
            if current.isLegend {
                Text("Las Leyendas cuentan solas: cuando la completes, el emblema aparecerá en tu perfil.")
                    .font(.sarrio(14))
                    .foregroundStyle(Theme.Colors.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            } else if current.isJoined {
                Button(isMine ? "Borrar reto" : "Salir del reto") {
                    if isMine { confirmDelete = true } else { Task { await setJoined(false) } }
                }
                .buttonStyle(.secondary)
            } else {
                Button {
                    Task { await setJoined(true) }
                } label: {
                    if working { ProgressView().tint(.white) } else { Text("Unirme al reto") }
                }
                .buttonStyle(.primary)
            }
        }
        .disabled(working)
        .padding(.top, Theme.Spacing.s)
    }

    // MARK: Datos

    private func load() async {
        do {
            detail = try await api.challenge(id: challenge.id)
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func setJoined(_ join: Bool) async {
        working = true
        defer { working = false }
        await store.setJoined(current, join)
        await load()
        UINotificationFeedbackGenerator().notificationOccurred(.success)
    }
}

private struct DetailLabelStyle: LabelStyle {
    func makeBody(configuration: Configuration) -> some View {
        HStack(spacing: 5) {
            configuration.icon.font(.system(size: 12, weight: .light)).foregroundStyle(Theme.Colors.accent)
            configuration.title.font(.sarrio(13)).foregroundStyle(Theme.Colors.textSecondary)
        }
    }
}

/// Globo de un reto de lista: tus banderas en las cimas hechas y banderas grises en las que faltan.
struct ChallengeGlobeView: View {
    var title: String
    var peaks: [ChallengePeak]
    @Environment(LibraryStore.self) private var library
    @Environment(\.dismiss) private var dismiss
    @State private var selected: GlobeSelection?

    private var doneGroups: [PeakGroup] {
        let done = Set(peaks.filter(\.done).map(\.id))
        return library.peakGroups.filter { done.contains($0.id) }
    }

    private var pending: [PeakRef] { peaks.filter { !$0.done }.map(\.ref) }

    var body: some View {
        ZStack(alignment: .top) {
            Globe3DMap(groups: doneGroups, pending: pending, selected: $selected, overviewToken: 0)
                .ignoresSafeArea()
            VStack(spacing: Theme.Spacing.s) {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(title)
                            .font(.sarrio(20, .semibold))
                            .foregroundStyle(.white)
                            .fixedSize(horizontal: false, vertical: true)
                        Text("\(peaks.filter(\.done).count) de \(peaks.count) cimas")
                            .font(.sarrio(13, .medium).monospacedDigit())
                            .foregroundStyle(.white.opacity(0.8))
                    }
                    .shadow(color: .black.opacity(0.55), radius: 3, y: 1)
                    Spacer()
                    Button { dismiss() } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(.white)
                            .frame(width: 40, height: 40)
                            .shadow(color: .black.opacity(0.5), radius: 3, y: 1)
                    }
                    .accessibilityLabel("Cerrar")
                }
                Spacer()
                if let selected {
                    PeakFlyCard(selection: selected) { withAnimation(Theme.Motion.spring) { self.selected = nil } }
                        .padding(.bottom, Theme.Spacing.s)
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                        .id(selected.id)
                }
            }
            .padding(.horizontal, Theme.Spacing.m)
            .padding(.top, Theme.Spacing.s)
            .animation(Theme.Motion.spring, value: selected?.id)
        }
    }
}
