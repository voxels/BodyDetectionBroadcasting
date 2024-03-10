//
//  ContentViewShareplayModel.swift
//  BodyDetectionBroadcasting
//
//  Created by Michael A Edgcumbe on 3/6/24.
//


import Foundation
import RealityKit
import ARKit
import Combine
import GroupActivities

open class ContentViewShareplayModel: NSObject, ObservableObject {
    
    static let shared = ContentViewShareplayModel(useShareplay: true)
    @Published public var isActivated = false
    @Published public var isReady = false
    private var currentSession:ARSession?
    private var subscriptions = Set<AnyCancellable>()

    // Published values that the player, and other UI items, observe.
    @Published var enqueuedJointData: JointData?
    var groupSession: GroupSession<DanceCoordinator>? {
        didSet {
            if let groupSession = groupSession {
                let messenger = GroupSessionMessenger(session: groupSession, deliveryMode: .unreliable)
                self.messenger = messenger
                let journal = GroupSessionJournal(session: groupSession)
                self.journal = journal
                print("did set group session")
            }
        }
    }
    
    public var coordinator:DanceCoordinator?
    public var messenger:GroupSessionMessenger?
    public var journal:GroupSessionJournal?
    public var attachmentHistory:[GroupSessionJournal.Attachment] = [GroupSessionJournal.Attachment]()
    @Published public var encodedJointData:[String:JointData]?
    @Published public var nextJointData:[JointData]?
    @Published public var lastJointData:[JointData]?
    @Published public var jointHistory:[JointData] = [JointData]()
    private var decodeTask:Task<Void, Never>?

 
    // The 3D character to display.
    var character: BodyTrackedEntity?
    var characterIdentity: BodyTrackedEntity?
    let characterOffset: SIMD3<Float> = [0, 0, 0] // Offset the character by one meter to the left
    let characterAnchor = AnchorEntity()
    var stream:OutputStream?
    let skipFrames:Int = 5
    private var displayLink:CADisplayLink!
    
    public var jointRawData = [[String:Any]]()
    @Published var displayLinkTimestamp:Double = 0
    var lastFrameDisplayLinkTimestamp:Double = 0
    
    public init(useShareplay:Bool) {
        super.init()
        if useShareplay {
            createDisplayLink()
        }
    }
    
    @discardableResult
    public func createCoordinator() async->DanceCoordinator {
        let activity = DanceCoordinator()
        coordinator = activity
        return activity
}

    @MainActor
    public func startAdvertisingDevice()
    {
        if let currentSession = currentSession {
            currentSession.pause()
            print("Running session")
            currentSession.run(ARBodyTrackingConfiguration())
            
        }
    }
    
    public func stopAdvertisingDevice() {
        currentSession?.pause()
    }
    
    public func load(arView:ARView) {
        currentSession = arView.session
        arView.session.delegate = self
        
        // If the iOS device doesn't support body tracking, raise a developer error for
        // this unhandled case.
        guard ARBodyTrackingConfiguration.isSupported else {
            fatalError("This feature is only supported on devices with an A12 chip")
        }

        // Run a body tracking configration.
        let configuration = ARBodyTrackingConfiguration()
        arView.session.run(configuration)
        configureScene(arView: arView)
        
    }
    
    public func configureScene(arView:ARView) {
        arView.scene.addAnchor(characterAnchor)

        // Asynchronously load the 3D character.
        var cancellable: AnyCancellable? = nil
        cancellable = Entity.loadBodyTrackedAsync(named: "character/biped_robot").sink(
            receiveCompletion: { completion in
                if case let .failure(error) = completion {
                    print("Error: Unable to load model: \(error.localizedDescription)")
                }
                cancellable?.cancel()
        }, receiveValue: { (character: Entity) in
            if let character = character as? BodyTrackedEntity {
                // Scale the character to human size
                //self.characterAnchor.scale = [0.01, 0.01, 0.01]
                self.character = character
                cancellable?.cancel()
            } else {
                print("Error: Unable to load model as BodyTrackedEntity")
            }
        })

    }
}

extension ContentViewShareplayModel : ARSessionDelegate {
    public func session(_ session: ARSession, didUpdate anchors: [ARAnchor]) {
        for anchor in anchors {
            guard let bodyAnchor = anchor as? ARBodyAnchor else { continue }
            print("found body anchor")
   
            if let character = character, character.parent == nil {
                // Attach the character to its anchor as soon as
                // 1. the body anchor was detected and
                // 2. the character was loaded.
                // Update the position of the character anchor's position.
                let bodyPosition = simd_make_float3(bodyAnchor.transform.columns.3)
                characterAnchor.position = bodyPosition + characterOffset
                // Also copy over the rotation of the body anchor, because the skeleton's pose
                // in the world is relative to the body anchor's rotation.
                characterAnchor.orientation = Transform(matrix: bodyAnchor.transform).rotation
                characterAnchor.addChild(character)
            } else if let _ = character {
                let bodyPosition = simd_make_float3(bodyAnchor.transform.columns.3)
                characterAnchor.position = bodyPosition + characterOffset
                // Also copy over the rotation of the body anchor, because the skeleton's pose
                // in the world is relative to the body anchor's rotation.
                characterAnchor.orientation = Transform(matrix: bodyAnchor.transform).rotation
            }
            
            var newJointData = jointRawData
            let skeletonLocalTransforms = bodyAnchor.skeleton.jointLocalTransforms
                
            for index in 0..<ARSkeletonDefinition.defaultBody3D.jointNames.count {
                    let name = ARSkeletonDefinition.defaultBody3D.jointNames[index]
                let transform = Transform(matrix:skeletonLocalTransforms[index])
                    let translationValues = [
                        "x":Double(transform.translation.x),
                        "y":Double(transform.translation.y),
                        "z":Double(transform.translation.z)
                    ] as NSDictionary
                    let orientationValues = [
                        "r":Double(transform.rotation.real),
                        "ix":Double(transform.rotation.imag.x),
                        "iy":Double(transform.rotation.imag.y),
                        "iz":Double(transform.rotation.imag.z),
                    ] as NSDictionary
                    let scaleValues = [
                        "x":Double(transform.scale.x),
                        "y":Double(transform.scale.y),
                        "z":Double(transform.scale.z),
                    ]
                    let metadataValues = [
                        "i":Double(index),
                        "t":displayLinkTimestamp,
                        "name":name
                    ] as NSDictionary
                    
                    let anchorValues = [
                        "x":Double(characterAnchor.transform.translation.x),
                        "y":Double(characterAnchor.transform.translation.y),
                        "z":Double(characterAnchor.transform.translation.z),
                        "r":Double(characterAnchor.transform.rotation.real),
                        "ix":Double(characterAnchor.transform.rotation.imag.x),
                        "iy":Double(characterAnchor.transform.rotation.imag.y),
                        "iz":Double(characterAnchor.transform.rotation.imag.z)
                    ] as NSDictionary
                    let jointData = ["d":metadataValues,"t":translationValues,"o":orientationValues, "s":scaleValues, "a":anchorValues] as [String : Any]
                    newJointData.append(jointData)
                }
            jointRawData = newJointData
        }
    }
    
    public func session(_ session: ARSession, didUpdate frame: ARFrame) {
        
    }
}



extension ContentViewShareplayModel {
    private func createDisplayLink() {
        displayLink = CADisplayLink(target: self, selector:#selector(onFrame(link:)))
        displayLink.add(to: .main, forMode: .default)
    }
}

extension ContentViewShareplayModel {
    
    @objc func onFrame(link:CADisplayLink) {
            Task { @MainActor in
                
                var finalJointData = [JointData]()
                for rawData in jointRawData {
                    do {
                        let decodedData = try decode(JointData.self, from: rawData)
                        finalJointData.append(decodedData)
                    } catch {
                        print(error)
                    }
                }
                lastJointData = nextJointData
                nextJointData = finalJointData
                var encodedData = [String:JointData]()
                for nextJointDatum in finalJointData {
                    encodedData[nextJointDatum.d.name] = nextJointDatum
                }
                encodedJointData = encodedData
                    print("set encoded data")
                }
        
        
        lastFrameDisplayLinkTimestamp = displayLinkTimestamp
        displayLinkTimestamp = link.timestamp
    }
}

extension ContentViewShareplayModel {
    @MainActor
    public func handle(message:JointData) async {
        
        if jointHistory.count >= 100 {
            jointHistory.remove(at: 0)
        }
        jointHistory.append(message)
    }
    
    @MainActor
    public func shareActivity() async {
        guard let coordinator = coordinator else {
            print("no activity")
            return
        }
        // Await the result of the preparation call.
        switch await coordinator.prepareForActivation() {
            
        case .activationDisabled:
            print("Activation disabled")
//            // Playback coordination isn't active, or the user prefers to play the
//            // movie apart from the group. Enqueue the movie for local playback only.
            
        case .activationPreferred:
            // The user prefers to share this activity with the group.
            // The app enqueues the movie for playback when the activity starts.
            do {
                let isActive = try await coordinator.activate()
                print("Activated activity \(isActive)")
            } catch {
                print("Unable to activate the activity: \(error)")
            }
            
        case .cancelled:
            // The user cancels the operation. Do nothing.
            break
            
        default: ()
        }
    }
    
    @MainActor
    func configureGroupSession(_ groupSession: GroupSession<DanceCoordinator>) {
        print("Configure group session")
        self.groupSession = groupSession
        Task {
            await joinDanceCoordinator(groupSession: groupSession)
        }
    }
    
    @MainActor
    public func joinDanceCoordinator(groupSession:GroupSession<DanceCoordinator>) async {
            // Remove previous subscriptions.
            subscriptions.removeAll()
            
            // Observe changes to the session state.
            groupSession.$state.sink { [weak self] state in
                if case .invalidated = state {
                    // Set the groupSession to nil to publish
                    // the invalidated session state.
                    self?.groupSession = nil
                    self?.messenger = nil
                    self?.journal = nil
                    self?.subscriptions.removeAll()
                    self?.isActivated = false
                    self?.isReady = false
                    print("Session invalidated")
                } else if case .joined = state {
                    print("Joined group session \(groupSession.id)\t\(groupSession.activeParticipants)")
                    self?.isActivated = true
                }
            }.store(in: &subscriptions)
            
            // Join the session to participate in playback coordination.
        if groupSession.state != .joined  {
            groupSession.join()
        }
            
            // Observe when the local user or a remote participant starts an activity.
            groupSession.$activity.sink { [weak self] activity in
                print("activity is active:\(activity.id)")
                self?.isReady = true
            }.store(in: &subscriptions)
        }
}


extension ContentViewShareplayModel {
    /// Run a given function at an approximate frequency.
    ///
    /// > Note: This method doesn’t take into account the time it takes to run the given function itself.
    @MainActor
    func run(function: () async -> Void, withFrequency hz: UInt64) async {
        while true {
            if Task.isCancelled {
                return
            }
            
            // Sleep for 1 s / hz before calling the function.
            let nanoSecondsToSleep: UInt64 = NSEC_PER_SEC / hz
            do {
                try await Task.sleep(nanoseconds: nanoSecondsToSleep)
            } catch {
                // Sleep fails when the Task is cancelled. Exit the loop.
                return
            }
            
            await function()
        }
    }
}



extension ContentViewShareplayModel {
    func decode<T>(_ type: T.Type, from dictionary: [String: Any]) throws -> T where T : Decodable {
        let decoder = JSONDecoder()
        let data = try JSONSerialization.data(withJSONObject: dictionary, options: [])
        return try decoder.decode(type, from: data)
    }
}
