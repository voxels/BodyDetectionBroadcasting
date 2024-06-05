//
//  ContentView.swift
//  BodyDetectionBroadcasting
//
//  Created by Michael A Edgcumbe on 2/13/24.
//

import SwiftUI
import RealityKit
import ARKit
import GroupActivities
import _GroupActivities_UIKit

struct ContentView : View {
    @StateObject private var model = ContentViewModel()
    @StateObject private var shareplayModel = ContentViewShareplayModel(useShareplay: true)
    @State private var useShareplay = false
    @State private var useJournal = false
    @State private var playerModel = PlayerModel()
    @State private var sendTask:Task<Void, Never>?
    private let videoURLString = "http://192.168.8.179:1935/live/countryclub/playlist.m3u8?DVR"
    private let audioURLString = "http://192.168.8.179:8000/radio"
    var body: some View {
        if useShareplay {
            if !shareplayModel.isReady {
                ShareplayViewContainer(shareplayModel: shareplayModel)
                    .task {
                        await shareplayModel.shareActivity()
                    }
                    .task {
                        for await dancingSession in DanceCoordinator.sessions() {
                            print("found coordinator session \(dancingSession.activity.id)")
                            shareplayModel.configureGroupSession(dancingSession)
                        }
                    }
            } else {
                ZStack(alignment: .bottomTrailing, content: {
                    ARViewContainer(model: model, shareplayModel: shareplayModel, useShareplay: useShareplay)
                        .onChange(of: shareplayModel.nextJointData, { oldValue, newValue in
                            if useJournal {
                                guard let journal = shareplayModel.journal, let groupSession = shareplayModel.groupSession, groupSession.activeParticipants.count > 1, groupSession.state == .joined else {
                                    print("Active participants: \(shareplayModel.groupSession?.activeParticipants)")
                                    return
                                }
                                Task(priority: .userInitiated, operation: {
                                    for key in newValue.keys {
                                        let jointsData = newValue[key]!
                                        var encodedJointsData = [String:JointData]()
                                        
                                        for jointsDatum in jointsData {
                                            encodedJointsData[jointsDatum.d.name] = jointsDatum
                                        }
                                        
                                        let skeletonJointData = SkeletonJointData(ident: key, jointData:encodedJointsData)
                                        do {
                                            let attachment = try await journal.add(skeletonJointData)
                                            print("Sending attachment:\(attachment.id)")
                                            shareplayModel.attachmentHistory.append(attachment.id)
                                        } catch {
                                            print(error)
                                        }
                                    }
                                })
                            } else {
                                guard let messenger = shareplayModel.messenger, let groupSession = shareplayModel.groupSession, groupSession.state == .joined else {
                                    print("Active participants: \(shareplayModel.groupSession?.activeParticipants)")
                                    return
                                }
                                Task(priority: .userInitiated, operation: {
                                    for key in newValue.keys {
                                        let jointsData = newValue[key]!
                                        for jointsDatum in jointsData {
                                            do {
                                                try await messenger.send(jointsDatum)
                                            } catch {
                                                print(error)
                                            }
                                        }
                                    }
                                })
                            }
                        })
                    
                        .onAppear(perform: {
                            shareplayModel.startAdvertisingDevice()
                        })
                        .edgesIgnoringSafeArea(.all)
                        .onDisappear(perform: {
                            shareplayModel.stopAdvertisingDevice()
                        })
                        .onChange(of: shareplayModel.groupSession?.state) { oldValue, newValue in
                            if case .invalidated = newValue {
                                shareplayModel.isReady = false
                            }
                        }
//                        .task {
//                            if let groupSession = shareplayModel.groupSession {
//                                playerModel.player.playbackCoordinator.coordinateWithSession(groupSession)
//                                playerModel.audioPlayer.playbackCoordinator.coordinateWithSession(groupSession)
//                                Task { @MainActor in
//                                    do {
//                                        playerModel.loadAudio(urlString: audioURLString)
//                                        try await playerModel.loadVideo(URL(string:videoURLString)!, presentation: .fullWindow)
//                                    } catch {
//                                        print(error)
//                                    }
//                                }
//                            }
//                        }
//                    PlayerViewController(model: $playerModel)
//                        .frame(width:320, height:240)
//                        .padding(32)
//                        .onDisappear(perform: {
//                            playerModel.stop()
//                        })
//                        .foregroundStyle(.clear)
                })
            }
        } else {
            ARViewContainer(model: model, shareplayModel: shareplayModel, useShareplay: useShareplay)
            .onAppear {
                model.startAdvertisingDevice()
            }
            .onDisappear(perform: {
                model.stopAdvertisingDevice()
            })
            .onChange(of: model.frameCount) { oldValue, newValue in
                if model.multipeerSession.connectedPeers.count >= 1 {
                    if let sendTask = sendTask, !sendTask.isCancelled {
                        print("Cancelling task")
                        sendTask.cancel()
                    }
                    
                    sendTask = Task(priority: .userInitiated) {
                        if Task.isCancelled {
                            print("Canceled task")
                            return
                        }
                        model.send(rawData:model.jointRawData)
                        print("Sent model")
                    }
                }
            }
        }
    }
}

struct ARViewContainer: UIViewRepresentable {
    @ObservedObject private var model:ContentViewModel
    @ObservedObject private var shareplayModel:ContentViewShareplayModel
    private var useShareplay = false
    
    public init( model:ContentViewModel, shareplayModel:ContentViewShareplayModel, useShareplay:Bool) {
        self.useShareplay = useShareplay
        self.model = model
        self.shareplayModel = shareplayModel
    }
    
    func makeUIView(context: Context) -> ARView {
        let arView = ARView(frame: .zero)
        if useShareplay {
            shareplayModel.load(arView: arView)
        } else {
            model.load(arView: arView)
        }
        
        return arView
    }
    
    func updateUIView(_ uiView: ARView, context: Context) {}
    
}

#Preview {
    ContentView()
}
