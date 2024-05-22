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

public struct SkeletonJointData:Equatable, Codable, Hashable, CustomMessageIdentifiable {
    public static var messageIdentifier: String = "com.noisederived.BodyDetectionBroadcasting.skeletonjointdata"
    let ident:String
    let jointData:[String:JointData]
}

extension SkeletonJointData: Transferable {
    public static var transferRepresentation: some TransferRepresentation {
        CodableRepresentation(contentType: .skeletonjointdata)
        
        DataRepresentation(contentType: .skeletonjointdata) { jointData in
            try JSONEncoder().encode(jointData)
        } importing: { data in
            try JSONDecoder().decode(SkeletonJointData.self, from: data)
        }
    }
}

extension UTType {
     static var skeletonjointdata: UTType { UTType(exportedAs: "com.noisederived.BodyDetectionBroadcasting.skeletonjointdata") }
}


public struct JointData:Identifiable, Equatable, Codable, Hashable, CustomMessageIdentifiable {
    public static var messageIdentifier: String = "com.noisederived.BodyDetectionBroadcasting.jointdata"

    public let id:String
    let d:JointMetadata
    let t:TranslationData
    let o:OrientationData
    let s:ScaleData
    let a:AnchorData
    
    static let zero = JointData(id: UUID().uuidString, d: JointMetadata(i: 0, t: 0, name: "root", ident: "zero", a: 0.0), t:TranslationData(x: 0, y: 0, z: 0), o: OrientationData(r: 1, ix: 0, iy: 0, iz: 0), s: ScaleData(x: 1, y: 1, z: 1), a: AnchorData(x: 0, y: 0, z: 0, r: 1, ix: 0, iy: 0, iz: 0))
    
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
    let i:Float
    let t:Double
    let name:String
    let ident:String
    let a:Float
}

public struct TranslationData:Equatable, Codable, Hashable {
    let x:Float
    let y:Float
    let z:Float
}

public struct ScaleData:Equatable, Codable, Hashable {
    let x:Float
    let y:Float
    let z:Float
}

public struct OrientationData:Equatable, Codable, Hashable {
    let r:Float
    let ix:Float
    let iy:Float
    let iz:Float
}

public struct AnchorData: Equatable, Codable, Hashable {
    let x:Float
    let y:Float
    let z:Float
    let r:Float
    let ix:Float
    let iy:Float
    let iz:Float
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
