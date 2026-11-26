import Foundation
#if canImport(FoundationXML)
import FoundationXML
#endif

/// Lee archivos TCX (Training Center XML): `Trackpoint` con posición, altitud y hora.
public final class TCXParser: NSObject, XMLParserDelegate {
    private var points: [TrackPoint] = []
    private var text = ""
    private var lat: Double?
    private var lon: Double?
    private var elevation: Double?
    private var time: Date?
    private var inTrackpoint = false
    private var sport: SportType?
    private var notes: String?

    nonisolated(unsafe) private static let isoFormatter: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter(); f.formatOptions = [.withInternetDateTime]; return f
    }()
    nonisolated(unsafe) private static let isoFractional: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter(); f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]; return f
    }()

    public static func parse(data: Data) throws -> ParsedTrack {
        let delegate = TCXParser()
        let parser = XMLParser(data: data)
        parser.delegate = delegate
        guard parser.parse() else {
            throw TrackParseError.invalidXML(parser.parserError?.localizedDescription ?? "unknown")
        }
        guard !delegate.points.isEmpty else { throw TrackParseError.noPoints }
        return ParsedTrack(name: delegate.notes, points: delegate.points, sport: delegate.sport)
    }

    public func parser(_ parser: XMLParser, didStartElement elementName: String, namespaceURI: String?,
                       qualifiedName qName: String?, attributes: [String: String] = [:]) {
        text = ""
        switch localName(elementName) {
        case "Trackpoint":
            inTrackpoint = true
            lat = nil; lon = nil; elevation = nil; time = nil
        case "Activity":
            if sport == nil, let s = attributes["Sport"] { sport = SportType(tcxSport: s) }
        default: break
        }
    }

    public func parser(_ parser: XMLParser, foundCharacters string: String) { text += string }

    public func parser(_ parser: XMLParser, didEndElement elementName: String, namespaceURI: String?, qualifiedName qName: String?) {
        let value = text.trimmingCharacters(in: .whitespacesAndNewlines)
        switch localName(elementName) {
        case "LatitudeDegrees" where inTrackpoint: lat = Double(value)
        case "LongitudeDegrees" where inTrackpoint: lon = Double(value)
        case "AltitudeMeters" where inTrackpoint: elevation = Double(value)
        case "Time" where inTrackpoint:
            time = Self.isoFormatter.date(from: value) ?? Self.isoFractional.date(from: value)
        case "Notes" where !inTrackpoint:
            if notes == nil, !value.isEmpty { notes = value }
        case "Trackpoint":
            // Los puntos sin posición (p. ej. pulsaciones en cinta) se ignoran.
            if let lat, let lon { points.append(TrackPoint(latitude: lat, longitude: lon, elevation: elevation, time: time)) }
            inTrackpoint = false
        default: break
        }
        text = ""
    }

    private func localName(_ name: String) -> String {
        name.split(separator: ":").last.map(String.init) ?? name
    }
}
