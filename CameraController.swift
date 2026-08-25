import Cocoa
import AVFoundation

class CameraController: NSObject, ObservableObject, AVCapturePhotoCaptureDelegate {
    @Published var isAuthorized: Bool = false
    private let session = AVCaptureSession()
    private let output = AVCapturePhotoOutput()
    private var previewLayer: AVCaptureVideoPreviewLayer?
    private var photoCompletion: ((NSImage?) -> Void)?
    
    override init() {
        super.init()
        checkCameraPermissions()
    }
    
    func checkCameraPermissions() {
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            DispatchQueue.main.async { self.isAuthorized = true }
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .video) { granted in
                DispatchQueue.main.async { self.isAuthorized = granted }
            }
        default:
            DispatchQueue.main.async { self.isAuthorized = false }
        }
    }
    
    func startSession() {
        guard !session.isRunning else { return }
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self = self else { return }
            
            if self.session.inputs.isEmpty {
                // Universal macOS device lookup (built-in webcam, external USB, Continuity Camera)
                guard let device = AVCaptureDevice.default(for: .video) ??
                                  AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .unspecified),
                      let input = try? AVCaptureDeviceInput(device: device) else {
                    print("⚠️ Video device unavailable.")
                    return
                }
                
                self.session.beginConfiguration()
                self.session.sessionPreset = .photo
                if self.session.canAddInput(input) { self.session.addInput(input) }
                if self.session.canAddOutput(self.output) { self.session.addOutput(self.output) }
                self.session.commitConfiguration()
            }
            self.session.startRunning()
        }
    }
    
    func stopSession() {
        guard session.isRunning else { return }
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            self?.session.stopRunning()
        }
    }
    
    func setupPreviewLayer(in view: NSView) {
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            view.wantsLayer = true
            
            if self.previewLayer == nil {
                let layer = AVCaptureVideoPreviewLayer(session: self.session)
                layer.videoGravity = .resizeAspectFill
                layer.frame = view.bounds
                view.layer?.addSublayer(layer)
                self.previewLayer = layer
            } else {
                self.previewLayer?.frame = view.bounds
                if let layer = self.previewLayer, layer.superlayer == nil {
                    view.layer?.addSublayer(layer)
                }
            }
        }
    }
    
    func updatePreviewFrame(to bounds: CGRect) {
        DispatchQueue.main.async { [weak self] in
            CATransaction.begin()
            CATransaction.setDisableActions(true)
            self?.previewLayer?.frame = bounds
            CATransaction.commit()
        }
    }
    
    func capturePhoto(completion: @escaping (NSImage?) -> Void) {
        self.photoCompletion = completion
        let settings = AVCapturePhotoSettings()
        output.capturePhoto(with: settings, delegate: self)
    }
    
    func photoOutput(_ output: AVCapturePhotoOutput, didFinishProcessingPhoto photo: AVCapturePhoto, error: Error?) {
        guard let data = photo.fileDataRepresentation(),
              let image = NSImage(data: data) else {
            photoCompletion?(nil)
            return
        }
        photoCompletion?(image)
    }
}
