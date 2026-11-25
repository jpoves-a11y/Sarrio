import Foundation
import Testing
@testable import SarrioKit

private let aneto = Peak(id: 1, name: "Aneto", ele: 3404, lat: 42.6311, lon: 0.6569)
private let maladeta = Peak(id: 2, name: "Maladeta", ele: 3308, lat: 42.6467, lon: 0.6378)
private let farAway = Peak(id: 3, name: "Mulhacén", ele: 3479, lat: 37.0531, lon: -3.3114)

private func loadFixture(_ name: String) throws -> Data {
    let url = try #require(Bundle.module.url(forResource: name, withExtension: nil, subdirectory: "Fixtures"))
    return try Data(contentsOf: url)
}

@Suite struct GeoTests {
    @Test func geohashMatchesReference() {
        #expect(Geo.geohash(latitude: 57.64911, longitude: 10.40744, precision: 11) == "u4pruydqqvj")
        // Mismo valor que genera tools/peaks/fetch-peaks.mjs para el Aneto.
        #expect(Geo.geohash(latitude: 42.6311, longitude: 0.6569) == "sp86w")
    }

    @Test func distanceOfOneDegreeLatitude() {
        #expect(abs(Geo.distance(0, 0, 1, 0) - 111_195) < 100)
    }

    @Test func simplifyKeepsEndpointsOfStraightLine() {
        let line = (0..<50).map { TrackPoint(latitude: 42 + Double($0) * 0.0001, longitude: 0) }
        let simplified = Geo.simplify(line, tolerance: 5)
        #expect(simplified.count == 2)
        #expect(simplified.first == line.first && simplified.last == line.last)
    }

    @Test func geohashCellsCoverBox() throws {
        let box = try #require(BoundingBox(points: [TrackPoint(latitude: 42.62, longitude: 0.63),
                                                    TrackPoint(latitude: 42.65, longitude: 0.66)]))
        #expect(Geo.geohashCells(covering: box).contains("sp86"))
    }
}

@Suite struct GPXParserTests {
    @Test func parsesTrack() throws {
        let track = try GPXParser.parse(data: loadFixture("aneto.gpx"))
        #expect(track.name == "Aneto desde La Besurta")
        #expect(track.points.count == 6)
        #expect(track.points[3].elevation == 3398)
        #expect(track.startDate != nil)
        #expect(track.elevationGain() == 1498)
    }

    @Test func rejectsEmptyFile() {
        let empty = Data(#"<gpx version="1.1"></gpx>"#.utf8)
        #expect(throws: TrackParseError.noPoints) { try GPXParser.parse(data: empty) }
    }
}

@Suite struct PeakDetectorTests {
    @Test func detectsAnetoButNotNearbyPeaks() throws {
        let track = try GPXParser.parse(data: loadFixture("aneto.gpx"))
        let summits = PeakDetector().detect(track: track.points, candidates: [aneto, maladeta, farAway])
        #expect(summits.map(\.peak.name) == ["Aneto"])
        #expect(summits[0].distance < 40)
    }

    @Test func rejectsPassingBelowTheSummit() {
        // Mismo punto horizontal pero 300 m más bajo (p. ej. un túnel o una ladera muy empinada).
        let track = [TrackPoint(latitude: 42.6312, longitude: 0.6568, elevation: 3100)]
        #expect(PeakDetector().detect(track: track, candidates: [aneto]).isEmpty)
    }

    @Test func usesStricterRadiusWithoutElevation() {
        let close = [TrackPoint(latitude: 42.6312, longitude: 0.6569)]   // ~11 m
        let medium = [TrackPoint(latitude: 42.6314, longitude: 0.6569)]  // ~33 m
        #expect(PeakDetector().detect(track: close, candidates: [aneto]).count == 1)
        #expect(PeakDetector().detect(track: medium, candidates: [aneto]).isEmpty)
    }
}
