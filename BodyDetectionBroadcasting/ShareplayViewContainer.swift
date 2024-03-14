//
//  ShareplayViewController.swift
//  BodyDetectionBroadcasting
//
//  Created by Michael A Edgcumbe on 3/8/24.
//

import SwiftUI
import GroupActivities
import _GroupActivities_UIKit

struct ShareplayViewContainer: UIViewControllerRepresentable {
    @ObservedObject private var shareplayModel:ContentViewShareplayModel
    
    public init(  shareplayModel:ContentViewShareplayModel) {
        self.shareplayModel = shareplayModel
    }
    
    func makeUIViewController(context: Context) -> GroupActivitySharingController {
        let controller = GroupActivitySharingController { () -> DanceCoordinator in
            let activity = DanceCoordinator()
            shareplayModel.coordinator = activity
            return activity
        }
        return controller
    }
    
    func updateUIViewController(_ uiView: GroupActivitySharingController, context: Context) {}
    
}

#Preview {
    ShareplayViewContainer(shareplayModel: ContentViewShareplayModel(useShareplay: true))
}
