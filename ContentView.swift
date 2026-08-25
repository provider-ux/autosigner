import SwiftUI
import PDFKit
import UniformTypeIdentifiers

struct ContentView: View {
    @State private var document: PDFDocument?
    @State private var isManualMode: Bool = false
    @State private var showCameraSheet: Bool = false
    @State private var statusMessage: String?
    
    @State private var profiles: [UserProfile] = [
        UserProfile(printedName: "Carlo Domingo, NP (FPA)", signatureImage: nil)
    ]
    @State private var selectedProfileID: UUID?
    
    @StateObject private var undoController = PDFUndoController()
    private let autoSigner = AutoSigner()
    
    var activeProfile: UserProfile? {
        if let id = selectedProfileID {
            return profiles.first(where: { $0.id == id })
        }
        return profiles.first
    }
    
    var body: some View {
        VStack(spacing: 0) {
            // Top Action Toolbar
            HStack(spacing: 10) {
                Button(action: openPDF) {
                    Label("Open PDF", systemImage: "doc.badge.plus")
                }
                
                Picker("", selection: Binding(
                    get: { selectedProfileID ?? profiles.first?.id ?? UUID() },
                    set: { selectedProfileID = $0 }
                )) {
                    ForEach(profiles) { profile in
                        Text(profile.printedName).tag(profile.id)
                    }
                }
                .frame(width: 180)
                
                Button(action: { showCameraSheet = true }) {
                    Label("Scan Signature", systemImage: "camera")
                }
                
                if activeProfile?.signatureImage != nil {
                    Button("Clear Signature") {
                        clearActiveSignature()
                    }
                }
                
                Divider().frame(height: 20)
                
                Button(action: performAutoSign) {
                    Label("Auto-Sign", systemImage: "signature")
                }
                .buttonStyle(.borderedProminent)
                .disabled(document == nil || activeProfile?.signatureImage == nil)
                
                // BATCH AUTO-SIGN BUTTON
                Button(action: batchSignPDFs) {
                    Label("Batch Sign PDFs", systemImage: "doc.on.doc")
                }
                .disabled(activeProfile?.signatureImage == nil)
                .help("Select multiple PDFs to auto-sign all at once")
                
                Button(action: { isManualMode.toggle() }) {
                    Label(isManualMode ? "Click Page..." : "Manual Drop Sign", systemImage: "hand.tap")
                }
                .tint(isManualMode ? .orange : .accentColor)
                .disabled(document == nil || activeProfile?.signatureImage == nil)
                
                Divider().frame(height: 20)
                
                // History Actions
                HStack(spacing: 6) {
                    Button(action: { undoController.undo(on: document) }) {
                        Image(systemName: "arrow.uturn.backward")
                    }
                    .disabled(!undoController.canUndo)
                    .help("Undo")
                    
                    Button(action: { undoController.redo(on: document) }) {
                        Image(systemName: "arrow.uturn.forward")
                    }
                    .disabled(!undoController.canRedo)
                    .help("Redo")
                    
                    Button(action: { undoController.clearAll(on: document) }) {
                        Image(systemName: "trash")
                    }
                    .disabled(document == nil)
                    .help("Clear All PDF Signatures")
                }
            }
            .padding(10)
            .background(Color(NSColor.windowBackgroundColor))
            
            if let msg = statusMessage {
                Text(msg)
                    .font(.caption)
                    .bold()
                    .foregroundColor(.white)
                    .padding(.vertical, 4)
                    .frame(maxWidth: .infinity)
                    .background(Color.accentColor)
            }
            
            Divider()
            
            // PDF Viewing Canvas
            ZStack {
                if document != nil {
                    PDFViewer(
                        document: $document,
                        isManualMode: $isManualMode,
                        activeProfile: activeProfile,
                        undoController: undoController
                    )
                } else {
                    VStack(spacing: 12) {
                        Image(systemName: "doc.richtext")
                            .font(.system(size: 48))
                            .foregroundColor(.secondary)
                        Text("Open a PDF or Batch Sign multiple documents")
                            .font(.headline)
                            .foregroundColor(.secondary)
                        HStack(spacing: 12) {
                            Button("Open PDF", action: openPDF)
                                .buttonStyle(.borderedProminent)
                            Button("Batch Sign PDFs", action: batchSignPDFs)
                        }
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
        }
        .sheet(isPresented: $showCameraSheet) {
            SignatureCaptureView { capturedNSImage in
                saveCapturedSignature(capturedNSImage)
            }
        }
        .onAppear {
            if selectedProfileID == nil {
                selectedProfileID = profiles.first?.id
            }
        }
    }
    
    private func openPDF() {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        panel.allowedContentTypes = [.pdf]
        
        if panel.runModal() == .OK, let url = panel.url {
            self.document = PDFDocument(url: url)
        }
    }
    
    // Batch file selector and execution handler
    private func batchSignPDFs() {
        guard let profile = activeProfile, profile.signatureImage != nil else { return }
        
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        panel.allowedContentTypes = [.pdf]
        panel.prompt = "Batch Sign PDFs"
        
        if panel.runModal() == .OK {
            let urls = panel.urls
            let signedCount = autoSigner.batchSign(urls: urls, profile: profile)
            
            showStatus("Successfully batch signed \(signedCount) PDF(s)! Saved with '_signed.pdf' suffix.")
        }
    }
    
    private func saveCapturedSignature(_ image: NSImage) {
        guard let currentID = activeProfile?.id,
              let index = profiles.firstIndex(where: { $0.id == currentID }) else { return }
        
        profiles[index].signatureImage = image
    }
    
    private func clearActiveSignature() {
        guard let currentID = activeProfile?.id,
              let index = profiles.firstIndex(where: { $0.id == currentID }) else { return }
        
        profiles[index].signatureImage = nil
    }
    
    private func performAutoSign() {
        guard let doc = document, let profile = activeProfile else { return }
        undoController.recordState(from: doc)
        autoSigner.applySignatures(to: doc, profile: profile)
    }
    
    private func showStatus(_ text: String) {
        statusMessage = text
        DispatchQueue.main.asyncAfter(deadline: .now() + 4.0) {
            if statusMessage == text { statusMessage = nil }
        }
    }
}
