//
//  JointData.swift
//  BodyDetectionBroadcasting
//
//  Created by Michael A Edgcumbe on 3/6/24.
//

import Foundation
import RealityKit
import Combine
import GroupActivities
import CoreTransferable
import UniformTypeIdentifiers

public struct DanceCoordinator:GroupActivity, Identifiable, Codable {
    public var id:UUID = UUID()
    public var sharedVideo:URL = URL(string:"http://10.0.0.68:1935/ShadowDancingBroadcasting/countryclub/playlist.m3u8?DVR")!
    public var sharedAudio:URL = URL(string:"http://10.0.0.68:8000/radio")!

    public static let activityIdentifier = "com.noisederived.BodyDetectionBroadcasting.body-tracking"
}

extension DanceCoordinator {
    // Provide information about the activity.
    public var metadata: GroupActivityMetadata {
        var metadata = GroupActivityMetadata()
        metadata.type = .workoutTogether
        metadata.title = "Shadow Dancing"
        metadata.fallbackURL = URL(string:"https://secretatomics.com")!
        metadata.supportsContinuationOnTV = false

        return metadata
    }
}


public struct JointData: Equatable, Codable, Hashable, CustomMessageIdentifiable {
    
    public static var messageIdentifier: String = "com.noisederived.BodyDetectionBroadcasting.jointdata"

    let d:JointMetadata
    let t:TranslationData
    let o:OrientationData
    let s:ScaleData
    let a:AnchorData
    
    static let zero = JointData(d: JointMetadata(i: 0, t: 0, name: "root"), t:TranslationData(x: 0, y: 0, z: 0), o: OrientationData(r: 1, ix: 0, iy: 0, iz: 0), s: ScaleData(x: 1, y: 1, z: 1), a: AnchorData(x: 0, y: 0, z: 0, r: 1, ix: 0, iy: 0, iz: 0))
    
    var scale:SIMD3<Float> {
        get {
            return SIMD3<Float>(Float(s.x ), Float(s.y), Float(s.z))
        }
    }
    var translation:SIMD3<Float> {
        get {
            return SIMD3<Float>(Float(t.x), Float(t.y), Float(t.z))
        }
    }
    var orientation:simd_quatf {
        get {
            return simd_quatf(real: Float(o.r), imag: SIMD3(Float(o.ix), Float(o.iy), Float(o.iz)))
        }
    }
    
    var transform:Transform {
        get {
            return Transform(scale: scale, rotation: orientation, translation: translation)
        }
    }
}

public struct JointMetadata : Equatable, Codable, Hashable {
    let i:Double
    let t:Double
    let name:String
}

public struct TranslationData:Equatable, Codable, Hashable {
    let x:Double
    let y:Double
    let z:Double
}

public struct ScaleData:Equatable, Codable, Hashable {
    let x:Double
    let y:Double
    let z:Double
}

public struct OrientationData:Equatable, Codable, Hashable {
    let r:Double
    let ix:Double
    let iy:Double
    let iz:Double
}

public struct AnchorData: Equatable, Codable, Hashable {
    let x:Double
    let y:Double
    let z:Double
    let r:Double
    let ix:Double
    let iy:Double
    let iz:Double
}



extension JointData: Transferable {
    public static var transferRepresentation: some TransferRepresentation {
        CodableRepresentation(contentType: .jointdata)
        
        DataRepresentation(contentType: .jointdata) { jointData in
            try JSONEncoder().encode(jointData)
        } importing: { data in
            try JSONDecoder().decode(JointData.self, from: data)
        }
    }
}

extension UTType {
     static var jointdata: UTType { UTType(exportedAs: "com.noisederived.BodyDetectionBroadcasting.jointdata") }
}
