import SwiftUI
import Cocoa
import AVFoundation

struct SignatureCaptureView: View {
    @Environment(\.dismiss) private var dismiss
    @StateObject private var cameraController = CameraController()
    @State private var processedSignature: NSImage?
    var onSave: (NSImage) -> Void
    
    var body: some View {
        VStack(spacing: 20) {
            Text(processedSignature == nil ? "Align Signature in Camera" : "Signature Captured!")
                .font(.headline)
            
            ZStack {
                if let processed = processedSignature {
                    Image(nsImage: processed)
                        .resizable()
                        .scaledToFit()
                        .frame(width: 480, height: 280)
                        .background(Color.gray.opacity(0.15))
                        .cornerRadius(12)
                } else {
                    CameraPreviewRepresentable(cameraController: cameraController)
                        .frame(width: 480, height: 280)
                        .cornerRadius(12)
                }
            }
            
            HStack(spacing: 16) {
                if processedSignature == nil {
                    Button("Cancel") {
                        cameraController.stopSession()
                        dismiss()
                    }
                    
                    Button("Capture Signature") {
                        captureAndProcess()
                    }
                    .buttonStyle(.borderedProminent)
                } else {
                    Button("Retake") {
                        handleRetake()
                    }
                    
                    Button("Save Signature") {
                        if let sig = processedSignature {
                            onSave(sig)
                            cameraController.stopSession()
                            dismiss()
                        }
                    }
                    .buttonStyle(.borderedProminent)
                }
            }
        }
        .padding(24)
        .onAppear {
            cameraController.startSession()
        }
        .onDisappear {
            cameraController.stopSession()
        }
    }
    
    private func captureAndProcess() {
        cameraController.capturePhoto { rawImage in
            guard let raw = rawImage else { return }
            if let cleanSig = VectorSignatureTracer.extractVectorSignature(from: raw) {
                DispatchQueue.main.async {
                    self.processedSignature = cleanSig
                }
            }
        }
    }
    
    private func handleRetake() {
        DispatchQueue.main.async {
            self.processedSignature = nil
            self.cameraController.startSession()
        }
    }
}

struct CameraPreviewRepresentable: NSViewRepresentable {
    @ObservedObject var cameraController: CameraController
    
    func makeNSView(context: Context) -> NSView {
        let view = NSView(frame: NSRect(x: 0, y: 0, width: 480, height: 280))
        cameraController.setupPreviewLayer(in: view)
        return view
    }
    
    func updateNSView(_ nsView: NSView, context: Context) {
        cameraController.updatePreviewFrame(to: nsView.bounds)
    }
}
