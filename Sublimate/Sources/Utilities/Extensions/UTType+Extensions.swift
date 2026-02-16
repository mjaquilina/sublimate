import UniformTypeIdentifiers

extension UTType {
    static var database: UTType {
        UTType(filenameExtension: "db") ?? .data
    }
}
