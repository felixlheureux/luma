import Foundation
import LumaCore

let arguments = Array(CommandLine.arguments.dropFirst())
do {
    guard arguments.count <= 1 else { throw NSError(domain: "Usage: luma-rules [catalog.yaml]", code: 1) }
    let catalog = try arguments.first.map { try RuleLoader.load(from: URL(fileURLWithPath: $0)) } ?? RuleLoader.bundled()
    print("Validated catalog \(catalog.version) (\(catalog.locale)): \(catalog.generated.count) generated rules, \(catalog.ownership.count) named ownership mappings.")
} catch {
    FileHandle.standardError.write(Data((error.localizedDescription + "\n").utf8))
    exit(1)
}
