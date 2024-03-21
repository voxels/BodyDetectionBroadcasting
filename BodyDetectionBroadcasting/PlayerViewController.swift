//
//  PlayerViewController.swift
//  BodyDetectionBroadcasting
//
//  Created by Michael A Edgcumbe on 3/15/24.
//


import AVKit
import SwiftUI

// This view is a SwiftUI wrapper over `AVPlayerViewController`.
struct PlayerViewController: UIViewControllerRepresentable {
    
    @Binding public var model:PlayerModel

    func makeUIViewController(context: Context) -> AVPlayerViewController {
        
        let controller = model.makePlayerViewController()
        controller.videoGravity = .resizeAspect
        return controller
        
    }
    
    func updateUIViewController(_ uiViewController: AVPlayerViewController, context: Context) {
        
    }
    
    static func dismantleUIViewController(
        _ uiViewController: Self.UIViewControllerType,
        coordinator: Self.Coordinator
    ){
        uiViewController.player?.replaceCurrentItem(with: nil)
        print("Dismantled")
    }
}
