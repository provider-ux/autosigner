import SwiftUI
import PDFKit
import AppKit

struct AnnotationSnapshot {
    let pageIndex: Int
    let bounds: CGRect
    let profile: UserProfile
    let timestamp: String
}

class PDFUndoController: ObservableObject {
    @Published var canUndo = false
    @Published var canRedo = false
    
    private var undoStack: [[AnnotationSnapshot]] = []
    private var redoStack: [[AnnotationSnapshot]] = []
    
    func recordState(from document: PDFDocument?) {
        guard let doc = document else { return }
        var currentSnapshots: [AnnotationSnapshot] = []
        
        for i in 0..<doc.pageCount {
            guard let page = doc.page(at: i) else { continue }
            let annotationsSnapshot = Array(page.annotations)
            for annotation in annotationsSnapshot {
                if let sig = annotation as? CleanSignatureAnnotation {
                    currentSnapshots.append(AnnotationSnapshot(
                        pageIndex: i,
                        bounds: sig.bounds,
                        profile: sig.profile,
                        timestamp: sig.timestampString
                    ))
                }
            }
        }
        
        undoStack.append(currentSnapshots)
        redoStack.removeAll()
        updateFlags()
    }
    
    func undo(on document: PDFDocument?) {
        guard let doc = document, !undoStack.isEmpty else { return }
        
        var currentSnapshots: [AnnotationSnapshot] = []
        for i in 0..<doc.pageCount {
            guard let page = doc.page(at: i) else { continue }
            let annotationsSnapshot = Array(page.annotations)
            for annotation in annotationsSnapshot {
                if let sig = annotation as? CleanSignatureAnnotation {
                    currentSnapshots.append(AnnotationSnapshot(
                        pageIndex: i,
                        bounds: sig.bounds,
                        profile: sig.profile,
                        timestamp: sig.timestampString
                    ))
                }
            }
        }
        
        redoStack.append(currentSnapshots)
        let previousSnapshots = undoStack.removeLast()
        restore(snapshots: previousSnapshots, to: doc)
        updateFlags()
    }
    
    func redo(on document: PDFDocument?) {
        guard let doc = document, !redoStack.isEmpty else { return }
        
        var currentSnapshots: [AnnotationSnapshot] = []
        for i in 0..<doc.pageCount {
            guard let page = doc.page(at: i) else { continue }
            let annotationsSnapshot = Array(page.annotations)
            for annotation in annotationsSnapshot {
                if let sig = annotation as? CleanSignatureAnnotation {
                    currentSnapshots.append(AnnotationSnapshot(
                        pageIndex: i,
                        bounds: sig.bounds,
                        profile: sig.profile,
                        timestamp: sig.timestampString
                    ))
                }
            }
        }
        
        undoStack.append(currentSnapshots)
        let nextSnapshots = redoStack.removeLast()
        restore(snapshots: nextSnapshots, to: doc)
        updateFlags()
    }
    
    func clearAll(on document: PDFDocument?) {
        guard let doc = document else { return }
        recordState(from: doc)
        
        for i in 0..<doc.pageCount {
            guard let page = doc.page(at: i) else { continue }
            while let annotation = page.annotations.first(where: { $0 is CleanSignatureAnnotation }) {
                page.removeAnnotation(annotation)
            }
        }
    }
    
    private func restore(snapshots: [AnnotationSnapshot], to doc: PDFDocument) {
        for i in 0..<doc.pageCount {
            guard let page = doc.page(at: i) else { continue }
            while let annotation = page.annotations.first(where: { $0 is CleanSignatureAnnotation }) {
                page.removeAnnotation(annotation)
            }
        }
        
        for snap in snapshots {
            guard snap.pageIndex < doc.pageCount,
                  let page = doc.page(at: snap.pageIndex) else { continue }
            let annotation = CleanSignatureAnnotation(bounds: snap.bounds, profile: snap.profile, timestamp: snap.timestamp)
            page.addAnnotation(annotation)
        }
    }
    
    private func updateFlags() {
        canUndo = !undoStack.isEmpty
        canRedo = !redoStack.isEmpty
    }
}

struct PDFViewer: NSViewRepresentable {
    @Binding var document: PDFDocument?
    @Binding var isManualMode: Bool
    var activeProfile: UserProfile?
    @ObservedObject var undoController: PDFUndoController
    
    func makeNSView(context: Context) -> MovablePDFView {
        let pdfView = MovablePDFView()
        pdfView.autoScales = true
        pdfView.displayMode = .singlePageContinuous
        pdfView.displayDirection = .vertical
        pdfView.undoController = undoController
        
        let clickGesture = NSClickGestureRecognizer(
            target: context.coordinator,
            action: #selector(Coordinator.handlePageClick(_:))
        )
        pdfView.addGestureRecognizer(clickGesture)
        
        return pdfView
    }
    
    func updateNSView(_ nsView: MovablePDFView, context: Context) {
        context.coordinator.parent = self
        
        if nsView.document != document {
            nsView.document = document
        }
        nsView.undoController = undoController
        
        if isManualMode {
            NSCursor.crosshair.set()
        } else {
            NSCursor.arrow.set()
        }
    }
    
    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }
    
    class Coordinator: NSObject {
        var parent: PDFViewer
        
        init(_ parent: PDFViewer) {
            self.parent = parent
        }
        
        @objc func handlePageClick(_ sender: NSClickGestureRecognizer) {
            guard let pdfView = sender.view as? MovablePDFView else { return }
            pdfView.currentSelection = nil
            
            guard parent.isManualMode,
                  let profile = parent.activeProfile,
                  let doc = pdfView.document else { return }
            
            let locationInView = sender.location(in: pdfView)
            guard let page = pdfView.page(for: locationInView, nearest: false) else { return }
            let locationOnPage = pdfView.convert(locationInView, to: page)
            
            parent.undoController.recordState(from: doc)
            
            let signatureRect = CGRect(
                x: locationOnPage.x - 180,
                y: locationOnPage.y - 15,
                width: 380,
                height: 90
            )
            
            let annotation = CleanSignatureAnnotation(bounds: signatureRect, profile: profile)
            page.addAnnotation(annotation)
            
            parent.isManualMode = false
        }
    }
}

enum DragAction {
    case move(offset: CGPoint)
    case resize(startSize: CGSize, startPoint: CGPoint)
}

class MovablePDFView: PDFView {
    var undoController: PDFUndoController?
    private var activeAnnotation: CleanSignatureAnnotation?
    private var dragAction: DragAction?
    
    override var acceptsFirstResponder: Bool { true }
    
    override func mouseDown(with event: NSEvent) {
        window?.makeFirstResponder(self)
        let locationInView = convert(event.locationInWindow, from: nil)
        guard let page = page(for: locationInView, nearest: false) else {
            deselectAll()
            super.mouseDown(with: event)
            return
        }
        
        let locationOnPage = convert(locationInView, to: page)
        
        let annotationsSnapshot = Array(page.annotations)
        if let annotation = annotationsSnapshot.first(where: { ($0 as? CleanSignatureAnnotation)?.bounds.contains(locationOnPage) == true }) as? CleanSignatureAnnotation {
            
            deselectAll()
            annotation.isSelected = true
            activeAnnotation = annotation
            needsDisplay = true
            currentSelection = nil
            
            if let doc = document {
                undoController?.recordState(from: doc)
            }
            
            let bounds = annotation.bounds
            let handleSize = max(18.0, bounds.height * 0.2)
            let handleRect = CGRect(x: bounds.maxX - handleSize, y: bounds.maxY - handleSize, width: handleSize, height: handleSize)
            
            if handleRect.contains(locationOnPage) {
                dragAction = .resize(startSize: bounds.size, startPoint: locationOnPage)
            } else {
                dragAction = .move(offset: CGPoint(x: locationOnPage.x - bounds.origin.x, y: locationOnPage.y - bounds.origin.y))
            }
            return
        }
        
        deselectAll()
        super.mouseDown(with: event)
    }
    
    override func keyDown(with event: NSEvent) {
        if event.keyCode == 51 || event.keyCode == 117 {
            if let annotation = activeAnnotation,
               let page = annotation.page,
               let doc = document {
                
                undoController?.recordState(from: doc)
                page.removeAnnotation(annotation)
                activeAnnotation = nil
                needsDisplay = true
                return
            }
        }
        super.keyDown(with: event)
    }
    
    override func mouseDragged(with event: NSEvent) {
        if let annotation = activeAnnotation,
           let page = annotation.page,
           let action = dragAction {
            
            let locationInView = convert(event.locationInWindow, from: nil)
            let locationOnPage = convert(locationInView, to: page)
            
            switch action {
            case .move(let offset):
                var newBounds = annotation.bounds
                newBounds.origin = CGPoint(
                    x: locationOnPage.x - offset.x,
                    y: locationOnPage.y - offset.y
                )
                annotation.bounds = newBounds
                
            case .resize(let startSize, let startPoint):
                let deltaX = locationOnPage.x - startPoint.x
                let deltaY = locationOnPage.y - startPoint.y
                let newWidth = max(140, startSize.width + deltaX)
                let newHeight = max(45, startSize.height + deltaY)
                
                annotation.bounds = CGRect(
                    origin: annotation.bounds.origin,
                    size: CGSize(width: newWidth, height: newHeight)
                )
            }
            
            needsDisplay = true
            return
        }
        
        super.mouseDragged(with: event)
    }
    
    override func mouseUp(with event: NSEvent) {
        if dragAction != nil {
            dragAction = nil
            return
        }
        super.mouseUp(with: event)
    }
    
    private func deselectAll() {
        guard let doc = document else { return }
        for i in 0..<doc.pageCount {
            guard let page = doc.page(at: i) else { continue }
            let annotationsSnapshot = Array(page.annotations)
            for ann in annotationsSnapshot {
                if let sig = ann as? CleanSignatureAnnotation, sig.isSelected {
                    sig.isSelected = false
                }
            }
        }
        activeAnnotation = nil
        needsDisplay = true
    }
}
