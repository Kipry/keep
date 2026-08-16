//
//  KeepCapture.swift
//  KeepCapture
//
//  Created by Karl-Pierre Kipry on 16.08.26.
//

import ExtensionKit
import Foundation
import LockedCameraCapture
import SwiftUI

@main
struct KeepCapture: LockedCameraCaptureExtension {
    var body: some LockedCameraCaptureExtensionScene {
        LockedCameraCaptureUIScene { session in
            KeepCaptureViewFinder(session: session)
        }
    }
}
