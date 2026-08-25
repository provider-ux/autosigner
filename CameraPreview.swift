import SwiftUI
import AVFoundation

struct CameraPreview: NSViewRepresentable {
    var session: AVCaptureSession
    
    class VideoView: NSView {
        var videoLayer: AVCaptureVideoPreviewLayer
        
        init(session: AVCaptureSession) {
            videoLayer = AVCaptureVideoPreviewLayer(session: session)
            super.init(frame: .zero)
            videoLayer.videoGravity = .resizeAspectFill
            self.layer = videoLayer
            self.wantsLayer = true
        }
        
        required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
        
        override func layout() {
            super.layout()
            videoLayer.frame = bounds
        }
    }
    
    func makeNSView(context: Context) -> VideoView {
        return VideoView(session: session)
    }
    
    func updateNSView(_ nsView: VideoView, context: Context) {
        nsView.videoLayer.session = session
    }
}
