import Foundation
import UniformTypeIdentifiers

struct BuiltInSoundDefinition: Identifiable, Hashable {
    var id: String { filename }
    var name: String
    var filename: String
}

enum SoundAssetError: LocalizedError {
    case unsupportedExtension
    case securityScopedAccessFailed
    case bundledSoundMissing(String)

    var errorDescription: String? {
        switch self {
        case .unsupportedExtension:
            "仅支持 caf、aif、aiff、wav 音频文件。为保证系统闹铃能响，请先把 mp3/m4a 转成 wav 或 caf。"
        case .securityScopedAccessFailed:
            "无法读取所选音频文件，请从“文件”App 中重新选择。"
        case .bundledSoundMissing(let filename):
            "缺少内置铃声文件：\(filename)"
        }
    }
}

final class SoundAssetManager {
    static let alarmKitDefaultIdentifier = SoundLibrary.alarmKitDefaultIdentifier
    static let defaultSoundIdentifier = SoundLibrary.defaultSoundIdentifier
    static let builtInSounds: [BuiltInSoundDefinition] = [
        BuiltInSoundDefinition(name: "晨光", filename: "cnalarm_soft_chime.wav"),
        BuiltInSoundDefinition(name: "清脆", filename: "cnalarm_bright_ping.wav"),
        BuiltInSoundDefinition(name: "短促", filename: "cnalarm_steady_beep.wav")
    ]

    let supportedTypes: [UTType] = [
        .wav,
        .aiff,
        UTType(filenameExtension: "caf") ?? .audio
    ]

    func importSound(from sourceURL: URL) throws -> SoundAsset {
        let allowedExtensions = ["caf", "aif", "aiff", "wav"]
        let ext = sourceURL.pathExtension.lowercased()
        guard allowedExtensions.contains(ext) else {
            throw SoundAssetError.unsupportedExtension
        }

        let didAccess = sourceURL.startAccessingSecurityScopedResource()
        defer {
            if didAccess {
                sourceURL.stopAccessingSecurityScopedResource()
            }
        }

        let directory = try soundsDirectory()
        let filename = "\(UUID().uuidString).\(ext)"
        let destination = directory.appendingPathComponent(filename)
        if FileManager.default.fileExists(atPath: destination.path) {
            try FileManager.default.removeItem(at: destination)
        }
        try FileManager.default.copyItem(at: sourceURL, to: destination)
        return SoundAsset(name: sourceURL.deletingPathExtension().lastPathComponent, kind: .imported, filename: filename)
    }

    func deleteImportedSound(_ sound: SoundAsset) throws {
        guard sound.kind == .imported else { return }
        let fileURL = try soundsDirectory().appendingPathComponent(sound.filename)
        if FileManager.default.fileExists(atPath: fileURL.path) {
            try FileManager.default.removeItem(at: fileURL)
        }
    }

    func installBundledSoundsIfNeeded() throws {
        let directory = try soundsDirectory()
        for sound in Self.builtInSounds {
            let destination = directory.appendingPathComponent(sound.filename)
            guard !FileManager.default.fileExists(atPath: destination.path) else { continue }
            guard let source = bundledSoundURL(filename: sound.filename) else {
                throw SoundAssetError.bundledSoundMissing(sound.filename)
            }
            try FileManager.default.copyItem(at: source, to: destination)
        }
    }

    func url(for identifier: String) -> URL? {
        guard identifier != Self.alarmKitDefaultIdentifier else { return nil }
        if let directory = try? soundsDirectory() {
            let libraryURL = directory.appendingPathComponent(identifier)
            if FileManager.default.fileExists(atPath: libraryURL.path) {
                return libraryURL
            }
        }
        return bundledSoundURL(filename: identifier)
    }

    func builtInSoundAssetDefinitions() -> [SoundAsset] {
        Self.builtInSounds.map { SoundAsset(name: $0.name, kind: .bundledSleep, filename: $0.filename) }
    }

    func soundsDirectory() throws -> URL {
        let library = try FileManager.default.url(
            for: .libraryDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )
        let directory = library.appendingPathComponent("Sounds", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }

    private func bundledSoundURL(filename: String) -> URL? {
        let url = URL(fileURLWithPath: filename)
        let name = url.deletingPathExtension().lastPathComponent
        let ext = url.pathExtension
        return Bundle.main.url(forResource: name, withExtension: ext)
            ?? Bundle.main.url(forResource: name, withExtension: ext, subdirectory: "Resources/Sounds")
            ?? Bundle.main.urls(forResourcesWithExtension: ext, subdirectory: nil)?.first { $0.lastPathComponent == filename }
            ?? Bundle.main.urls(forResourcesWithExtension: ext, subdirectory: "Resources/Sounds")?.first { $0.lastPathComponent == filename }
    }
}
