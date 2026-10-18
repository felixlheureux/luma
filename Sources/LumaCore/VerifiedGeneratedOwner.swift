import Foundation

/// Supported default layout for one named product; no arbitrary app-name matching.
public struct GeneratedOwnerRequirement: Sendable {
    public let bundleName: String
    public let bundleID: String
    public let productName: String
    public let version: String
    public let commit: String
}

public enum VerifiedGeneratedOwner {
    @TaskLocal static var applicationRootsOverride: [URL]?

    static func validate(_ rule: CleanupRule, home: URL) throws {
        guard let required = rule.requiredApplication else { return }
        try NonMaterializingIO.perform {
            guard try Filesystem.attributes(home.appendingPathComponent(rule.relativePath))[.type] as? FileAttributeType == .typeDirectory else {
                throw LumaError.rejected("The supported cache location is not a directory. This layout was skipped.")
            }
            for root in applicationRootsOverride ?? [home.appendingPathComponent("Applications"), URL(fileURLWithPath: "/Applications")] {
                let bundle = root.appendingPathComponent(required.bundleName)
                do {
                    let metadata = try Filesystem.applicationMetadata(at: bundle)
                    guard metadata["CFBundleIdentifier"] as? String == required.bundleID,
                          metadata["CFBundleShortVersionString"] as? String == required.version else {
                        throw LumaError.rejected("This cache layout supports \(rule.appName ?? required.productName) \(required.version). The installed app does not match; this location was skipped.")
                    }
                    let resources = bundle.appendingPathComponent("Contents/Resources/app")
                    let product = try JSONSerialization.jsonObject(with: Filesystem.readMetadata(resources.appendingPathComponent("product.json"), limit: 1_048_576)) as? [String: Any]
                    let package = try JSONSerialization.jsonObject(with: Filesystem.readMetadata(resources.appendingPathComponent("package.json"), limit: 1_048_576)) as? [String: Any]
                    guard product?["darwinBundleIdentifier"] as? String == required.bundleID,
                          product?["nameShort"] as? String == required.productName,
                          product?["commit"] as? String == required.commit,
                          package?["version"] as? String == required.version else {
                        throw LumaError.rejected("The installed app's product metadata does not verify the supported \(required.version) layout. This location was skipped.")
                    }
                    return
                } catch {
                    // A missing installation is different from an unreadable,
                    // changed, linked or unsupported one. Neither grants access.
                    if GeneratedDataScanner.failureState(error) != .missing { throw error }
                }
            }
            throw LumaError.rejected("A supported installed app could not be verified. This location was skipped.")
        }
    }
}
