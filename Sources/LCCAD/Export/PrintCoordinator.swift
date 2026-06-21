import AppKit
import CoreGraphics
import Foundation

// MARK: - Unit Conversion

/// Conversion constants between millimeters and PostScript points.
/// 1 inch = 25.4 mm, 1 inch = 72 points, so 1 mm = 72/25.4 points.
private let pointsPerMM: CGFloat = 72.0 / 25.4  // ~2.8346

/// Convert millimeters to PostScript points.
private func mmToPoints(_ mm: CGFloat) -> CGFloat {
    mm * pointsPerMM
}

// MARK: - Print Coordinator

@MainActor
enum PrintCoordinator {

    /// Print the document at real size (1:1) with optional tile printing.
    static func printDocument(_ document: DocumentData, from window: NSWindow?) {
        // Pre-fetch all calibrations so the NSView doesn't need @MainActor access at draw time
        let calibrations = PrinterCalibrationStore.shared.calibrations
        let view = PrintableDocumentView(document: document, calibrations: calibrations)

        let printInfo = NSPrintInfo.shared.copy() as! NSPrintInfo
        printInfo.horizontalPagination = .automatic
        printInfo.verticalPagination = .automatic
        printInfo.isHorizontallyCentered = false
        printInfo.isVerticallyCentered = false
        printInfo.scalingFactor = 1.0  // Ensure no OS-level scaling

        let pages = document.settings.pageLayout.pages
        let layout = document.settings.pageLayout
        if !layout.pages.isEmpty {
            // Page-based: apply the layout's paper size and orientation to print settings.
            let size = layout.effectivePageSize
            printInfo.paperSize = NSSize(width: mmToPoints(size.width), height: mmToPoints(size.height))
            printInfo.orientation = layout.orientation == .landscape ? .landscape : .portrait

            // Margins to 0 so the full paper area is available and
            // page.origin maps to paper origin.
            printInfo.topMargin = 0
            printInfo.bottomMargin = 0
            printInfo.leftMargin = 0
            printInfo.rightMargin = 0
        } else {
            // Auto-tile: use 10mm margins for alignment marks + gluing overlap
            let margin = mmToPoints(10)
            printInfo.topMargin = margin
            printInfo.bottomMargin = margin
            printInfo.leftMargin = margin
            printInfo.rightMargin = margin
        }

        let op = NSPrintOperation(view: view, printInfo: printInfo)
        op.showsPrintPanel = true
        op.showsProgressPanel = true

        if let window {
            op.runModal(for: window, delegate: nil, didRun: nil, contextInfo: nil)
        } else {
            op.run()
        }
    }

    /// Print a calibration test page with a 100mm square.
    /// If the selected printer has a calibration profile, the correction is applied
    /// so the user can verify the calibration is working correctly.
    static func printCalibrationPage(from window: NSWindow?) {
        let calibrations = PrinterCalibrationStore.shared.calibrations
        let view = CalibrationTestPageView(calibrations: calibrations)

        let printInfo = NSPrintInfo.shared.copy() as! NSPrintInfo
        printInfo.horizontalPagination = .automatic
        printInfo.verticalPagination = .automatic
        printInfo.isHorizontallyCentered = true
        printInfo.isVerticallyCentered = true
        printInfo.scalingFactor = 1.0  // Ensure no OS-level scaling

        let margin = mmToPoints(15)
        printInfo.topMargin = margin
        printInfo.bottomMargin = margin
        printInfo.leftMargin = margin
        printInfo.rightMargin = margin

        let op = NSPrintOperation(view: view, printInfo: printInfo)
        op.showsPrintPanel = true
        op.showsProgressPanel = true

        if let window {
            op.runModal(for: window, delegate: nil, didRun: nil, contextInfo: nil)
        } else {
            op.run()
        }
    }
}

// MARK: - Printable Document View (NSView for NSPrintOperation)

private class PrintableDocumentView: NSView {
    private let document: DocumentData
    private let calibrations: [PrinterCalibration]
    private var tileColumns: Int = 1
    private var tileRows: Int = 1
    private var contentBounds: CGRect = .zero  // in mm
    private var printableAreaPerPage: CGSize = .zero  // in points
    private let overlapMM: CGFloat = 10  // overlap between tiles for alignment
    private let alignMarkLengthMM: CGFloat = 5
    private var usePageLayout: Bool = false
    private var layoutPages: [PrintPage] = []

    init(document: DocumentData, calibrations: [PrinterCalibration]) {
        self.document = document
        self.calibrations = calibrations
        super.init(frame: .zero)
        calculateLayout()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override var isFlipped: Bool { true }

    private func calculateLayout() {
        let pages = document.settings.pageLayout.pages
        if !pages.isEmpty {
            calculatePageBasedLayout(pages)
        } else {
            calculateAutoTileLayout()
        }
    }

    private func calculatePageBasedLayout(_ pages: [PrintPage]) {
        usePageLayout = true
        layoutPages = pages

        let pageSize = document.settings.pageLayout.effectivePageSize
        let paperSizePt = NSSize(width: mmToPoints(pageSize.width),
                                  height: mmToPoints(pageSize.height))
        printableAreaPerPage = paperSizePt

        let totalWidth = paperSizePt.width
        let totalHeight = paperSizePt.height * CGFloat(pages.count)
        self.frame = NSRect(x: 0, y: 0, width: totalWidth, height: totalHeight)
    }

    private func calculateAutoTileLayout() {
        usePageLayout = false

        // Compute bounding box of all visible shapes (in mm)
        contentBounds = computeBoundingBox()

        // Add margin around content (5mm)
        let contentMarginMM: CGFloat = 5
        contentBounds = contentBounds.insetBy(dx: -contentMarginMM, dy: -contentMarginMM)

        // Default to current paper size for layout calculation
        let printInfo = NSPrintInfo.shared
        let paperSize = printInfo.paperSize
        let printableArea = CGSize(
            width: paperSize.width - printInfo.leftMargin - printInfo.rightMargin,
            height: paperSize.height - printInfo.topMargin - printInfo.bottomMargin
        )
        printableAreaPerPage = printableArea

        // Convert content size to points
        let contentWidthPt = mmToPoints(contentBounds.width)
        let contentHeightPt = mmToPoints(contentBounds.height)

        // Calculate overlap in points
        let overlapPt = mmToPoints(overlapMM)

        // Calculate tile count
        if contentWidthPt <= printableArea.width {
            tileColumns = 1
        } else {
            let effectiveWidth = printableArea.width - overlapPt
            tileColumns = max(1, Int(ceil((contentWidthPt - overlapPt) / effectiveWidth)))
        }

        if contentHeightPt <= printableArea.height {
            tileRows = 1
        } else {
            let effectiveHeight = printableArea.height - overlapPt
            tileRows = max(1, Int(ceil((contentHeightPt - overlapPt) / effectiveHeight)))
        }

        // Set the view frame to encompass all pages
        let totalWidth = printableArea.width
        let totalHeight = printableArea.height * CGFloat(tileRows * tileColumns)
        self.frame = NSRect(x: 0, y: 0, width: totalWidth, height: totalHeight)
    }

    // MARK: - Pagination

    override func knowsPageRange(_ range: NSRangePointer) -> Bool {
        let count = usePageLayout ? layoutPages.count : tileRows * tileColumns
        range.pointee = NSRange(location: 1, length: max(1, count))
        return true
    }

    override func rectForPage(_ page: Int) -> NSRect {
        let pageIndex = page - 1
        let pageWidth = printableAreaPerPage.width
        let pageHeight = printableAreaPerPage.height
        return NSRect(
            x: 0,
            y: CGFloat(pageIndex) * pageHeight,
            width: pageWidth,
            height: pageHeight
        )
    }

    // MARK: - Drawing

    override func draw(_ dirtyRect: NSRect) {
        guard let context = NSGraphicsContext.current?.cgContext else { return }

        if usePageLayout {
            drawPageBased(dirtyRect, context: context)
        } else {
            drawAutoTile(dirtyRect, context: context)
        }
    }

    private func drawPageBased(_ dirtyRect: NSRect, context: CGContext) {
        let pageHeight = printableAreaPerPage.height
        let pageIndex = pageHeight > 0 ? Int(dirtyRect.origin.y / pageHeight) : 0
        guard pageIndex < layoutPages.count else { return }

        let page = layoutPages[pageIndex]

        context.saveGState()
        context.clip(to: dirtyRect)

        // White background
        context.setFillColor(NSColor.white.cgColor)
        context.fill(dirtyRect)

        // Get calibration
        let calibration = currentPrinterCalibration()
        let calScaleX = CGFloat(calibration?.scaleX ?? 1.0)
        let calScaleY = CGFloat(calibration?.scaleY ?? 1.0)

        // Page frame = paper. page.origin in world coords maps to (0,0)
        // on the physical paper. Margins are set to 0 in printDocument so
        // dirtyRect covers the full paper area.
        context.translateBy(x: dirtyRect.origin.x, y: dirtyRect.origin.y)

        let scaleX = pointsPerMM * calScaleX
        let scaleY = pointsPerMM * calScaleY
        context.scaleBy(x: scaleX, y: scaleY)

        // Offset so page.origin maps to paper origin
        context.translateBy(x: -page.origin.x, y: -page.origin.y)

        // Clip to page frame in world coords
        let pageFrame = document.settings.pageLayout.pageFrame(for: page)
        context.clip(to: pageFrame)

        drawShapes(in: context)

        context.restoreGState()

        // Page label
        let label = "Page \(pageIndex + 1)/\(layoutPages.count)"
        let font = NSFont.systemFont(ofSize: 8)
        let attrs: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: NSColor.gray]
        let attrStr = NSAttributedString(string: label, attributes: attrs)
        let textSize = attrStr.size()
        attrStr.draw(in: NSRect(
            x: dirtyRect.maxX - textSize.width - 10,
            y: dirtyRect.maxY - textSize.height - 5,
            width: textSize.width, height: textSize.height
        ))
    }

    private func drawAutoTile(_ dirtyRect: NSRect, context: CGContext) {
        // Determine which page we are drawing
        let pageHeight = printableAreaPerPage.height
        let pageIndex: Int
        if pageHeight > 0 {
            pageIndex = Int(dirtyRect.origin.y / pageHeight)
        } else {
            pageIndex = 0
        }
        let col = tileColumns > 1 ? pageIndex % tileColumns : 0
        let row = tileColumns > 0 ? pageIndex / tileColumns : 0

        context.saveGState()

        // Clip to the page area
        context.clip(to: dirtyRect)

        // White background
        context.setFillColor(NSColor.white.cgColor)
        context.fill(dirtyRect)

        // Get calibration for current printer
        let calibration = currentPrinterCalibration()
        let calScaleX = CGFloat(calibration?.scaleX ?? 1.0)
        let calScaleY = CGFloat(calibration?.scaleY ?? 1.0)

        // Calculate tile offset
        let overlapPt = mmToPoints(overlapMM)
        let effectiveWidthPt = printableAreaPerPage.width - overlapPt
        let effectiveHeightPt = printableAreaPerPage.height - overlapPt
        let tileOffsetXPt = CGFloat(col) * effectiveWidthPt
        let tileOffsetYPt = CGFloat(row) * effectiveHeightPt

        // Transform: translate to page origin, then apply mm-to-points scaling
        // with calibration correction, then offset for the content bounds and tile
        context.translateBy(x: dirtyRect.origin.x, y: dirtyRect.origin.y)

        // Apply calibration-corrected mm-to-points conversion
        let scaleX = pointsPerMM * calScaleX
        let scaleY = pointsPerMM * calScaleY
        context.scaleBy(x: scaleX, y: scaleY)

        // Offset to account for content bounds origin and tile position
        let offsetXMM = contentBounds.origin.x + tileOffsetXPt / scaleX
        let offsetYMM = contentBounds.origin.y + tileOffsetYPt / scaleY
        context.translateBy(x: -offsetXMM, y: -offsetYMM)

        // Draw all visible shapes
        drawShapes(in: context)

        // Restore and draw alignment marks on top (in points, not mm)
        context.restoreGState()

        if tileRows * tileColumns > 1 {
            drawAlignmentMarks(in: context, dirtyRect: dirtyRect, row: row, col: col)
            drawPageLabel(in: context, dirtyRect: dirtyRect, row: row, col: col)
        }
    }

    // MARK: - Shape Drawing (in mm coordinates)

    private func drawShapes(in context: CGContext) {
        for layer in document.layers where layer.isVisible {
            for shape in layer.shapes {
                drawShape(shape, in: context)
            }

            // Draw stitch holes
            if !layer.stitchLines.isEmpty {
                let stitchColor = NSColor(red: 0.831, green: 0.647, blue: 0.455, alpha: 1.0)
                context.setFillColor(stitchColor.cgColor)
                for stitchLine in layer.stitchLines {
                    let iron = document.prickingIrons.first { $0.id == stitchLine.ironId }
                    let r = (iron?.holeSize ?? 1.0) / 2
                    for hole in stitchLine.holes {
                        let rect = CGRect(
                            x: hole.position.x - r,
                            y: hole.position.y - r,
                            width: r * 2,
                            height: r * 2
                        )
                        context.fillEllipse(in: rect)
                    }
                }
            }
        }
    }

    private func drawShape(_ shape: AnyShape, in context: CGContext) {
        let sc = shape.stroke.color
        let strokeColor = NSColor(red: sc.r, green: sc.g, blue: sc.b, alpha: sc.a)
        context.setStrokeColor(strokeColor.cgColor)
        context.setFillColor(NSColor.clear.cgColor)
        context.setLineWidth(shape.stroke.width)  // in mm, transform handles conversion
        if let pattern = shape.stroke.dashPattern, !pattern.isEmpty {
            context.setLineDash(phase: 0, lengths: pattern)
        } else {
            context.setLineDash(phase: 0, lengths: [])
        }

        switch shape {
        case .line(let line):
            context.move(to: line.startPoint)
            context.addLine(to: line.endPoint)
            context.strokePath()

        case .rectangle(let rect):
            let unrotated = CGRect(origin: rect.origin, size: rect.size)
            if rect.rotation != 0 {
                context.saveGState()
                let c = rect.unrotatedCenter
                context.translateBy(x: c.x, y: c.y)
                context.rotate(by: rect.rotation)
                context.translateBy(x: -c.x, y: -c.y)
            }
            if rect.cornerRadius > 0 {
                let path = CGPath(roundedRect: unrotated, cornerWidth: rect.cornerRadius, cornerHeight: rect.cornerRadius, transform: nil)
                context.addPath(path)
            } else {
                context.addRect(unrotated)
            }
            context.strokePath()
            if rect.rotation != 0 {
                context.restoreGState()
            }

        case .ellipse(let ellipse):
            if ellipse.rotation != 0 {
                context.saveGState()
                let c = ellipse.center
                context.translateBy(x: c.x, y: c.y)
                context.rotate(by: ellipse.rotation)
                context.translateBy(x: -c.x, y: -c.y)
            }
            context.addEllipse(in: ellipse.unrotatedBounds)
            context.strokePath()
            if ellipse.rotation != 0 {
                context.restoreGState()
            }

        case .arc(let arc):
            context.addArc(center: arc.center, radius: arc.radius,
                          startAngle: arc.startAngle, endAngle: arc.endAngle,
                          clockwise: arc.clockwise)
            context.strokePath()

        case .dot(let dot):
            context.setFillColor(strokeColor.cgColor)
            let r = dot.radius
            context.fillEllipse(in: CGRect(x: dot.position.x - r, y: dot.position.y - r,
                                           width: r * 2, height: r * 2))

        case .bezier(let bezier):
            guard bezier.points.count >= 2 else { return }
            context.move(to: bezier.points[0].point)
            let segCount = bezier.isClosed ? bezier.points.count : bezier.points.count - 1
            for i in 0..<segCount {
                let j = (i + 1) % bezier.points.count
                context.addCurve(to: bezier.points[j].point,
                                control1: bezier.points[i].controlOut,
                                control2: bezier.points[j].controlIn)
            }
            if bezier.isClosed { context.closePath() }
            context.strokePath()

        case .text(let text):
            let resolvedFont = text.resolvedNSFont
            let font = NSFont(name: resolvedFont.fontName, size: text.fontSize)
                ?? NSFont.systemFont(ofSize: text.fontSize)
            let color = NSColor(red: sc.r, green: sc.g, blue: sc.b, alpha: sc.a)
            let paragraphStyle = NSMutableParagraphStyle()
            switch text.textAlignment {
            case .left: paragraphStyle.alignment = .left
            case .center: paragraphStyle.alignment = .center
            case .right: paragraphStyle.alignment = .right
            }
            let attrs: [NSAttributedString.Key: Any] = [
                .font: font,
                .foregroundColor: color,
                .paragraphStyle: paragraphStyle
            ]
            let attrStr = NSAttributedString(string: text.content, attributes: attrs)

            // Draw text using NSAttributedString (handles flipped coordinates)
            // Since isFlipped = true, NSAttributedString.draw works correctly
            let textSize = attrStr.size()
            if text.rotation != 0 {
                context.saveGState()
                let c = text.unrotatedCenter
                context.translateBy(x: c.x, y: c.y)
                context.rotate(by: text.rotation)
                context.translateBy(x: -c.x, y: -c.y)
            }
            let textRect = NSRect(
                x: text.position.x,
                y: text.position.y,
                width: textSize.width,
                height: textSize.height
            )
            attrStr.draw(in: textRect)
            if text.rotation != 0 {
                context.restoreGState()
            }

        case .dimensionLine(let dim):
            context.saveGState()
            let dimHex = DimensionLineShape.colorLightHex
            let dimColor = NSColor(red: CGFloat((dimHex >> 16) & 0xFF) / 255.0,
                                   green: CGFloat((dimHex >> 8) & 0xFF) / 255.0,
                                   blue: CGFloat(dimHex & 0xFF) / 255.0, alpha: 1.0)
            context.setStrokeColor(dimColor.cgColor)
            context.setFillColor(dimColor.cgColor)
            context.setLineWidth(0.3)
            context.setLineDash(phase: 0, lengths: [])
            let (a, b) = dim.dimEndpoints
            context.move(to: dim.start); context.addLine(to: a)
            context.move(to: dim.end); context.addLine(to: b)
            context.move(to: a); context.addLine(to: b)
            context.strokePath()
            fillArrowhead(in: context, tip: a, toward: b)
            fillArrowhead(in: context, tip: b, toward: a)
            let label = dim.displayLabel(unit: document.settings.unit)
            let font = NSFont.systemFont(ofSize: DimensionLineShape.textHeight)
            let para = NSMutableParagraphStyle()
            para.alignment = .center
            let attrs: [NSAttributedString.Key: Any] = [
                .font: font, .foregroundColor: dimColor, .paragraphStyle: para
            ]
            let attrStr = NSAttributedString(string: label, attributes: attrs)
            let sz = attrStr.size()
            let anchor = dim.labelAnchor
            attrStr.draw(in: NSRect(x: anchor.x - sz.width / 2, y: anchor.y - sz.height / 2,
                                    width: sz.width, height: sz.height))
            context.restoreGState()

        case .group(let group):
            for child in group.children {
                drawShape(child, in: context)
            }
        }
    }

    /// Fill a triangular arrowhead with its tip at `tip`, opening toward `toward`.
    private func fillArrowhead(in context: CGContext, tip: CGPoint, toward: CGPoint) {
        let dx = toward.x - tip.x, dy = toward.y - tip.y
        let len = (dx * dx + dy * dy).squareRoot()
        guard len > 1e-9 else { return }
        let ux = dx / len, uy = dy / len
        let L = DimensionLineShape.arrowLength
        let halfW = L * 0.35
        let bx = tip.x + ux * L, by = tip.y + uy * L
        let px = -uy, py = ux
        context.move(to: tip)
        context.addLine(to: CGPoint(x: bx + px * halfW, y: by + py * halfW))
        context.addLine(to: CGPoint(x: bx - px * halfW, y: by - py * halfW))
        context.closePath()
        context.fillPath()
    }

    // MARK: - Alignment Marks (drawn in points)

    private func drawAlignmentMarks(in context: CGContext, dirtyRect: NSRect, row: Int, col: Int) {
        context.saveGState()
        context.setStrokeColor(NSColor.gray.cgColor)
        context.setLineWidth(0.5)

        let markLen = mmToPoints(alignMarkLengthMM)
        let inset: CGFloat = mmToPoints(2)

        // Corner alignment marks (L-shaped at each corner)
        let corners: [(CGFloat, CGFloat, CGFloat, CGFloat)] = [
            (dirtyRect.minX + inset, dirtyRect.minY + inset, 1, 1),
            (dirtyRect.maxX - inset, dirtyRect.minY + inset, -1, 1),
            (dirtyRect.minX + inset, dirtyRect.maxY - inset, 1, -1),
            (dirtyRect.maxX - inset, dirtyRect.maxY - inset, -1, -1),
        ]

        for (cx, cy, dx, dy) in corners {
            context.move(to: CGPoint(x: cx, y: cy))
            context.addLine(to: CGPoint(x: cx + markLen * dx, y: cy))
            context.move(to: CGPoint(x: cx, y: cy))
            context.addLine(to: CGPoint(x: cx, y: cy + markLen * dy))
        }
        context.strokePath()

        // Cross marks at midpoints of edges
        let crossSize = mmToPoints(2)
        let midX = dirtyRect.midX
        let midY = dirtyRect.midY

        drawCross(in: context, at: CGPoint(x: midX, y: dirtyRect.minY + inset), size: crossSize)
        drawCross(in: context, at: CGPoint(x: midX, y: dirtyRect.maxY - inset), size: crossSize)
        drawCross(in: context, at: CGPoint(x: dirtyRect.minX + inset, y: midY), size: crossSize)
        drawCross(in: context, at: CGPoint(x: dirtyRect.maxX - inset, y: midY), size: crossSize)

        context.restoreGState()
    }

    private func drawCross(in context: CGContext, at point: CGPoint, size: CGFloat) {
        context.move(to: CGPoint(x: point.x - size, y: point.y))
        context.addLine(to: CGPoint(x: point.x + size, y: point.y))
        context.move(to: CGPoint(x: point.x, y: point.y - size))
        context.addLine(to: CGPoint(x: point.x, y: point.y + size))
        context.strokePath()
    }

    private func drawPageLabel(in context: CGContext, dirtyRect: NSRect, row: Int, col: Int) {
        let pageNum = row * tileColumns + col + 1
        let totalPages = tileRows * tileColumns
        let label = "Page \(pageNum)/\(totalPages) (col:\(col + 1), row:\(row + 1))"
        let font = NSFont.systemFont(ofSize: 8)
        let attrs: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: NSColor.gray
        ]
        let attrStr = NSAttributedString(string: label, attributes: attrs)
        let textSize = attrStr.size()
        let textRect = NSRect(
            x: dirtyRect.maxX - textSize.width - 10,
            y: dirtyRect.maxY - textSize.height - 5,
            width: textSize.width,
            height: textSize.height
        )
        attrStr.draw(in: textRect)
    }

    // MARK: - Calibration Lookup

    private func currentPrinterCalibration() -> PrinterCalibration? {
        if let printInfo = NSPrintOperation.current?.printInfo {
            let printerName = printInfo.printer.name
            return calibrations.first { $0.printerName == printerName }
        }
        return nil
    }

    // MARK: - Bounding Box

    private func computeBoundingBox() -> CGRect {
        var minX = CGFloat.infinity, minY = CGFloat.infinity
        var maxX = -CGFloat.infinity, maxY = -CGFloat.infinity

        for layer in document.layers where layer.isVisible {
            for shape in layer.shapes {
                let bb = shape.boundingBox
                minX = min(minX, bb.minX)
                minY = min(minY, bb.minY)
                maxX = max(maxX, bb.maxX)
                maxY = max(maxY, bb.maxY)
            }
        }

        guard minX.isFinite else {
            return CGRect(x: 0, y: 0, width: 100, height: 100)
        }
        return CGRect(x: minX, y: minY, width: maxX - minX, height: maxY - minY)
    }
}

// MARK: - Calibration Test Page View

private class CalibrationTestPageView: NSView {
    private let squareSizeMM: CGFloat = 150
    private let calibrations: [PrinterCalibration]

    init(calibrations: [PrinterCalibration]) {
        self.calibrations = calibrations
        // Fit within A4 printable area (210-30=180mm width, 297-30=267mm height)
        // with 15mm print margins on each side
        let totalWidth = mmToPoints(175)
        let totalHeight = mmToPoints(220)
        super.init(frame: NSRect(x: 0, y: 0, width: totalWidth, height: totalHeight))
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override var isFlipped: Bool { true }

    private func currentPrinterCalibration() -> PrinterCalibration? {
        if let printInfo = NSPrintOperation.current?.printInfo {
            let printerName = printInfo.printer.name
            return calibrations.first { $0.printerName == printerName }
        }
        return nil
    }

    override func draw(_ dirtyRect: NSRect) {
        guard let context = NSGraphicsContext.current?.cgContext else { return }

        // White background
        context.setFillColor(NSColor.white.cgColor)
        context.fill(dirtyRect)

        // Apply calibration if available
        let calibration = currentPrinterCalibration()
        let calScaleX = CGFloat(calibration?.scaleX ?? 1.0)
        let calScaleY = CGFloat(calibration?.scaleY ?? 1.0)

        // Title
        let titleFont = NSFont.boldSystemFont(ofSize: 14)
        let titleAttrs: [NSAttributedString.Key: Any] = [
            .font: titleFont,
            .foregroundColor: NSColor.black
        ]
        let titleStr = NSAttributedString(string: "LCCAD プリンターキャリブレーション", attributes: titleAttrs)
        titleStr.draw(at: NSPoint(x: mmToPoints(5), y: mmToPoints(5)))

        // Calibration status
        let statusFont = NSFont.systemFont(ofSize: 8)
        let statusText: String
        let statusColor: NSColor
        if let cal = calibration {
            statusText = "キャリブレーション適用中: X=\(String(format: "%.4f", cal.scaleX))  Y=\(String(format: "%.4f", cal.scaleY))"
            statusColor = .systemBlue
        } else {
            statusText = "キャリブレーション未設定（補正なしで印刷）"
            statusColor = .systemOrange
        }
        let statusAttrs: [NSAttributedString.Key: Any] = [
            .font: statusFont,
            .foregroundColor: statusColor
        ]
        NSAttributedString(string: statusText, attributes: statusAttrs)
            .draw(at: NSPoint(x: mmToPoints(5), y: mmToPoints(13)))

        // Instructions
        let bodyFont = NSFont.systemFont(ofSize: 9)
        let bodyAttrs: [NSAttributedString.Key: Any] = [
            .font: bodyFont,
            .foregroundColor: NSColor.darkGray
        ]
        let instructions = """
        手順:
        1. このページを拡大縮小なし（100%）で印刷してください。
        2. 下の正方形を定規で測ってください。
        3. 正方形は正確に 150mm × 150mm であるべきです。
        4. LCCAD 設定 > Printer Calibration で測定値を入力してください。
        5. 補正倍率が自動計算されます。
        """
        let instrStr = NSAttributedString(string: instructions, attributes: bodyAttrs)
        instrStr.draw(at: NSPoint(x: mmToPoints(5), y: mmToPoints(19)))

        // Draw the 150mm square with calibration applied.
        // The stroke is drawn centered on the path, so the outer-edge-to-outer-edge
        // distance = path size + strokeWidth. To ensure the OUTER edges measure
        // exactly 150mm when measured with calipers, subtract the stroke width
        // from the path rectangle.
        let strokeWidth: CGFloat = 0.75
        let squareOriginX = mmToPoints(5) + strokeWidth / 2
        let squareOriginY = mmToPoints(48) + strokeWidth / 2
        let squareWidthPt = mmToPoints(squareSizeMM) * calScaleX - strokeWidth
        let squareHeightPt = mmToPoints(squareSizeMM) * calScaleY - strokeWidth

        context.setStrokeColor(NSColor.black.cgColor)
        context.setLineWidth(strokeWidth)
        context.stroke(CGRect(x: squareOriginX, y: squareOriginY,
                              width: squareWidthPt, height: squareHeightPt))

        // Dimension labels
        let dimFont = NSFont.systemFont(ofSize: 9)
        let dimAttrs: [NSAttributedString.Key: Any] = [
            .font: dimFont,
            .foregroundColor: NSColor.black
        ]

        // Outer edges of the square (what calipers measure)
        let outerLeft = squareOriginX - strokeWidth / 2
        let outerTop = squareOriginY - strokeWidth / 2
        let outerWidth = squareWidthPt + strokeWidth   // = mmToPoints(150) * calScale
        let outerHeight = squareHeightPt + strokeWidth

        // Horizontal dimension (below the square)
        let hLabel = NSAttributedString(string: "150 mm", attributes: dimAttrs)
        let hLabelSize = hLabel.size()
        hLabel.draw(at: NSPoint(
            x: outerLeft + outerWidth / 2 - hLabelSize.width / 2,
            y: outerTop + outerHeight + mmToPoints(3)
        ))

        // Dimension line (horizontal)
        let arrowY = outerTop + outerHeight + mmToPoints(2)
        context.setLineWidth(0.5)
        context.move(to: CGPoint(x: outerLeft, y: arrowY))
        context.addLine(to: CGPoint(x: outerLeft + outerWidth / 2 - hLabelSize.width / 2 - mmToPoints(2), y: arrowY))
        context.strokePath()
        context.move(to: CGPoint(x: outerLeft + outerWidth / 2 + hLabelSize.width / 2 + mmToPoints(2), y: arrowY))
        context.addLine(to: CGPoint(x: outerLeft + outerWidth, y: arrowY))
        context.strokePath()

        // Vertical dimension (right of the square)
        let vLabel = NSAttributedString(string: "150 mm", attributes: dimAttrs)
        let vLabelSize = vLabel.size()
        context.saveGState()
        let vLabelX = outerLeft + outerWidth + mmToPoints(5)
        let vLabelY = outerTop + outerHeight / 2 + vLabelSize.width / 2
        context.translateBy(x: vLabelX, y: vLabelY)
        context.rotate(by: -.pi / 2)
        vLabel.draw(at: .zero)
        context.restoreGState()

        // Ruler markings along the bottom edge (every 10mm, from outer edge)
        context.setLineWidth(0.3)
        for i in 0...15 {
            let x = outerLeft + mmToPoints(CGFloat(i) * 10) * calScaleX
            let tickLen: CGFloat = (i % 5 == 0) ? mmToPoints(3) : mmToPoints(1.5)
            context.move(to: CGPoint(x: x, y: outerTop + outerHeight))
            context.addLine(to: CGPoint(x: x, y: outerTop + outerHeight - tickLen))
            context.strokePath()
        }

        // Ruler markings along the left edge (from outer edge)
        for i in 0...15 {
            let y = outerTop + mmToPoints(CGFloat(i) * 10) * calScaleY
            let tickLen: CGFloat = (i % 5 == 0) ? mmToPoints(3) : mmToPoints(1.5)
            context.move(to: CGPoint(x: outerLeft, y: y))
            context.addLine(to: CGPoint(x: outerLeft + tickLen, y: y))
            context.strokePath()
        }

        // Footer
        let footerAttrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 8),
            .foregroundColor: NSColor.gray
        ]
        let footerStr = NSAttributedString(
            string: "LCCAD — 印刷ダイアログで「用紙に合わせる」がオフになっていることを確認してください。",
            attributes: footerAttrs
        )
        footerStr.draw(at: NSPoint(x: mmToPoints(5), y: mmToPoints(210)))
    }
}
