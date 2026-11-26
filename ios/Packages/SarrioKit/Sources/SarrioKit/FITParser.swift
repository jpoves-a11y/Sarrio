import Foundation

/// Lector mínimo de archivos FIT (Garmin, Coros, Suunto, Wahoo…).
///
/// Solo extrae lo que Sarrio necesita: los mensajes `record` (posición, altitud y hora) y el deporte
/// del mensaje `session`. Soporta cabeceras de 12 y 14 bytes, ambos órdenes de bytes, cabeceras de
/// hora comprimida, campos de desarrollador y archivos encadenados.
public enum FITParser {
    /// Segundos entre la época Unix y la de FIT (31-12-1989 00:00 UTC).
    static let fitEpochOffset: TimeInterval = 631_065_600
    /// Grados por semicírculo.
    static let semicircle = 180.0 / 2_147_483_648.0

    private enum Message {
        static let session: UInt16 = 18
        static let record: UInt16 = 20
    }

    private struct FieldDefinition { var number: UInt8; var size: Int }

    private struct Definition {
        var global: UInt16
        var bigEndian: Bool
        var fields: [FieldDefinition]
        var developerBytes: Int
    }

    public static func parse(data: Data) throws -> ParsedTrack {
        let bytes = [UInt8](data)
        var points: [TrackPoint] = []
        var sport: SportType?
        var offset = 0
        // Un archivo puede llevar varios FIT seguidos.
        while offset + 12 <= bytes.count {
            let end = try parseFile(bytes, at: offset, points: &points, sport: &sport)
            guard end > offset else { break }
            offset = end
        }
        guard !points.isEmpty else { throw TrackParseError.noPoints }
        return ParsedTrack(name: nil, points: points, sport: sport)
    }

    /// Lee un FIT empezando en `start` y devuelve dónde termina (incluido el CRC).
    private static func parseFile(_ b: [UInt8], at start: Int, points: inout [TrackPoint], sport: inout SportType?) throws -> Int {
        let headerSize = Int(b[start])
        guard headerSize == 12 || headerSize == 14, start + headerSize <= b.count else {
            throw TrackParseError.invalidFIT("cabecera")
        }
        guard b[start + 8] == 0x2E, b[start + 9] == 0x46, b[start + 10] == 0x49, b[start + 11] == 0x54 else {
            throw TrackParseError.invalidFIT("no es un archivo .FIT")
        }
        let dataSize = Int(readUInt(b, start + 4, 4, bigEndian: false))
        var i = start + headerSize
        let end = min(i + dataSize, b.count)

        var definitions: [UInt8: Definition] = [:]
        var lastTimestamp: UInt32 = 0

        while i < end {
            let header = b[i]; i += 1
            if header & 0x80 != 0 {
                // Cabecera de hora comprimida: mensaje de datos con desfase de 5 bits.
                let local = (header >> 5) & 0x03
                let delta = UInt32(header & 0x1F)
                var ts = (lastTimestamp & ~0x1F) + delta
                if delta < (lastTimestamp & 0x1F) { ts += 0x20 }
                lastTimestamp = ts
                guard let def = definitions[local] else { throw TrackParseError.invalidFIT("mensaje sin definición") }
                i = try readData(b, at: i, end: end, def: def, compressedTimestamp: ts,
                                 lastTimestamp: &lastTimestamp, points: &points, sport: &sport)
            } else if header & 0x40 != 0 {
                // Mensaje de definición.
                let local = header & 0x0F
                let hasDeveloperData = header & 0x20 != 0
                guard i + 5 <= end else { throw TrackParseError.invalidFIT("definición truncada") }
                let bigEndian = b[i + 1] == 1
                let global = UInt16(readUInt(b, i + 2, 2, bigEndian: bigEndian))
                let count = Int(b[i + 4])
                i += 5
                guard i + count * 3 <= end else { throw TrackParseError.invalidFIT("definición truncada") }
                var fields: [FieldDefinition] = []
                for f in 0..<count {
                    fields.append(FieldDefinition(number: b[i + f * 3], size: Int(b[i + f * 3 + 1])))
                }
                i += count * 3
                var developerBytes = 0
                if hasDeveloperData {
                    guard i < end else { throw TrackParseError.invalidFIT("definición truncada") }
                    let devCount = Int(b[i]); i += 1
                    guard i + devCount * 3 <= end else { throw TrackParseError.invalidFIT("definición truncada") }
                    for f in 0..<devCount { developerBytes += Int(b[i + f * 3 + 1]) }
                    i += devCount * 3
                }
                definitions[local] = Definition(global: global, bigEndian: bigEndian, fields: fields, developerBytes: developerBytes)
            } else {
                guard let def = definitions[header & 0x0F] else { throw TrackParseError.invalidFIT("mensaje sin definición") }
                i = try readData(b, at: i, end: end, def: def, compressedTimestamp: nil,
                                 lastTimestamp: &lastTimestamp, points: &points, sport: &sport)
            }
        }
        return end + 2 // CRC del archivo
    }

    private static func readData(_ b: [UInt8], at start: Int, end: Int, def: Definition, compressedTimestamp: UInt32?,
                                 lastTimestamp: inout UInt32, points: inout [TrackPoint], sport: inout SportType?) throws -> Int {
        let total = def.fields.reduce(0) { $0 + $1.size } + def.developerBytes
        guard start + total <= end else { throw TrackParseError.invalidFIT("mensaje truncado") }

        var values: [UInt8: (offset: Int, size: Int)] = [:]
        var i = start
        for field in def.fields {
            values[field.number] = (i, field.size)
            i += field.size
        }
        func uint(_ number: UInt8, size: Int) -> UInt64? {
            guard let v = values[number], v.size == size else { return nil }
            return readUInt(b, v.offset, size, bigEndian: def.bigEndian)
        }

        if let ts = uint(253, size: 4), ts != 0xFFFF_FFFF { lastTimestamp = UInt32(ts) }

        switch def.global {
        case Message.record:
            guard let rawLat = uint(0, size: 4), let rawLon = uint(1, size: 4),
                  rawLat != 0x7FFF_FFFF, rawLon != 0x7FFF_FFFF else { break }
            let lat = Double(Int32(bitPattern: UInt32(rawLat))) * semicircle
            let lon = Double(Int32(bitPattern: UInt32(rawLon))) * semicircle
            guard abs(lat) <= 90, abs(lon) <= 180 else { break }
            var elevation: Double?
            if let e = uint(78, size: 4), e != 0xFFFF_FFFF {
                elevation = Double(e) / 5 - 500
            } else if let e = uint(2, size: 2), e != 0xFFFF {
                elevation = Double(e) / 5 - 500
            }
            let ts = compressedTimestamp ?? (uint(253, size: 4).flatMap { $0 == 0xFFFF_FFFF ? nil : UInt32($0) })
            let time = ts.map { Date(timeIntervalSince1970: TimeInterval($0) + fitEpochOffset) }
            points.append(TrackPoint(latitude: lat, longitude: lon, elevation: elevation, time: time))
        case Message.session:
            if sport == nil, let s = uint(5, size: 1), s != 0xFF {
                let sub = uint(6, size: 1).flatMap { $0 == 0xFF ? nil : UInt8($0) }
                sport = SportType(fitSport: UInt8(s), subSport: sub)
            }
        default:
            break
        }
        return i + def.developerBytes
    }

    private static func readUInt(_ b: [UInt8], _ offset: Int, _ size: Int, bigEndian: Bool) -> UInt64 {
        var value: UInt64 = 0
        for k in 0..<size {
            let byte = UInt64(b[offset + (bigEndian ? k : size - 1 - k)])
            value = (value << 8) | byte
        }
        return value
    }
}
