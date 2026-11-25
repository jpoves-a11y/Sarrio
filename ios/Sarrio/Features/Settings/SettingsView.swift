import SwiftUI

struct SettingsView: View {
    var body: some View {
        ContentUnavailableView("Ajustes", systemImage: "gearshape", description: Text("Fuentes de datos (Apple Health, Polar, Garmin, Suunto, COROS), privacidad y zonas privadas."))
            .navigationTitle("Ajustes")
    }
}
