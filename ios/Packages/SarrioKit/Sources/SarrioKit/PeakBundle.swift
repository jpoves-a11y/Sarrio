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
/// Columnas: geohash de 5, id OSM, lat, lon, altitud (vacía si no hay), nombre, nombre en español.
public struct PeakBundle: Sendable {
    /// Versión del conjunto (ms), para comparar con `GET /v1/peaks/version`.
    public let version: Int64?
    /// Celdas que la copia cubre: en ellas no hace falta preguntar al servidor (aunque estén vacías).
    public let coveredCells: Set<String>
    private let byCell: [String: [Peak]]

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
            let peak = Peak(id: id, name: String(f[5]), nameEs: nameEs, ele: Double(f[4]), lat: lat, lon: lon)
            byCell[String(f[0].prefix(4)), default: []].append(peak)
        }
        guard sawHeader else { throw BundleError.badHeader }
        self.version = version
        self.coveredCells = cells
        self.byCell = byCell
    }

    public func covers(_ cell: String) -> Bool { coveredCells.contains(cell) }

    /// Picos de una celda geohash de 4 caracteres (vacío si no hay o no está cubierta).
    public func peaks(in cell: String) -> [Peak] { byCell[cell] ?? [] }
}
