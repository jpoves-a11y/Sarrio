import Foundation

/// Los picos que viajan dentro de la app (`peaks.tsv`), para detectar cumbres al instante y sin
/// conexión. Lo genera `backend/scripts/export-peaks-bundle.mjs` desde la tabla de picos.
///
/// Formato (texto, UTF-8):
/// ```
/// #sarrio-peaks 1
/// #version 1784000000000
/// #cells sp84 sp86 …           celdas geohash de 4 caracteres que la copia cubre por completo
/// sp86w<TAB>1001<TAB>42.6311<TAB>0.6569<TAB>3404<TAB>Aneto<TAB>
/// ```
/// Columnas: geohash de 5, id OSM, lat, lon, altitud (vacía si no hay), nombre, nombre en español
/// y, opcional, cordillera.
public struct PeakBundle: Sendable {
    /// Versión del conjunto (ms), para comparar con `GET /v1/peaks/version`.
    public let version: Int64?
    /// Celdas que la copia cubre: en ellas no hace falta preguntar al servidor (aunque estén vacías).
    public let coveredCells: Set<String>
    private let byCell: [String: [Peak]]
    /// Todos los picos con su nombre normalizado (sin tildes ni mayúsculas), para buscar.
    private let searchable: [(peak: Peak, keys: [String])]

    public var count: Int { byCell.values.reduce(0) { $0 + $1.count } }

    public enum BundleError: Error, Equatable { case badHeader, badRow(Int) }

    public init(data: Data) throws {
        let text = String(decoding: data, as: UTF8.self)
        var version: Int64?
        var cells = Set<String>()
        var byCell: [String: [Peak]] = [:]
        var sawHeader = false
        var lineNumber = 0
        for line in text.split(separator: "\n", omittingEmptySubsequences: true) {
            lineNumber += 1
            if line.hasPrefix("#") {
                let parts = line.dropFirst().split(separator: " ")
                switch parts.first {
                case "sarrio-peaks": sawHeader = parts.dropFirst().first == "1"
                case "version": version = parts.dropFirst().first.flatMap { Int64($0) }
                case "cells": cells.formUnion(parts.dropFirst().map(String.init))
                default: break
                }
                continue
            }
            guard sawHeader else { throw BundleError.badHeader }
            let f = line.split(separator: "\t", omittingEmptySubsequences: false)
            guard f.count >= 6, f[0].count >= 4, let id = Int64(f[1]), let lat = Double(f[2]), let lon = Double(f[3]) else {
                throw BundleError.badRow(lineNumber)
            }
            let nameEs = f.count > 6 && !f[6].isEmpty ? String(f[6]) : nil
            let range = f.count > 7 && !f[7].isEmpty ? String(f[7]) : nil
            let peak = Peak(id: id, name: String(f[5]), nameEs: nameEs, ele: Double(f[4]), lat: lat, lon: lon, range: range)
            byCell[String(f[0].prefix(4)), default: []].append(peak)
        }
        guard sawHeader else { throw BundleError.badHeader }
        self.version = version
        self.coveredCells = cells
        self.byCell = byCell
        self.searchable = byCell.values.joined().map { peak in
            (peak, [peak.name, peak.nameEs].compactMap { $0.map(PeakBundle.normalize) })
        }
    }

    /// «Pìc d'Anéto» → «pic d'aneto»: sin tildes ni mayúsculas.
    public static func normalize(_ text: String) -> String {
        text.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: Locale(identifier: "es_ES"))
    }

    /// Picos cuyo nombre contiene `query` (sin tildes ni mayúsculas). Primero los que empiezan por
    /// ella, luego los que tienen una palabra que empieza por ella y luego el resto; dentro de cada
    /// grupo, los de `preferred` (p. ej. los ya subidos) y luego los más altos.
    public func search(_ query: String, limit: Int = 20, preferred: Set<Int64> = []) -> [Peak] {
        let q = Self.normalize(query.trimmingCharacters(in: .whitespacesAndNewlines))
        guard q.count >= 2 else { return [] }
        var hits: [(peak: Peak, rank: Int)] = []
        for entry in searchable {
            var best = Int.max
            for key in entry.keys {
                guard let r = key.range(of: q) else { continue }
                let rank: Int
                if r.lowerBound == key.startIndex {
                    rank = 0
                } else {
                    let before = key[key.index(before: r.lowerBound)]
                    rank = before == " " || before == "-" || before == "'" || before == "(" || before == "/" ? 1 : 2
                }
                best = min(best, rank)
            }
            if best != .max { hits.append((entry.peak, best)) }
        }
        hits.sort {
            if $0.rank != $1.rank { return $0.rank < $1.rank }
            let p0 = preferred.contains($0.peak.id), p1 = preferred.contains($1.peak.id)
            if p0 != p1 { return p0 }
            return ($0.peak.ele ?? 0) > ($1.peak.ele ?? 0)
        }
        return hits.prefix(limit).map(\.peak)
    }

    public func covers(_ cell: String) -> Bool { coveredCells.contains(cell) }

    /// Picos de una celda geohash de 4 caracteres (vacío si no hay o no está cubierta).
    public func peaks(in cell: String) -> [Peak] { byCell[cell] ?? [] }
}
