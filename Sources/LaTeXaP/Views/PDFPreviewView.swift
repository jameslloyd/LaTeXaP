import AppKit
import PDFKit
import SwiftUI

public final class InteractivePDFView: PDFView {
    public var onBackwardSyncClick: ((Int, CGPoint, CGFloat) -> Void)?

    public override func mouseDown(with event: NSEvent) {
        // Command-Click or Double-Click triggers backward SyncTeX jump to source line
        if event.modifierFlags.contains(.command) || event.clickCount == 2 {
            let viewPoint = convert(event.locationInWindow, from: nil)
            if let page = page(for: viewPoint, nearest: true),
               let doc = document {
                let pageIndex = doc.index(for: page) // 0-based
                let pagePoint = convert(viewPoint, to: page)
                let bounds = page.bounds(for: .mediaBox)
                onBackwardSyncClick?(pageIndex + 1, pagePoint, bounds.height)
                if event.modifierFlags.contains(.command) {
                    return
                }
            }
        }
        super.mouseDown(with: event)
    }
}

public struct PDFPreviewContainer: NSViewRepresentable {
    public let pdfURL: URL?
    public let pdfRevision: Int
    @Binding public var forwardSyncBox: SyncTeXBox?
    @Binding public var zoomScale: CGFloat
    public var onBackwardSync: (Int, Double, Double) -> Void

    public init(
        pdfURL: URL?,
        pdfRevision: Int,
        forwardSyncBox: Binding<SyncTeXBox?>,
        zoomScale: Binding<CGFloat>,
        onBackwardSync: @escaping (Int, Double, Double) -> Void
    ) {
        self.pdfURL = pdfURL
        self.pdfRevision = pdfRevision
        self._forwardSyncBox = forwardSyncBox
        self._zoomScale = zoomScale
        self.onBackwardSync = onBackwardSync
    }

    public func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    public func makeNSView(context: Context) -> InteractivePDFView {
        let pdfView = InteractivePDFView()
        pdfView.autoScales = true
        pdfView.displayMode = .singlePageContinuous
        pdfView.displaysPageBreaks = true
        pdfView.backgroundColor = NSColor.underPageBackgroundColor

        pdfView.onBackwardSyncClick = { pageNumber, pagePoint, pageHeight in
            // Convert bottom-left PDFKit pagePoint to top-left SyncTeX coordinates
            let xPt = Double(pagePoint.x)
            let yTopPt = Double(pageHeight - pagePoint.y)
            onBackwardSync(pageNumber, xPt, yTopPt)
        }

        return pdfView
    }

    public func updateNSView(_ pdfView: InteractivePDFView, context: Context) {
        pdfView.onBackwardSyncClick = { pageNumber, pagePoint, pageHeight in
            let xPt = Double(pagePoint.x)
            let yTopPt = Double(pageHeight - pagePoint.y)
            onBackwardSync(pageNumber, xPt, yTopPt)
        }

        if context.coordinator.lastLoadedRevision != pdfRevision, let url = pdfURL {
            // Preserve current scroll position & page across live rebuilds
            let previousPageIndex: Int? = {
                guard let currentDoc = pdfView.document,
                      let currentPage = pdfView.currentPage else { return nil }
                return currentDoc.index(for: currentPage)
            }()
            let previousScrollOrigin = pdfView.documentView?.enclosingScrollView?.contentView.bounds.origin

            if let newDoc = PDFDocument(url: url) {
                pdfView.document = newDoc
                context.coordinator.lastLoadedRevision = pdfRevision

                if let prevIdx = previousPageIndex, prevIdx < newDoc.pageCount, let targetPage = newDoc.page(at: prevIdx) {
                    pdfView.go(to: targetPage)
                }
                if let origin = previousScrollOrigin,
                   let clipView = pdfView.documentView?.enclosingScrollView?.contentView {
                    clipView.scroll(to: origin)
                    pdfView.enclosingScrollView?.reflectScrolledClipView(clipView)
                }
            }
        }

        if abs(pdfView.scaleFactor - zoomScale) > 0.02 && !pdfView.autoScales {
            pdfView.scaleFactor = zoomScale
        }

        if let box = forwardSyncBox, let doc = pdfView.document {
            let pageIndex = max(0, min(doc.pageCount - 1, box.page - 1))
            if let page = doc.page(at: pageIndex) {
                let pageBounds = page.bounds(for: .mediaBox)
                let pdfY = pageBounds.height - CGFloat(box.yTopPt) - CGFloat(box.depthPt)
                let rect = NSRect(
                    x: max(0, CGFloat(box.xPt) - 6),
                    y: max(0, pdfY - 4),
                    width: max(60, CGFloat(box.widthPt) + 12),
                    height: max(18, CGFloat(box.heightPt + box.depthPt) + 8)
                )

                // Remove any previous temporary SyncTeX highlight annotations
                if let oldAnnotation = context.coordinator.activeHighlightAnnotation,
                   let oldPage = context.coordinator.activeHighlightPage {
                    oldPage.removeAnnotation(oldAnnotation)
                }

                let highlight = PDFAnnotation(bounds: rect, forType: .highlight, withProperties: nil)
                highlight.color = NSColor.systemYellow.withAlphaComponent(0.55)
                page.addAnnotation(highlight)
                context.coordinator.activeHighlightAnnotation = highlight
                context.coordinator.activeHighlightPage = page

                pdfView.go(to: rect, on: page)

                DispatchQueue.main.async {
                    self.forwardSyncBox = nil
                }

                // Fade/remove temporary highlight after 1.8 seconds
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.8) {
                    if context.coordinator.activeHighlightAnnotation === highlight {
                        page.removeAnnotation(highlight)
                        context.coordinator.activeHighlightAnnotation = nil
                    }
                }
            }
        }
    }

    public final class Coordinator {
        var lastLoadedRevision: Int = -1
        var activeHighlightAnnotation: PDFAnnotation?
        weak var activeHighlightPage: PDFPage?
    }
}
