import SarrioKit
import SwiftUI

/// Crear un reto propio: de meta (desnivel, km, cimas, salidas… entre dos fechas) o de lista
/// de cimas elegidas con el buscador.
struct CreateChallengeView: View {
    @Environment(AchievementsStore.self) private var store
    @Environment(LibraryStore.self) private var library
    @Environment(\.peakPackStore) private var peakPackStore
    @Environment(\.dismiss) private var dismiss

    @State private var kind: ChallengeKind = .metric
    @State private var title = ""
    @State private var metric: ChallengeMetric = .elevationGain
    @State private var target = ""
    @State private var startsAt = Calendar.current.startOfDay(for: .now)
    @State private var endsAt = Calendar.current.date(byAdding: .month, value: 3, to: Calendar.current.startOfDay(for: .now))!
    @State private var visibility: Visibility = .friends
    @State private var peaks: [PeakRef] = []
    @State private var query = ""
    @State private var results: [Peak] = []
    @State private var saving = false
    @State private var errorMessage: String?

    private var targetValue: Double? {
        Double(target.replacingOccurrences(of: ".", with: "").replacingOccurrences(of: ",", with: "."))
    }

    private var canSave: Bool {
        guard title.trimmingCharacters(in: .whitespaces).count >= 2 else { return false }
        return kind == .metric ? (targetValue ?? 0) > 0 && endsAt > startsAt : !peaks.isEmpty
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Theme.Spacing.l) {
                Picker("Tipo", selection: $kind) {
                    Text("Meta").tag(ChallengeKind.metric)
                    Text("Lista de cimas").tag(ChallengeKind.peaks)
                }
                .pickerStyle(.segmented)

                field("Nombre") {
                    TextField("", text: $title, prompt: Text(kind == .metric ? "Mil metros al mes" : "Mis tresmiles"))
                        .font(.sarrio(20, .semibold))
                }

                if kind == .metric { metricFields } else { peakFields }

                field("Quién lo ve") {
                    Picker("Quién lo ve", selection: $visibility) {
                        Text("Solo yo").tag(Visibility.private)
                        Text("Amigos").tag(Visibility.friends)
                        Text("Todos").tag(Visibility.public)
                    }
                    .pickerStyle(.segmented)
                }

                if let errorMessage {
                    Text(errorMessage).font(.sarrio(14)).foregroundStyle(.red).fixedSize(horizontal: false, vertical: true)
                }
            }
            .padding(Theme.Spacing.m)
            .animation(Theme.Motion.spring, value: kind)
        }
        .background(Theme.Colors.page)
        .navigationTitle("Nuevo reto")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) { Button("Cancelar") { dismiss() } }
            ToolbarItem(placement: .confirmationAction) {
                if saving { ProgressView() } else { Button("Crear") { Task { await save() } }.disabled(!canSave) }
            }
        }
        .task(id: query) { await search() }
    }

    // MARK: Meta

    private var metricFields: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.l) {
            field("Qué cuenta") {
                Menu {
                    ForEach(ChallengeMetric.creatable) { m in
                        Button(m.title) { metric = m }
                    }
                } label: {
                    HStack {
                        Text(metric.title).font(.sarrio(17, .medium)).foregroundStyle(Theme.Colors.textPrimary)
                        Spacer()
                        Image(systemName: "chevron.up.chevron.down").font(.system(size: 13)).foregroundStyle(Theme.Colors.textSecondary)
                    }
                }
            }
            field("Meta") {
                HStack(alignment: .firstTextBaseline) {
                    TextField("", text: $target, prompt: Text(placeholder))
                        .keyboardType(.numberPad)
                        .font(.sarrio(34, .semibold).monospacedDigit())
                    Text(metric.unit).font(.sarrio(17, .medium)).foregroundStyle(Theme.Colors.textSecondary)
                }
            }
            field("Fechas") {
                DatePicker("Empieza", selection: $startsAt, displayedComponents: .date).font(.sarrio(16))
                DatePicker("Termina", selection: $endsAt, in: startsAt..., displayedComponents: .date).font(.sarrio(16))
            }
        }
    }

    private var placeholder: String {
        switch metric {
        case .elevationGain: "10000"
        case .distance: "200"
        case .activeWeeks: "12"
        default: "20"
        }
    }

    // MARK: Lista de cimas

    private var peakFields: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.m) {
            field("Añadir cimas") {
                HStack(spacing: Theme.Spacing.s) {
                    Image(systemName: "magnifyingglass").font(.system(size: 15)).foregroundStyle(Theme.Colors.textSecondary)
                    TextField("", text: $query, prompt: Text("Buscar un pico"))
                        .autocorrectionDisabled()
                        .font(.sarrio(16, .medium))
                }
            }
            ForEach(results.filter { r in !peaks.contains { $0.id == r.id } }) { peak in
                Button {
                    withAnimation(Theme.Motion.snappy) { peaks.append(PeakRef(peak)) }
                    query = ""
                    results = []
                } label: {
                    peakRow(PeakRef(peak), icon: "plus", tint: Theme.Colors.accent)
                }
                .buttonStyle(.plain)
            }
            if !peaks.isEmpty {
                SectionHeader(title: peaks.count == 1 ? "1 cima" : "\(peaks.count) cimas")
                    .padding(.top, Theme.Spacing.s)
                ForEach(peaks, id: \.id) { peak in
                    Button {
                        withAnimation(Theme.Motion.snappy) { peaks.removeAll { $0.id == peak.id } }
                    } label: {
                        peakRow(peak, icon: "minus", tint: Theme.Colors.textSecondary)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private func peakRow(_ peak: PeakRef, icon: String, tint: Color) -> some View {
        HStack(spacing: Theme.Spacing.m) {
            Image(systemName: icon).font(.system(size: 13, weight: .regular)).foregroundStyle(tint).frame(width: 24)
            VStack(alignment: .leading, spacing: 1) {
                Text(peak.displayName).font(.sarrio(16, .semibold)).foregroundStyle(Theme.Colors.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)
                if let range = peak.range { Text(range).font(.sarrio(12)).foregroundStyle(Theme.Colors.textSecondary) }
            }
            Spacer(minLength: Theme.Spacing.s)
            if let ele = peak.ele {
                Text("\(ele.groupedInteger) m").font(.sarrio(15, .medium).monospacedDigit()).foregroundStyle(Theme.Colors.textSecondary)
            }
        }
        .padding(.vertical, 8)
        .contentShape(Rectangle())
        .overlay(alignment: .bottom) { Rectangle().fill(Theme.Colors.separator).frame(height: 0.5) }
    }

    // MARK: Partes y acciones

    private func field(_ label: String, @ViewBuilder content: () -> some View) -> some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.s) {
            Text(label.uppercased())
                .font(.sarrio(12, .semibold))
                .tracking(1.4)
                .foregroundStyle(Theme.Colors.textSecondary)
            content()
            Rectangle().fill(Theme.Colors.separator).frame(height: 0.5)
        }
    }

    private func search() async {
        let q = query
        guard q.trimmingCharacters(in: .whitespaces).count >= 2 else { results = []; return }
        try? await Task.sleep(for: .milliseconds(180))
        guard !Task.isCancelled else { return }
        let found = await peakPackStore.search(q, preferred: Set(library.peakGroups.map(\.id)), limit: 8)
        guard !Task.isCancelled else { return }
        results = found
    }

    private func save() async {
        saving = true
        defer { saving = false }
        let trimmed = title.trimmingCharacters(in: .whitespaces)
        let ms = { (d: Date) in Int64(d.timeIntervalSince1970 * 1000) }
        var body = NewChallenge(kind: kind, title: trimmed, visibility: visibility)
        if kind == .metric {
            body.metric = metric
            // La distancia se guarda en metros
            body.target = metric == .distance ? (targetValue ?? 0) * 1000 : targetValue
            body.startsAt = ms(startsAt)
            // Hasta el final del día elegido
            body.endsAt = ms(Calendar.current.date(byAdding: .day, value: 1, to: Calendar.current.startOfDay(for: endsAt))!)
        } else {
            body.peakIds = peaks.map(\.id)
        }
        do {
            _ = try await store.create(body)
            UINotificationFeedbackGenerator().notificationOccurred(.success)
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
