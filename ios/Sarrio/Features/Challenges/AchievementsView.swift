import SwiftUI

extension View {
    /// Título solo cuando la vista no va dentro de otra que ya lo pone (Logros).
    @ViewBuilder func navigationTitle(ifNotEmbedded title: String?) -> some View {
        if let title { navigationTitle(title) } else { self }
    }
}

/// Pestaña Logros: Retos y Emblemas en un mismo sitio, con un selector editorial arriba
/// (dos etiquetas en versalitas y un filo de acento que se desliza bajo la activa).
struct AchievementsView: View {
    enum Section: String, CaseIterable, Identifiable {
        case challenges, badges
        var id: String { rawValue }
        var title: String { self == .challenges ? "Retos" : "Emblemas" }
    }

    @AppStorage("achievements.section") private var section: Section = .challenges
    @State private var creating = false
    @Namespace private var underline

    var body: some View {
        VStack(spacing: 0) {
            picker
            Group {
                switch section {
                case .challenges: ChallengesView(embedded: true)
                case .badges: BadgesView(embedded: true)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .background(Theme.Colors.page)
        .navigationTitle("Logros")
        .toolbar {
            if section == .challenges {
                Button { creating = true } label: {
                    Image(systemName: "plus").font(.system(size: 17, weight: .regular))
                }
                .accessibilityLabel("Crear reto")
            }
        }
        .sheet(isPresented: $creating) { NavigationStack { CreateChallengeView() } }
    }

    private var picker: some View {
        HStack(spacing: Theme.Spacing.l) {
            ForEach(Section.allCases) { item in
                Button {
                    withAnimation(Theme.Motion.snappy) { section = item }
                } label: {
                    VStack(spacing: 6) {
                        Text(item.title.uppercased())
                            .font(.sarrio(13, .semibold))
                            .tracking(1.4)
                            .foregroundStyle(section == item ? Theme.Colors.textPrimary : Theme.Colors.textSecondary)
                        ZStack {
                            Rectangle().fill(.clear).frame(height: 2)
                            if section == item {
                                Rectangle().fill(Theme.Colors.accent).frame(height: 2)
                                    .matchedGeometryEffect(id: "underline", in: underline)
                            }
                        }
                    }
                    .fixedSize()
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .sensoryFeedback(.selection, trigger: section)
            }
            Spacer()
        }
        .padding(.horizontal, Theme.Spacing.m)
        .padding(.top, Theme.Spacing.xs)
        .overlay(alignment: .bottom) { Rectangle().fill(Theme.Colors.separator).frame(height: 0.5) }
    }
}
