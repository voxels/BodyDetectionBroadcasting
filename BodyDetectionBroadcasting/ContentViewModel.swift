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

open class ContentViewModel: NSObject, ObservableObject {
    // The 3D character to display.
    var character: BodyTrackedEntity?
    var characterIdentity: BodyTrackedEntity?
    let characterOffset: SIMD3<Float> = [0, 0, 0] // Offset the character by one meter to the left
    let characterAnchor = AnchorEntity()
    var stream:OutputStream?
    let skipFrames:Int = 5
    private var displayLink:CADisplayLink!
    private let multipeerSession: MCSession
    // 2
    private let myPeerId = MCPeerID(displayName: UIDevice.current.name)
    
    private static let service = "body-tracking"
    private var nearbyServiceAdvertiser: MCNearbyServiceAdvertiser
    public var jointRawData = [[String:Any]]()
    var displayLinkTimestamp:Double = 0
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
    }
    
    public func stopAdvertisingDevice() {
        nearbyServiceAdvertiser.stopAdvertisingPeer()
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
            guard let bodyAnchor = anchor as? ARBodyAnchor else { continue }
   
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
            
            jointRawData.removeAll(keepingCapacity: true)
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
        displayLink.add(to: .main, forMode: .default)
    }
}

extension ContentViewModel {
    
    @objc func onFrame(link:CADisplayLink) {
        if displayLinkTimestamp < lastFrameDisplayLinkTimestamp + displayLink.duration * Double(skipFrames) {
            displayLinkTimestamp = link.timestamp
            return
        }
        
        do{
            let jsonData = try JSONSerialization.data(withJSONObject: jointRawData)
            try multipeerSession.send(jsonData, toPeers: multipeerSession.connectedPeers, with: .reliable)
            lastFrameDisplayLinkTimestamp = displayLinkTimestamp
            displayLinkTimestamp = link.timestamp
        } catch {
            lastFrameDisplayLinkTimestamp = displayLinkTimestamp
            displayLinkTimestamp = link.timestamp
            print(error)
        }
    }
}

extension ContentViewModel : MCNearbyServiceAdvertiserDelegate {
    public func advertiser(_ advertiser: MCNearbyServiceAdvertiser, didReceiveInvitationFromPeer peerID: MCPeerID, withContext context: Data?, invitationHandler: @escaping (Bool, MCSession?) -> Void) {
        invitationHandler(true, self.multipeerSession)
    }
    
}
