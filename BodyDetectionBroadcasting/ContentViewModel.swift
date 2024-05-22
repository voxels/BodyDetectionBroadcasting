//
//  ContentViewModel.swift
//  BodyDetectionBroadcasting
//
//  Created by Michael A Edgcumbe on 2/13/24.
//

import Foundation
import RealityKit
import ARKit
import Combine
import MultipeerConnectivity

// Specify the decimal place to round to using an enum
public enum RoundingPrecision {
    case ones
    case tenths
    case hundredths
    case thousands
    case tenThousands
}

open class ContentViewModel: NSObject, ObservableObject {
    @Published public var isAdvertising:Bool = false
    // The 3D character to display.
    var character: BodyTrackedEntity?
    var characterIdentity: BodyTrackedEntity?
    let characterOffset: SIMD3<Float> = [0, 0, 0] // Offset the character by one meter to the left
    let characterAnchor = AnchorEntity()
    var characterAnchors = [UUID:AnchorEntity]()
    var characters = [UUID:BodyTrackedEntity]()

    private var sendTask:Task<Void, Never>?
    private var displayLink:CADisplayLink!
    public let multipeerSession: MCSession
    // 2
    private let myPeerId = MCPeerID(displayName: UIDevice.current.name)
    
    private static let service = "body-tracking"
    private var nearbyServiceAdvertiser: MCNearbyServiceAdvertiser
    public var jointRawData = [String:[[String:Any]]]()
    private var countFrames = 0
    public var frameCount = 0
    let skipFrames:Int = 3
    @Published var displayLinkTimestamp:Double = 0
    var lastFrameDisplayLinkTimestamp:Double = 0
    override public init() {
        self.multipeerSession = MCSession(peer: myPeerId, securityIdentity: nil, encryptionPreference: .none)
        self.nearbyServiceAdvertiser = MCNearbyServiceAdvertiser(peer: multipeerSession.myPeerID, discoveryInfo: nil, serviceType: ContentViewModel.service)
        super.init()
        multipeerSession.delegate = self
        nearbyServiceAdvertiser.delegate = self
        createDisplayLink()
    }
    
    public func startAdvertisingDevice()
    {
        nearbyServiceAdvertiser.startAdvertisingPeer()
        isAdvertising = true
        print("started advertising")
    }
    
    public func stopAdvertisingDevice() {
        nearbyServiceAdvertiser.stopAdvertisingPeer()
        isAdvertising = false
        print("stopped advertising")
    }
    
    public func load(arView:ARView) {
        arView.session.delegate = self
        
        // If the iOS device doesn't support body tracking, raise a developer error for
        // this unhandled case.
        guard ARBodyTrackingConfiguration.isSupported else {
            fatalError("This feature is only supported on devices with an A12 chip")
        }

        // Run a body tracking configration.
        let configuration = ARBodyTrackingConfiguration()
        arView.session.run(configuration)
        
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
                self.characterIdentity = character
                cancellable?.cancel()
            } else {
                print("Error: Unable to load model as BodyTrackedEntity")
            }
        })
    }
}

extension ContentViewModel : ARSessionDelegate {
    public func session(_ session: ARSession, didUpdate anchors: [ARAnchor]) {
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
                    "t":displayLinkTimestamp,
                    "name":name,
                    "ident":anchor.identifier.uuidString,
                    "a":bodyAnchor.isTracked ? 1.0 : 0.0
                ] as NSDictionary
                
                guard let characterAnchor = characterAnchors[anchor.identifier] else {
                    continue
                }
                
                let anchorValues = [
                    "x":preciseRound(characterAnchor.transform.translation.x),
                    "y":preciseRound(characterAnchor.transform.translation.y),
                    "z":preciseRound(characterAnchor.transform.translation.z),
                    "r":preciseRound(characterAnchor.transform.rotation.real),
                    "ix":preciseRound(characterAnchor.transform.rotation.imag.x),
                    "iy":preciseRound(characterAnchor.transform.rotation.imag.y),
                    "iz":preciseRound(characterAnchor.transform.rotation.imag.z)
                ] as NSDictionary
                
                
                let jointData = ["id":id,"d":metadataValues,"t":translationValues,"o":orientationValues, "s":scaleValues, "a":anchorValues] as [String : Any]
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
    
    public func send(rawData:[String : [[String : Any]]]) async -> Void {
        do {
            let jsonData = try JSONSerialization.data(withJSONObject:rawData)
            try multipeerSession.send(jsonData, toPeers: multipeerSession.connectedPeers, with: .unreliable)
        } catch {
            print(error)
        }
    }
}


extension ContentViewModel : MCSessionDelegate {
    
    public func session(_ session: MCSession, peer peerID: MCPeerID, didChange state: MCSessionState) {
        switch state{
        case .notConnected:
            break
        case .connecting:
            break
        case .connected:
            break
        @unknown default:
            fatalError()
        }
    }
    
    public func session(_ session: MCSession, didReceive data: Data, fromPeer peerID: MCPeerID) {
        
    }
    
    public func session(_ session: MCSession, didReceive stream: InputStream, withName streamName: String, fromPeer peerID: MCPeerID) {
        
    }
    
    public func session(_ session: MCSession, didStartReceivingResourceWithName resourceName: String, fromPeer peerID: MCPeerID, with progress: Progress) {
        
    }
    
    public func session(_ session: MCSession, didFinishReceivingResourceWithName resourceName: String, fromPeer peerID: MCPeerID, at localURL: URL?, withError error: Error?) {
        
    }
}



extension ContentViewModel {
    private func createDisplayLink() {
        displayLink = CADisplayLink(target: self, selector:#selector(onFrame(link:)))
        displayLink.preferredFramesPerSecond = 30
        displayLink.add(to: .main, forMode: .default)
    }
}

extension ContentViewModel {
    
    @objc func onFrame(link:CADisplayLink) {
        lastFrameDisplayLinkTimestamp = displayLinkTimestamp
        displayLinkTimestamp = link.timestamp
        frameCount += 1
    }
}

extension ContentViewModel : MCNearbyServiceAdvertiserDelegate {
    public func advertiser(_ advertiser: MCNearbyServiceAdvertiser, didReceiveInvitationFromPeer peerID: MCPeerID, withContext context: Data?, invitationHandler: @escaping (Bool, MCSession?) -> Void) {
        invitationHandler(true, self.multipeerSession)
    }
    
}

extension ContentViewModel {
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

extension ContentViewModel {
    // Round to the specific decimal place
    public func preciseRound(
        _ value: Float,
        precision: RoundingPrecision = .tenThousands) -> Double
    {
        return Double(value)
//        switch precision {
//        case .ones:
//            return round(value)
//        case .tenths:
//            return round(value * 10) / 10.0
//        case .hundredths:
//            return round(value * 100) / 100.0
//        case .thousands:
//            return round(value * 1000) / 1000.0
//        case .tenThousands:
//            return round(value * 10000) / 10000.0
//        }
    }
    
    
    func run(function: () -> Void, withFrequency hz: UInt64) async {
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
            
            function()
        }
    }

}
