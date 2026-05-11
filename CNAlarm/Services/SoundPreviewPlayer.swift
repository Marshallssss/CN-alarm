import AVFoundation
import Combine
import Foundation

@MainActor
final class SoundPreviewPlayer: ObservableObject {
    @Published var status: String?

    private var player: AVAudioPlayer?
    private let manager = SoundAssetManager()

    func preview(identifier: String) {
        if identifier == SoundLibrary.alarmKitDefaultIdentifier {
            status = "AlarmKit 系统默认声只有一个 default，由系统闹铃触发时播放，App 内不能直接预览。"
            return
        }
        guard let url = manager.url(for: identifier) else {
            status = "找不到这个铃声文件，请重新选择或导入。"
            return
        }
        do {
            try AVAudioSession.sharedInstance().setCategory(.playback, mode: .default)
            try AVAudioSession.sharedInstance().setActive(true)
            player = try AVAudioPlayer(contentsOf: url)
            player?.prepareToPlay()
            player?.play()
            status = "正在试听：\(displayName(for: identifier))"
        } catch {
            status = "试听失败：\(error.localizedDescription)"
        }
    }

    private func displayName(for identifier: String) -> String {
        SoundAssetManager.builtInSounds.first { $0.filename == identifier }?.name
            ?? URL(fileURLWithPath: identifier).deletingPathExtension().lastPathComponent
    }
}
