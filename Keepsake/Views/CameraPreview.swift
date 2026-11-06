import AVFoundation
import SwiftUI
import UIKit

struct CameraPreview: UIViewRepresentable {
    let session: AVCaptureSession

    func makeUIView(context _: Context) -> PreviewView {
        let view = PreviewView()
        view.videoPreviewLayer.session = session
        view.videoPreviewLayer.videoGravity = .resizeAspectFill
        view.applyPreviewConnection()
        return view
    }

    func updateUIView(_ uiView: PreviewView, context _: Context) {
        uiView.applyPreviewConnection()
    }
}

final class PreviewView: UIView {
    override class var layerClass: AnyClass {
        AVCaptureVideoPreviewLayer.self
    }

    var videoPreviewLayer: AVCaptureVideoPreviewLayer {
        guard let preview = layer as? AVCaptureVideoPreviewLayer else {
            fatalError("Expected AVCaptureVideoPreviewLayer")
        }
        return preview
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        applyPreviewConnection()
    }

    /// The connection appears only after the session is running, so this is applied again from layout.
    func applyPreviewConnection() {
        guard let connection = videoPreviewLayer.connection else { return }
        let portrait: CGFloat = 90
        if connection.isVideoRotationAngleSupported(portrait) {
            connection.videoRotationAngle = portrait
        }
        if connection.isVideoMirroringSupported {
            connection.automaticallyAdjustsVideoMirroring = false
            // Match the movie file, which is saved unmirrored so the other person sees you as they did.
            connection.isVideoMirrored = false
        }
    }
}
