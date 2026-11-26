import Foundation
import Testing
@testable import SarrioKit

/// Genera un FIT pequeño en memoria (cabecera de 14 bytes, little endian salvo que se pida lo contrario).
private struct FITWriter {
    var body: [UInt8] = []
    var bigEndian = false

    private func bytes(_ value: UInt64, _ size: Int) -> [UInt8] {
        let le = (0..<size).map { UInt8((value >> (8 * UInt64($0))) & 0xFF) }
        return bigEndian ? le.reversed() : le
    }

    /// Definición: `fields` = [(número, tamaño, tipo base)].
    mutating func define(local: UInt8, global: UInt16, fields: [(UInt8, UInt8, UInt8)], developer: [(UInt8, UInt8, UInt8)] = []) {
        body.append(0x40 | (developer.isEmpty ? 0 : 0x20) | local)
        body += [0, bigEndian ? 1 : 0] + bytes(UInt64(global), 2) + [UInt8(fields.count)]
        for f in fields { body += [f.0, f.1, f.2] }
        if !developer.isEmpty {
            body.append(UInt8(developer.count))
            for f in developer { body += [f.0, f.1, f.2] }
        }
    }

    mutating func data(local: UInt8, _ values: [(UInt64, Int)]) {
        body.append(local)
        for v in values { body += bytes(v.0, v.1) }
    }

    mutating func compressed(local: UInt8, offset: UInt8, _ values: [(UInt64, Int)]) {
        body.append(0x80 | (local << 5) | (offset & 0x1F))
        for v in values { body += bytes(v.0, v.1) }
    }

    func file() -> Data {
        var header: [UInt8] = [14, 0x20, 0x08, 0x08]
        let size = UInt32(body.count)
        header += (0..<4).map { UInt8((size >> (8 * UInt32($0))) & 0xFF) }
        header += Array(".FIT".utf8) + [0, 0]
        return Data(header + body + [0, 0])
    }
}

private func semicircles(_ degrees: Double) -> UInt64 {
    UInt64(UInt32(bitPattern: Int32((degrees / FITParser.semicircle).rounded())))
}

private func fitTime(_ date: Date) -> UInt64 { UInt64(date.timeIntervalSince1970 - FITParser.fitEpochOffset) }

private let start = Date(timeIntervalSince1970: 1_784_000_000)

@Suite struct FITParserTests {
    private func sampleFIT(bigEndian: Bool = false) -> Data {
        var w = FITWriter(bigEndian: bigEndian)
        // record: timestamp, lat, lon, enhanced_altitude
        w.define(local: 0, global: 20, fields: [(253, 4, 0x86), (0, 4, 0x85), (1, 4, 0x85), (78, 4, 0x86)])
        w.data(local: 0, [(fitTime(start), 4), (semicircles(42.6476), 4), (semicircles(0.6626), 4), (UInt64((1900 + 500) * 5), 4)])
        w.data(local: 0, [(fitTime(start) + 3600, 4), (semicircles(42.6312), 4), (semicircles(0.657), 4), (UInt64((3398 + 500) * 5), 4)])
        // Punto sin GPS (inválido): se ignora.
        w.data(local: 0, [(fitTime(start) + 3700, 4), (0x7FFF_FFFF, 4), (0x7FFF_FFFF, 4), (0xFFFF_FFFF, 4)])
        // session: sport = 17 (hiking)
        w.define(local: 1, global: 18, fields: [(253, 4, 0x86), (5, 1, 0x00), (6, 1, 0x00)])
        w.data(local: 1, [(fitTime(start) + 3800, 4), (17, 1), (0, 1)])
        return w.file()
    }

    @Test func parsesRecordsAndSport() throws {
        let track = try FITParser.parse(data: sampleFIT())
        #expect(track.points.count == 2)
        #expect(abs(track.points[1].latitude - 42.6312) < 1e-6)
        #expect(abs(track.points[1].longitude - 0.657) < 1e-6)
        #expect(track.points[1].elevation == 3398)
        #expect(track.points[0].time == start)
        #expect(track.sport == .hiking)
    }

    @Test func parsesBigEndian() throws {
        let track = try FITParser.parse(data: sampleFIT(bigEndian: true))
        #expect(track.points.count == 2)
        #expect(track.points[0].elevation == 1900)
    }

    @Test func handlesCompressedTimestampsAndDeveloperFields() throws {
        var w = FITWriter()
        let t0 = fitTime(start)
        // Definición con altitud de 2 bytes y un campo de desarrollador de 2 bytes.
        w.define(local: 0, global: 20, fields: [(253, 4, 0x86), (0, 4, 0x85), (1, 4, 0x85), (2, 2, 0x84)], developer: [(0, 2, 0)])
        w.data(local: 0, [(t0, 4), (semicircles(42.0), 4), (semicircles(0.5), 4), (UInt64((1000 + 500) * 5), 2), (0xBEEF, 2)])
        w.define(local: 1, global: 20, fields: [(0, 4, 0x85), (1, 4, 0x85)])
        let next = UInt8((t0 + 10) & 0x1F)
        w.compressed(local: 1, offset: next, [(semicircles(42.001), 4), (semicircles(0.501), 4)])
        let track = try FITParser.parse(data: w.file())
        #expect(track.points.count == 2)
        #expect(track.points[0].elevation == 1000)
        #expect(track.points[1].time == start.addingTimeInterval(10))
    }

    @Test func rejectsGarbage() {
        #expect(throws: TrackParseError.self) { try FITParser.parse(data: Data(repeating: 7, count: 40)) }
    }

    @Test func isDetectedBySniffing() {
        #expect(TrackFileFormat(sniffing: sampleFIT()) == .fit)
    }
}

@Suite struct TCXParserTests {
    private let tcx = Data("""
    <?xml version="1.0" encoding="UTF-8"?>
    <TrainingCenterDatabase xmlns="http://www.garmin.com/xmlschemas/TrainingCenterDatabase/v2">
      <Activities>
        <Activity Sport="Running">
          <Id>2026-07-14T05:00:00Z</Id>
          <Lap StartTime="2026-07-14T05:00:00Z">
            <Track>
              <Trackpoint><Time>2026-07-14T05:00:00Z</Time>
                <Position><LatitudeDegrees>42.6476</LatitudeDegrees><LongitudeDegrees>0.6626</LongitudeDegrees></Position>
                <AltitudeMeters>1900</AltitudeMeters></Trackpoint>
              <Trackpoint><Time>2026-07-14T05:00:05Z</Time><HeartRateBpm><Value>120</Value></HeartRateBpm></Trackpoint>
              <Trackpoint><Time>2026-07-14T08:00:00.500Z</Time>
                <Position><LatitudeDegrees>42.6312</LatitudeDegrees><LongitudeDegrees>0.657</LongitudeDegrees></Position>
                <AltitudeMeters>3398</AltitudeMeters></Trackpoint>
            </Track>
          </Lap>
          <Notes>Aneto</Notes>
        </Activity>
      </Activities>
    </TrainingCenterDatabase>
    """.utf8)

    @Test func parsesTrackpointsWithPosition() throws {
        let track = try TCXParser.parse(data: tcx)
        #expect(track.points.count == 2)
        #expect(track.points[1].elevation == 3398)
        #expect(track.sport == .running)
        #expect(track.name == "Aneto")
        #expect(track.duration == 3 * 3600 + 0.5)
        #expect(TrackFileFormat(sniffing: tcx) == .tcx)
        #expect(try TrackFile.parse(data: tcx).points.count == 2)
    }
}

@Suite struct UploadTests {
    @Test func simplifyKeepsForcedPoints() {
        let line = (0..<50).map { TrackPoint(latitude: 42 + Double($0) * 0.0001, longitude: 0) }
        let simplified = Geo.simplify(line, tolerance: 5, keeping: [17, 33])
        #expect(simplified == [line[0], line[17], line[33], line[49]])
    }

    @Test func buildsPayloadKeepingTheSummitPoint() throws {
        // Ruta recta de 200 puntos que pasa por la cima en el punto 120.
        let points = (0..<200).map { i in
            TrackPoint(latitude: 42.6 + Double(i) * 0.0002, longitude: 0.657, elevation: 2000 + Double(i) * 5,
                       time: start.addingTimeInterval(Double(i) * 30))
        }
        let peak = Peak(id: 7, name: "Cima", ele: 2600, lat: points[120].latitude, lon: 0.657)
        let summits = PeakDetector().detect(track: points, candidates: [peak])
        #expect(summits.count == 1)

        let upload = ActivityUpload(track: ParsedTrack(name: "Test", points: points), summits: summits,
                                    source: .file, externalId: "file:x")
        #expect(upload.track.count < 10)
        #expect(upload.track.contains { $0[0] == points[120].latitude })
        #expect(upload.startAt == Int64(start.timeIntervalSince1970 * 1000))
        #expect(upload.track.last?[3] == Optional(Double(199 * 30)))
        #expect(upload.ascents == [.init(peakId: 7, summitedAt: Int64(points[120].time!.timeIntervalSince1970 * 1000))])
        #expect(upload.sportType == "hiking")
        #expect(upload.durationS == Double(199 * 30))

        let json = try JSONSerialization.jsonObject(with: JSONEncoder().encode(upload)) as? [String: Any]
        #expect(json?["source"] as? String == "file")
    }

    @Test func fingerprintIsStable() {
        let a = TrackFile.fingerprint(Data("hola".utf8))
        #expect(a == TrackFile.fingerprint(Data("hola".utf8)))
        #expect(a != TrackFile.fingerprint(Data("hola!".utf8)))
        #expect(a.hasSuffix("-4"))
    }
}

@Suite struct PeakBundleTests {
    private let sample = Data("""
    #sarrio-peaks 1
    #version 1784000000000
    #cells sp86 sp84 sp87
    sp84q\t2\t42.6747\t0.0347\t3355\tMonte Perdido\t
    sp86w\t1001\t42.6311\t0.6569\t3404\tAneto\t
    sp86x\t1002\t42.6467\t0.6378\t\tMaladeta\tMaladeta
    """.utf8)

    @Test func readsPeaksByCell() throws {
        let bundle = try PeakBundle(data: sample)
        #expect(bundle.version == 1_784_000_000_000)
        #expect(bundle.count == 3)
        #expect(bundle.peaks(in: "sp86").map(\.name) == ["Aneto", "Maladeta"])
        #expect(bundle.peaks(in: "sp86")[1].ele == nil)
        #expect(bundle.peaks(in: "sp86")[1].nameEs == "Maladeta")
        #expect(bundle.peaks(in: "sp84").first?.ele == 3355)
    }

    @Test func knowsWhichCellsItCovers() throws {
        let bundle = try PeakBundle(data: sample)
        #expect(bundle.covers("sp87"))           // cubierta aunque no tenga picos
        #expect(bundle.peaks(in: "sp87").isEmpty)
        #expect(!bundle.covers("eytd"))           // fuera: hay que preguntar al servidor
    }

    @Test func detectsSummitsWithBundledPeaks() throws {
        let bundle = try PeakBundle(data: sample)
        let track = (0..<20).map { i in
            TrackPoint(latitude: 42.62 + Double(i) * 0.0006, longitude: 0.6569, elevation: 3300 + Double(i) * 6)
        }
        let summits = PeakDetector().detect(track: track, candidates: bundle.peaks(in: "sp86"))
        #expect(summits.map(\.peak.name) == ["Aneto"])
    }

    @Test func rejectsMalformedFiles() {
        #expect(throws: PeakBundle.BundleError.badHeader) { try PeakBundle(data: Data("sp86w\t1\t1\t1\t\tX\t".utf8)) }
        #expect(throws: PeakBundle.BundleError.badRow(2)) { try PeakBundle(data: Data("#sarrio-peaks 1\nbroken".utf8)) }
    }
}

@Suite struct PeakSearchTests {
    private let bundle: PeakBundle = {
        let rows = [
            "u0hu5\t1\t45.8326\t6.8652\t4808\tMont Blanc / Monte Bianco\t\tAlpes",
            "u0hu6\t2\t45.8786\t6.8873\t4248\tMont Blanc du Tacul\t\tAlpes",
            "u0j2b\t3\t45.5873\t7.2660\t3683\tPunta Nera della Grivola\t\tAlpes",
            "u0hmq\t4\t45.5806\t7.4634\t3064\tPunta Nera\t\tAlpes",
            "sp86w\t5\t42.6311\t0.6569\t3404\tAneto\tAneto\tPirineos",
            "sp86x\t6\t42.6000\t0.6000\t2500\tTuca de l'Anèto\t\tPirineos",
        ]
        return try! PeakBundle(data: Data((["#sarrio-peaks 1", "#cells u0hu"] + rows).joined(separator: "\n").utf8))
    }()

    @Test func findsByPrefixIgnoringAccentsAndCase() {
        #expect(bundle.search("punta nera").map(\.id) == [3, 4])
        #expect(bundle.search("ANETO").map(\.id) == [5, 6])
        #expect(bundle.search("anèt").first?.name == "Aneto")
        #expect(bundle.search("bianco").first?.name == "Mont Blanc / Monte Bianco")
    }

    @Test func ranksPrefixThenWordThenContainsAndPrefersAscended() {
        // "blanc": ninguno empieza por ella, los dos la tienen como palabra → el más alto primero
        #expect(bundle.search("blanc").map(\.id) == [1, 2])
        #expect(bundle.search("blanc", preferred: [2]).map(\.id) == [2, 1])
        // "nera": palabra en ambas
        #expect(bundle.search("nera").map(\.id) == [3, 4])
        #expect(bundle.search("a").isEmpty) // demasiado corta
        #expect(bundle.search("punta", limit: 1).count == 1)
    }

    @Test func keepsTheRange() {
        #expect(bundle.search("aneto").first?.range == "Pirineos")
        #expect(bundle.peaks(in: "u0hu").first?.range == "Alpes")
    }
}
