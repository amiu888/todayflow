import AVKit
import SwiftUI
import TodayFlowDesign

/// Plays the bundled walkthrough so the tutorial is one click away and works
/// without a network connection. The same MP4 is published under
/// `docs/tutorials/video/` for the GitHub guides.
public struct TutorialVideoView: View {
    @State private var player = AVPlayer()

    public init() {}

    /// The packaged video, or nil when the resource bundle is incomplete.
    public static var videoURL: URL? {
        Bundle.module.url(
            forResource: "todayflow-overview",
            withExtension: "mp4"
        )
    }

    public var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 3) {
                    Text("TodayFlow video walkthrough")
                        .font(.title3.weight(.semibold))
                    Text("Tasks, trays, projects, contacts, Jira drops, and local AI in 30 seconds.")
                        .font(.caption)
                        .foregroundStyle(DesignTokens.Palette.textSecondary)
                }
                Spacer(minLength: 12)
                Link("Read the guides", destination: TutorialLinks.index)
                    .font(.caption.weight(.semibold))
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 14)

            Divider()

            if Self.videoURL == nil {
                ContentUnavailableView(
                    "Video unavailable",
                    systemImage: "video.slash",
                    description: Text("Reinstall TodayFlow or read the guides on GitHub.")
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                PlayerSurface(player: player)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(.black)
            }
        }
        .frame(minWidth: 720, minHeight: 480)
        .background(DesignTokens.Palette.background)
        .onAppear {
            guard player.currentItem == nil, let url = Self.videoURL else { return }
            player.replaceCurrentItem(with: AVPlayerItem(url: url))
            player.play()
        }
        .onDisappear {
            player.pause()
        }
    }
}


/// AppKit's player instead of SwiftUI's `VideoPlayer`. On macOS 27 the
/// `_AVKit_SwiftUI` wrapper crashes while initializing its generic class
/// metadata; `AVPlayerView` is the stable AppKit surface and behaves the same.
private struct PlayerSurface: NSViewRepresentable {
    let player: AVPlayer

    func makeNSView(context: Context) -> AVPlayerView {
        let view = AVPlayerView()
        view.player = player
        view.controlsStyle = .inline
        view.showsFullScreenToggleButton = true
        view.allowsPictureInPicturePlayback = true
        return view
    }

    func updateNSView(_ view: AVPlayerView, context: Context) {
        if view.player !== player {
            view.player = player
        }
    }
}
