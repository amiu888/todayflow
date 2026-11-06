import AVKit
import SwiftUI
import TodayFlowDesign

/// One of the short videos bundled with the app. The files are copied into
/// TodayFlowFeatures resources so playback works without a network connection.
public enum TutorialVideo: String, CaseIterable, Identifiable, Sendable {
    case overview
    case useCases

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .overview: "Overview"
        case .useCases: "Use cases"
        }
    }

    public var subtitle: String {
        switch self {
        case .overview:
            "Tasks, trays, contacts, Jira, and local AI."
        case .useCases:
            "Create a task, drag an email or file, build a workflow, and watch it run."
        }
    }

    public var duration: String {
        switch self {
        case .overview: "0:30"
        case .useCases: "0:48"
        }
    }

    public var resourceName: String {
        switch self {
        case .overview: "todayflow-overview"
        case .useCases: "todayflow-use-cases"
        }
    }

    public var url: URL? {
        Bundle.module.url(forResource: resourceName, withExtension: "mp4")
    }
}

/// Plays the bundled walkthroughs in a native window. The sidebar switches
/// between the overview and the longer, real-screen use-case video.
public struct TutorialVideoView: View {
    @State private var player = AVPlayer()
    @State private var selected: TutorialVideo = .overview

    public init() {}

    public var body: some View {
        HStack(spacing: 0) {
            sidebar
            Divider()
            VStack(spacing: 0) {
                header
                Divider()
                if selected.url != nil {
                    PlayerSurface(player: player)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .background(.black)
                } else {
                    ContentUnavailableView(
                        "Video unavailable",
                        systemImage: "video.slash",
                        description: Text("Reinstall TodayFlow or read the guides on GitHub.")
                    )
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
        }
        .frame(minWidth: 720, minHeight: 480)
        .background(DesignTokens.Palette.background)
        .onAppear {
            if player.currentItem == nil {
                select(selected)
            }
        }
        .onDisappear {
            player.pause()
        }
    }

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Tutorial videos")
                .font(.caption.weight(.semibold))
                .foregroundStyle(DesignTokens.Palette.textSecondary)
                .padding(.horizontal, 2)

            ForEach(TutorialVideo.allCases) { video in
                Button {
                    select(video)
                } label: {
                    VStack(alignment: .leading, spacing: 4) {
                        HStack(spacing: 7) {
                            Image(systemName: selected == video ? "play.circle.fill" : "play.circle")
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundStyle(
                                    selected == video
                                        ? DesignTokens.Palette.accent
                                        : DesignTokens.Palette.textSecondary
                                )

                            Text(video.title)
                                .font(.callout.weight(.semibold))
                                .foregroundStyle(DesignTokens.Palette.textPrimary)

                            Spacer(minLength: 4)

                            Text(video.duration)
                                .font(.caption2.monospacedDigit())
                                .foregroundStyle(DesignTokens.Palette.textSecondary)
                        }

                        Text(video.subtitle)
                            .font(.caption2)
                            .foregroundStyle(DesignTokens.Palette.textSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .padding(9)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(
                        RoundedRectangle(cornerRadius: 9, style: .continuous)
                            .fill(
                                selected == video
                                    ? DesignTokens.Palette.accent.opacity(0.14)
                                    : Color.clear
                            )
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 9, style: .continuous)
                            .stroke(
                                selected == video
                                    ? DesignTokens.Palette.accent.opacity(0.55)
                                    : DesignTokens.Palette.hairline.opacity(0.6),
                                lineWidth: 1
                            )
                    )
                }
                .buttonStyle(.plain)
                .accessibilityLabel("\(video.title), \(video.duration)")
                .accessibilityValue(selected == video ? "Playing" : "Not selected")
            }

            Spacer(minLength: 8)

            Link("Read the guides on GitHub", destination: TutorialLinks.index)
                .font(.caption.weight(.semibold))

            Text("Both videos are bundled and play offline.")
                .font(.caption2)
                .foregroundStyle(DesignTokens.Palette.textSecondary)
        }
        .padding(14)
        .frame(width: 220)
        .background(DesignTokens.Palette.surface.opacity(0.55))
    }

    private var header: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                Text(selected.title)
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(DesignTokens.Palette.textPrimary)

                Text(selected.subtitle)
                    .font(.caption)
                    .foregroundStyle(DesignTokens.Palette.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 12)

            Text(selected.duration)
                .font(.caption.monospacedDigit())
                .foregroundStyle(DesignTokens.Palette.textSecondary)
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 12)
    }

    @MainActor
    private func select(_ video: TutorialVideo) {
        selected = video
        guard let url = video.url else { return }
        player.pause()
        player.replaceCurrentItem(with: AVPlayerItem(url: url))
        player.seek(to: .zero)
        player.play()
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
