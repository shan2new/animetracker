import SwiftUI
import CoreTransferable
import UniformTypeIdentifiers

/// The user's library as a file (board 15: export is always free). Titles, statuses and progress
/// only — never account identifiers. The bytes are produced on the main actor when the export is
/// created, so the transfer itself is plain data.
struct LibraryExport: Transferable {
    enum Format { case json, csv }
    let format: Format
    let json: Data
    let csv: Data

    @MainActor
    init(appModel: AppModel, format: Format) {
        self.format = format
        self.json = LibraryExport.makeJSON(appModel.library)
        self.csv = LibraryExport.makeCSV(appModel.library)
    }

    static var transferRepresentation: some TransferRepresentation {
        FileRepresentation(exportedContentType: .json) { export in
            try export.write(ext: "json", data: export.json)
        }
        .exportingCondition { $0.format == .json }
        FileRepresentation(exportedContentType: .commaSeparatedText) { export in
            try export.write(ext: "csv", data: export.csv)
        }
        .exportingCondition { $0.format == .csv }
    }

    private func write(ext: String, data: Data) throws -> SentTransferredFile {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("previously-library.\(ext)")
        try data.write(to: url, options: .atomic)
        return SentTransferredFile(url)
    }

    private static func makeJSON(_ library: [Franchise]) -> Data {
        struct Part: Encodable { let mediaId: Int; let label: String; let kind: String; let progress: Int; let totalEpisodes: Int }
        struct Row: Encodable { let id: String; let title: String; let source: String; let status: String; let parts: [Part] }
        let rows = library.map { f in
            Row(id: f.id, title: f.title, source: f.source.rawValue, status: f.effectiveStatus.rawValue,
                parts: f.parts.map { Part(mediaId: $0.mediaId, label: $0.canonicalLabel, kind: $0.kind.rawValue, progress: $0.progress, totalEpisodes: $0.totalEpisodes) })
        }
        let encoder = JSONEncoder(); encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return (try? encoder.encode(rows)) ?? Data()
    }

    private static func makeCSV(_ library: [Franchise]) -> Data {
        func q(_ s: String) -> String { "\"" + s.replacingOccurrences(of: "\"", with: "\"\"") + "\"" }
        var lines = ["title,source,status,part,kind,progress,total_episodes"]
        for f in library {
            for p in f.parts {
                lines.append([q(f.title), f.source.rawValue, f.effectiveStatus.rawValue, q(p.canonicalLabel), p.kind.rawValue, String(p.progress), String(p.totalEpisodes)].joined(separator: ","))
            }
        }
        return Data(lines.joined(separator: "\n").utf8)
    }
}
