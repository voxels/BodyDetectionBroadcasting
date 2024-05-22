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
    
    private var foundTracking = Set<UUID>()
    private var lostTracking = Set<UUID>()
    
    // Published values that the player, and other UI items, observe.
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
    public var attachmentHistory:[UUID] = [UUID]()
    @Published public var nextJointData:[String:[JointData]] = [String:[JointData]]()
    @Published public var lastJointData:[String:[JointData]]?
    private var decodeTask:Task<Void, Never>?
    
    
    // The 3D character to display.
    var characterIdentity: BodyTrackedEntity?
    let characterOffset: SIMD3<Float> = [0, 0, 0] // Offset the character by one meter to the left
    var characterAnchors = [UUID:AnchorEntity]()
    var characters = [UUID:BodyTrackedEntity]()
    var stream:OutputStream?
    let skipFrames:Int = 3
    private var displayLink:CADisplayLink!
    
    public var jointRawData = [String:[[String:Any]]]()
    @Published var displayLinkTimestamp:Double = 0
    var lastFrameDisplayLinkTimestamp:Double = 0
    let useShareplay:Bool
    public init(useShareplay:Bool) {
        self.useShareplay = useShareplay
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
    
    @MainActor
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
    
    @MainActor
    public func configureScene(arView:ARView) {
        // Asynchronously load the 3D character.
        var cancellable: AnyCancellable? = nil
        cancellable = Entity.loadBodyTrackedAsync(named: "character/biped_robot_90").sink(
            receiveCompletion: { completion in
                if case let .failure(error) = completion {
                    print("Error: Unable to load model: \(error.localizedDescription)")
                }
                cancellable?.cancel()
            }, receiveValue: { (character: Entity) in
                if let character = character as? BodyTrackedEntity {
                    self.characterIdentity = character
                    cancellable?.cancel()
                } else {
                    print("Error: Unable to load model as BodyTrackedEntity")
                }
            })
        
    }
}

extension ContentViewShareplayModel : ARSessionDelegate {
    public func session(_ session: ARSession, didUpdate anchors: [ARAnchor]) {
        if !useShareplay {
            return
        }
        for anchor in anchors {
            guard let bodyAnchor = anchor as? ARBodyAnchor else {
                continue
            }
            
//            if bodyAnchor.isTracked {
//                foundTracking.insert(anchor.identifier)
//                lostTracking.remove(anchor.identifier)
//            } else {
//                foundTracking.remove(anchor.identifier)
//                lostTracking.insert(anchor.identifier)
//                if let anchor = characterAnchors[anchor.identifier] {
//                    anchor.removeFromParent()
//                }
//                characters.removeValue(forKey: anchor.identifier)
//                characterAnchors.removeValue(forKey: anchor.identifier)
//            }
            
            
            if let characterIdentity = characterIdentity, !characterAnchors.keys.contains(anchor.identifier) {
                let bodyPosition = simd_make_float3(bodyAnchor.transform.columns.3)
                var newAnchor = AnchorEntity()
                newAnchor.position = bodyPosition + characterOffset
                // Also copy over the rotation of the body anchor, because the skeleton's pose
                // in the world is relative to the body anchor's rotation.
                newAnchor.orientation = Transform(matrix: bodyAnchor.transform).rotation
                let newCharacter = characterIdentity.clone(recursive: true)
                newAnchor.addChild(newCharacter)
                characterAnchors[anchor.identifier] = newAnchor
                characters[anchor.identifier] = newCharacter
            } else if let characterIdentity = characterIdentity, let characterAnchor = characterAnchors[anchor.identifier] {
                let bodyPosition = simd_make_float3(bodyAnchor.transform.columns.3)

                var newAnchor = characterAnchor
                newAnchor.position = bodyPosition + characterOffset
                // Also copy over the rotation of the body anchor, because the skeleton's pose
                // in the world is relative to the body anchor's rotation.
                newAnchor.orientation = Transform(matrix: bodyAnchor.transform).rotation
                characterAnchors[anchor.identifier] = newAnchor
            }
            
            var newJointData = [[String:Any]]()
            let skeletonLocalTransforms = bodyAnchor.skeleton.jointLocalTransforms
            
            for index in 0..<ARSkeletonDefinition.defaultBody3D.jointNames.count {
                let id = UUID().uuidString
                let name = ARSkeletonDefinition.defaultBody3D.jointNames[index]
                let transform = Transform(matrix:skeletonLocalTransforms[index])
                let translationValues = [
                    "x":preciseRound(transform.translation.x),
                    "y":preciseRound(transform.translation.y),
                    "z":preciseRound(transform.translation.z)
                ] as NSDictionary
                let orientationValues = [
                    "r":preciseRound(transform.rotation.real),
                    "ix":preciseRound(transform.rotation.imag.x),
                    "iy":preciseRound(transform.rotation.imag.y),
                    "iz":preciseRound(transform.rotation.imag.z),
                ] as NSDictionary
                let scaleValues = [
                    "x":preciseRound(transform.scale.x),
                    "y":preciseRound(transform.scale.y),
                    "z":preciseRound(transform.scale.z),
                ]
                let metadataValues = [
                    "i":Float(index),
                    "t":preciseRound(Float(displayLinkTimestamp)),
                    "name":name,
                    "ident":anchor.identifier.uuidString
                ] as NSDictionary
                
                let characterAnchor = characterAnchors[anchor.identifier]!
                
                let anchorValues = [
                    "x":preciseRound(characterAnchor.transform.translation.x),
                    "y":preciseRound(characterAnchor.transform.translation.y),
                    "z":preciseRound(characterAnchor.transform.translation.z),
                    "r":preciseRound(characterAnchor.transform.rotation.real),
                    "ix":preciseRound(characterAnchor.transform.rotation.imag.x),
                    "iy":preciseRound(characterAnchor.transform.rotation.imag.y),
                    "iz":preciseRound(characterAnchor.transform.rotation.imag.z)
                ] as NSDictionary
                
                
                let jointData = ["id":id,"d":metadataValues,"t":translationValues,"o":orientationValues, "s":scaleValues, "a":anchorValues, "f":foundTracking.map({$0.uuidString}), "l":lostTracking.map({$0.uuidString})] as [String : Any]
                newJointData.append(jointData)
            }
            
            let checker = JSONSerialization.isValidJSONObject(newJointData)
            if checker {
                jointRawData[anchor.identifier.uuidString] = newJointData
            } else {
                print("Found invalid new joint data \(newJointData)")
            }
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
    @MainActor
    func encodeJointData() {
        var allSkeletonJointData = [String:[JointData]]()
        for key in jointRawData.keys {
            var finalJointData = [JointData]()
            let skeletonJointRawData = jointRawData[key]!
            for rawData in skeletonJointRawData {
                do {
                    let checker = JSONSerialization.isValidJSONObject(rawData)
                    if checker {
                        let decodedData = try decode(JointData.self, from: rawData)
                        finalJointData.append(decodedData)
                    } else {
                        print("Raw data is not a json object:\(rawData)")
                    }
                } catch {
                    print(error)
                }
            }
            
            allSkeletonJointData[key] = finalJointData
        }
        
        lastJointData = nextJointData
        nextJointData = allSkeletonJointData
    }
    
    @MainActor
    @objc func onFrame(link:CADisplayLink) {
        encodeJointData()
        lastFrameDisplayLinkTimestamp = displayLinkTimestamp
        displayLinkTimestamp = link.timestamp
    }
}

extension ContentViewShareplayModel {
    @MainActor
    public func handle(message:JointData) async {
        
        
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
            isReady = false
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
            if let groupSession = groupSession {
                configureGroupSession(groupSession)
            }
        default: ()
        }
    }
    
    @MainActor
    func configureGroupSession(_ groupSession: GroupSession<DanceCoordinator>) {
        print("Configure group session")
        self.groupSession = groupSession
        if !groupSession.activeParticipants.contains(groupSession.localParticipant) {
            Task {
                await joinDanceCoordinator(groupSession: groupSession)
            }
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


extension ContentViewShareplayModel {


    // Round to the specific decimal place
    public func preciseRound(
        _ value: Float,
        precision: RoundingPrecision = .tenThousands) -> Float
    {
       return value
    }
}
