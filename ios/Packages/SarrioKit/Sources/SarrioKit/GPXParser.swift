import Foundation
#if canImport(FoundationXML)
import FoundationXML
#endif

public struct ParsedTrack: Sendable {
    public var name: String?
    public var points: [TrackPoint]

    public var startDate: Date? { points.first(where: { $0.time != nil })?.time }

    public var distance: Double {
        zip(points, points.dropFirst()).reduce(0) { $0 + Geo.distance($1.0, $1.1) }
    }

    /// Desnivel positivo con umbral de histéresis para filtrar ruido del GPS/barómetro.
    public func elevationGain(threshold: Double = 3) -> Double {
        var gain = 0.0
        var reference: Double?
        for e in points.compactMap(\.elevation) {
            guard let ref = reference else { reference = e; continue }
            if e - ref >= threshold { gain += e - ref; reference = e } else if ref - e >= threshold { reference = e }
        }
        return gain
    }
}

public enum TrackParseError: Error, Equatable {
    case invalidXML(String)
    case noPoints
}

/// Lee GPX 1.0/1.1 (`trkpt` y, si no hay, `rtept`).
public final class GPXParser: NSObject, XMLParserDelegate {
    private var points: [TrackPoint] = []
    private var routePoints: [TrackPoint] = []
    private var current: TrackPoint?
    private var currentIsRoute = false
    private var text = ""
    private var name: String?
    private var inTrackOrMetadata = false

    nonisolated(unsafe) private static let isoFormatter: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter(); f.formatOptions = [.withInternetDateTime]; return f
    }()
    nonisolated(unsafe) private static let isoFractional: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter(); f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]; return f
    }()

    public static func parse(data: Data) throws -> ParsedTrack {
        let delegate = GPXParser()
        let parser = XMLParser(data: data)
        parser.delegate = delegate
        guard parser.parse() else {
            throw TrackParseError.invalidXML(parser.parserError?.localizedDescription ?? "unknown")
        }
        let pts = delegate.points.isEmpty ? delegate.routePoints : delegate.points
        guard !pts.isEmpty else { throw TrackParseError.noPoints }
        return ParsedTrack(name: delegate.name, points: pts)
    }

    public func parser(_ parser: XMLParser, didStartElement elementName: String, namespaceURI: String?,
                       qualifiedName qName: String?, attributes: [String: String] = [:]) {
        text = ""
        switch localName(elementName) {
        case "trkpt", "rtept":
            if let lat = attributes["lat"].flatMap(Double.init), let lon = attributes["lon"].flatMap(Double.init) {
                current = TrackPoint(latitude: lat, longitude: lon)
                currentIsRoute = localName(elementName) == "rtept"
            }
        case "trk", "metadata":
            inTrackOrMetadata = true
        default: break
        }
    }

    public func parser(_ parser: XMLParser, foundCharacters string: String) { text += string }

    public func parser(_ parser: XMLParser, didEndElement elementName: String, namespaceURI: String?, qualifiedName qName: String?) {
        let value = text.trimmingCharacters(in: .whitespacesAndNewlines)
        switch localName(elementName) {
        case "ele": current?.elevation = Double(value)
        case "time":
            current?.time = Self.isoFormatter.date(from: value) ?? Self.isoFractional.date(from: value)
        case "name":
            if current == nil, inTrackOrMetadata, name == nil, !value.isEmpty { name = value }
        case "trkpt", "rtept":
            if let p = current { currentIsRoute ? routePoints.append(p) : points.append(p) }
            current = nil
        default: break
        }
        text = ""
    }

    private func localName(_ name: String) -> String {
        name.split(separator: ":").last.map(String.init) ?? name
    }
}
