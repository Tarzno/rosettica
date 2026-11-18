import SwiftUI
import UniformTypeIdentifiers
import RosetticaCore

extension UTType {
    static let rosettePattern = UTType(exportedAs: "io.github.tarzno.rosettica.document")
}

struct RosetteDocument: FileDocument {
    var pattern: RosettePattern

    init(pattern: RosettePattern = RosettePattern()) {
        self.pattern = pattern
    }

    static var readableContentTypes: [UTType] { [.rosettePattern] }

    init(configuration: ReadConfiguration) throws {
        guard let data = configuration.file.regularFileContents else {
            throw CocoaError(.fileReadCorruptFile)
        }
        pattern = try JSONDecoder().decode(RosettePattern.self, from: data)
    }

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return FileWrapper(regularFileWithContents: try encoder.encode(pattern))
    }
}
