import Foundation

/// Pico de OpenStreetMap tal como lo sirve `GET /v1/peaks/pack/:cell`.
public struct Peak: Sendable, Hashable, Codable, Identifiable {
    public var id: Int64
    public var name: String
    public var nameEs: String?
    /// Altitud oficial (tag `ele` de OSM), si existe.
    public var ele: Double?
    public var lat: Double
    public var lon: Double

    public init(id: Int64, name: String, nameEs: String? = nil, ele: Double?, lat: Double, lon: Double) {
        self.id = id; self.name = name; self.nameEs = nameEs; self.ele = ele; self.lat = lat; self.lon = lon
    }

    public var displayName: String { nameEs ?? name }
}

public struct PeakPack: Sendable, Codable {
    public var cell: String
    public var attribution: String
    public var peaks: [Peak]
}
