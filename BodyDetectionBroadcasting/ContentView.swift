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
    @StateObject private var shareplayModel = ContentViewShareplayModel(useShareplay: false)
    @State private var useShareplay = false
    var body: some View {
        if useShareplay {
            if !shareplayModel.isReady {
                ShareplayViewContainer(shareplayModel: shareplayModel)
                    .task {
                        for await dancingSession in DanceCoordinator.sessions() {
                            print("found coordinator session \(dancingSession.activity.id)")
                            shareplayModel.configureGroupSession(dancingSession)
                        }
                    }
            } else {
                ARViewContainer(model: model, shareplayModel: shareplayModel, useShareplay: useShareplay)
                    .onChange(of: shareplayModel.encodedJointData, { oldValue, newValue in
                        guard let newValue = newValue, let journal = shareplayModel.journal, let groupSession = shareplayModel.groupSession, groupSession.activeParticipants.count > 1 else {
                            print("Active participants: \(shareplayModel.groupSession?.activeParticipants)")
                            return
                        }
                        Task {
                            do {
                                let data = try JSONEncoder().encode(newValue)
                                
                                let attachment = try await journal.add(data)
                                print("Sending attachment:\(attachment.id)")
                                shareplayModel.attachmentHistory.append(attachment)
                            } catch {
                                print(error)
                            }
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
            }
        } else {
                ARViewContainer(model: model, shareplayModel: shareplayModel, useShareplay: useShareplay)
                .onAppear {
                    model.startAdvertisingDevice()
                    
                }
                .onDisappear(perform: {
                    model.stopAdvertisingDevice()
                })
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
