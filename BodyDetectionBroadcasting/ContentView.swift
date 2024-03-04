//
//  ContentView.swift
//  BodyDetectionBroadcasting
//
//  Created by Michael A Edgcumbe on 2/13/24.
//

import SwiftUI
import RealityKit
import ARKit

struct ContentView : View {
    
    @StateObject private var model = ContentViewModel()
    
    var body: some View {
        ARViewContainer(model:model).edgesIgnoringSafeArea(.all)
            .onAppear(perform: {
                model.startAdvertisingDevice()
            })
            .onDisappear(perform: {
                model.stopAdvertisingDevice()
            })
    }
}

struct ARViewContainer: UIViewRepresentable {
    @ObservedObject private var model:ContentViewModel
    
    public init(model: ContentViewModel) {
        self.model = model
    }
    
    func makeUIView(context: Context) -> ARView {
        
        let arView = ARView(frame: .zero)
        model.load(arView: arView)
        return arView
    }
    
    func updateUIView(_ uiView: ARView, context: Context) {}
    
}

#Preview {
    ContentView()
}
