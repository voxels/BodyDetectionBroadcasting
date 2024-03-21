//
//  PlayerModel.swift

import AVKit
import GroupActivities
import Combine
import Observation

/// The presentation modes the player supports.
enum Presentation {
    /// Indicates to present the player as a child of a parent user interface.
    case inline
    /// Indicates to present the player in full-window exclusive mode.
    case fullWindow
}

@Observable class PlayerModel : NSObject {
    public var isFullScreen = true {
        didSet {
            if isFullScreen {
                player.play()
            } else {
                player.pause()
            }
        }
    }
    /// A Boolean value that indicates whether playback is currently active.
    private(set) var isPlaying = false
    
    /// A Boolean value that indicates whether playback of the current item is complete.
    private(set) var isPlaybackComplete = false
    
    /// The presentation in which to display the current media.
    private(set) var presentation: Presentation = .inline
    
    /// The currently loaded video.
    private(set) var currentItem: URL? = nil
    
    /// A Boolean value that indicates whether the player should propose playing the next video in the Up Next list.
    private(set) var shouldProposeNextVideo = false
    
    /// An object that manages the playback of a video's media.
    public var player = AVPlayer()
    private var audioPlayer = AVPlayer()
    
    /// The currently presented player view controller.
    ///
    /// The life cycle of an `AVPlayerViewController` object is different than a typical view controller. In addition
    /// to displaying the player UI within your app, the view controller also manages the presentation of the media
    /// outside your app UI such as when using AirPlay, Picture in Picture, or docked full window. To ensure the view
    /// controller instance is preserved in these cases, the app stores a reference to it here (which
    /// is an environment-scoped object).
    ///
    /// This value is set by a call to the `makePlayerViewController()` method.
    public var playerViewController: AVPlayerViewController? = nil
    private var playerViewControllerDelegate: AVPlayerViewControllerDelegate? = nil
    
    private(set) var shouldAutoPlay = true
    
//    // An object that manages the app's SharePlay implementation.
//    private var coordinator: VideoWatchingCoordinator! = nil
    
    /// A token for periodic observation of the player's time.
    private var timeObserver: Any? = nil
    private var subscriptions = Set<AnyCancellable>()
    
    override init() {
        super.init()
//        coordinator = VideoWatchingCoordinator(playbackCoordinator: player.playbackCoordinator)
        observePlayback()
        Task {
            await configureAudioSession()
            //await observeSharedVideo()
        }
    }
    
    /// Creates a new player view controller object.
    /// - Returns: a configured player view controller.
    func makePlayerViewController() -> AVPlayerViewController {
        let delegate = PlayerViewControllerDelegate(player: self)
        let controller = AVPlayerViewController()
        controller.player = player
        controller.delegate = delegate

        // Set the model state
        playerViewController = controller
        playerViewControllerDelegate = delegate
        
        return controller
    }
    
    private func observePlayback() {
        // Return early if the model calls this more than once.
        guard subscriptions.isEmpty else { return }
        
        // Observe the time control status to determine whether playback is active.
        player.publisher(for: \.timeControlStatus)
            .receive(on: DispatchQueue.main)
            .removeDuplicates()
            .sink { [weak self] status in
                self?.isPlaying = status == .playing
            }
            .store(in: &subscriptions)
        
        // Observe this notification to know when a video plays to its end.
        NotificationCenter.default
            .publisher(for: .AVPlayerItemDidPlayToEndTime)
            .receive(on: DispatchQueue.main)
            .map { _ in true }
            .sink { [weak self] isPlaybackComplete in
                self?.isPlaybackComplete = isPlaybackComplete
            }
            .store(in: &subscriptions)
        
        // Observe audio session interruptions.
        NotificationCenter.default
            .publisher(for: AVAudioSession.interruptionNotification)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] notification in
                
                // Wrap the notification in helper type that extracts the interruption type and options.
//                guard let result = InterruptionResult(notification) else { return }
                
//                // Resume playback, if appropriate.
//                if result.type == .ended && result.options == .shouldResume {
                    self?.player.play()
//                }
            }.store(in: &subscriptions)
        
        // Add an observer of the player object's current time. The app observes
        // the player's current time to determine when to propose playing the next
        // video in the Up Next list.
        addTimeObserver()
    }
    
    /// Configures the audio session for video playback.
    private func configureAudioSession() async {
        let session = AVAudioSession.sharedInstance()
        do {
            // Configure the audio session for playback. Set the `moviePlayback` mode
            // to reduce the audio's dynamic range to help normalize audio levels.
            try session.setCategory(.playback, mode: .moviePlayback)
        } catch {
            print("Unable to configure audio session: \(error.localizedDescription)")
        }
    }

    /// Monitors the coordinator's `sharedVideo` property.
    ///
    /// If this value changes due to a remote participant sharing a new activity, load and present the new video.
    /*
    private func observeSharedVideo() async {
        let current = currentItem
        await coordinator.$sharedVideo
            .receive(on: DispatchQueue.main)
            // Only observe non-nil values.
            .compactMap { $0 }
            // Only observe updates set by a remote participant.
            .filter { $0 != current }
            .sink { [weak self] video in
                guard let self else { return }
                // Load the video for full-window presentation.
                loadVideo(video, presentation: .fullWindow)
            }
            .store(in: &subscriptions)
    }
     
     */
    
    /// Loads a video for playback in the requested presentation.
    /// - Parameters:
    ///   - video: The video to load for playback.
    ///   - presentation: The style in which to present the player.
    ///   - autoplay: A Boolean value that indicates whether to auto play that the content when presented.
    func loadVideo(_ video: URL, presentation: Presentation = .fullWindow, autoplay: Bool = true) async throws {
        // Update the model state for the request.
        currentItem = video
        shouldAutoPlay = autoplay
        isPlaybackComplete = false
        
        switch presentation {
        case .fullWindow:
            Task { @MainActor in
                // Attempt to SharePlay this video if a FaceTime call is active.
                //await coordinator.coordinatePlayback(of: video)
                // After preparing for coordination, load the video into the player and present it.
                try await replaceCurrentItem(with: video)
            }
        case .inline:
            // Don't SharePlay the video the when playing it from the inline player,
            // load the video into the player and present it.
            try await replaceCurrentItem(with: video)
        }

        // In visionOS, configure the spatial experience for either .inline or .fullWindow playback.
        configureAudioExperience(for: presentation)

        // Set the presentation, which typically presents the player full window.
        self.presentation = presentation
        
        if autoplay {
            Task { @MainActor in
                play()
            }
        }
   }
    
    private func replaceCurrentItem(with video: URL) async throws {
        // Create a new player item and set it as the player's current item.
        print("replacing current video with :\(video)")
        let playerItem = AVPlayerItem(url: video)
//        // Set external metadata on the player item for the current video.
//        let metadata = try await createMetadataItems(for: playerItem.asset)
//        playerItem.externalMetadata = metadata
        // Set the new player item as current, and begin loading its data.
        await MainActor.run {
            player.replaceCurrentItem(with: playerItem)
        }
        print("🍿 \(video.absoluteString) enqueued for playback.")
    }
    
    func stop() {
        player.pause()
        reset()
    }
    
    /// Clears any loaded media and resets the player model to its default state.
    func reset() {
        currentItem = nil
        player.replaceCurrentItem(with: nil)
        playerViewControllerDelegate = nil
        playerViewController = nil
        isFullScreen = false
    }
    
    /// Creates metadata items from the video items data.
    /// - Parameter video: the video to create metadata for.
    /// - Returns: An array of `AVMetadataItem` to set on a player item.
    
    private func createMetadataItems(for video: AVAsset) async throws -> [AVMetadataItem] {
        return try await video.load(.metadata)
    }
    /// Creates a metadata item for a the specified identifier and value.
    /// - Parameters:
    ///   - identifier: an identifier for the item.
    ///   - value: a value to associate with the item.
    /// - Returns: a new `AVMetadataItem` object.
    private func createMetadataItem(for identifier: AVMetadataIdentifier,
                                    value: Any) -> AVMetadataItem {
        let item = AVMutableMetadataItem()
        item.identifier = identifier
        item.value = value as? NSCopying & NSObjectProtocol
        // Specify "und" to indicate an undefined language.
        item.extendedLanguageTag = "und"
        return item.copy() as! AVMetadataItem
    }
    
    /// Configures the user's intended spatial audio experience to best fit the presentation.
    /// - Parameter presentation: the requested player presentation.
    private func configureAudioExperience(for presentation: Presentation) {
        #if os(visionOS)
        do {
            let experience: AVAudioSessionSpatialExperience
            switch presentation {
            case .inline:
                // Set a small, focused sound stage when watching trailers.
                experience = .headTracked(soundStageSize: .small, anchoringStrategy: .automatic)
            case .fullWindow:
                // Set a large sound stage size when viewing full window.
                experience = .headTracked(soundStageSize: .large, anchoringStrategy: .automatic)
            }
            try AVAudioSession.sharedInstance().setIntendedSpatialExperience(experience)
        } catch {
            print("Unable to set the intended spatial experience. \(error.localizedDescription)")
        }
        #endif
    }

    // MARK: - Transport Control
    
    
    func play() {
        player.play()
    }
    
    func pause() {
        player.pause()
    }
    
    func togglePlayback() {
        player.timeControlStatus == .paused ? play() : pause()
    }
    
    public func loadAudio(urlString:String) {
        if let url = URL(string: urlString) {
            do {
                try AVAudioSession.sharedInstance().setCategory(.playback, mode: .moviePlayback)
            } catch {
                print("Error setting audio session category and mode: \(error)")
            }
            audioPlayer = AVPlayer(url: url)
            audioPlayer.play()
        }
    }
    
    // MARK: - Time Observation
    private func addTimeObserver() {
        removeTimeObserver()
        // Observe the player's timing every 1 second
        let _ = CMTime(value: 1, timescale: 1)
//        timeObserver = player.addPeriodicTimeObserver(forInterval: timeInterval, queue: .main) { [weak self] time in
//        }
    }
    
    private func removeTimeObserver() {
        guard let timeObserver = timeObserver else { return }
        player.removeTimeObserver(timeObserver)
        self.timeObserver = nil
    }
    
    /// A coordinator that acts as the player view controller's delegate object.
    final class PlayerViewControllerDelegate: NSObject, AVPlayerViewControllerDelegate {
        
        let player: PlayerModel
        
        init(player: PlayerModel) {
            self.player = player
        }
        
        #if os(visionOS)
        // The app adopts this method to reset the state of the player model when a user
        // taps the back button in the visionOS player UI.
        func playerViewController(_ playerViewController: AVPlayerViewController,
                                  willEndFullScreenPresentationWithAnimationCoordinator coordinator: UIViewControllerTransitionCoordinator) {
            Task { @MainActor in
                player.isFullScreen = false
            }
        }
        #endif
        
    }
}

