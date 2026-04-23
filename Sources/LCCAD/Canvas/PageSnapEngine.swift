import CoreGraphics

/// Snap engine for page layout — snaps dragged pages to adjacent pages with overlap.
enum PageSnapEngine {
    struct SnapResult {
        var snappedOrigin: CGPoint
        var snappedX: Bool
        var snappedY: Bool
    }

    /// Snap the dragged page's origin against other pages.
    static func snap(
        draggedOrigin: CGPoint,
        pageSize: CGSize,
        allOtherOrigins: [CGPoint],
        overlapMM: CGFloat,
        tolerance: CGFloat
    ) -> SnapResult {
        var origin = draggedOrigin
        let dragFrame = CGRect(origin: draggedOrigin, size: pageSize)
        var snappedX = false
        var snappedY = false

        var bestDX: CGFloat?
        var bestDistX: CGFloat = .greatestFiniteMagnitude
        var bestDY: CGFloat?
        var bestDistY: CGFloat = .greatestFiniteMagnitude

        for otherOrigin in allOtherOrigins {
            let otherFrame = CGRect(origin: otherOrigin, size: pageSize)

            let overlapY = dragFrame.minY < otherFrame.maxY && dragFrame.maxY > otherFrame.minY
            let overlapX = dragFrame.minX < otherFrame.maxX && dragFrame.maxX > otherFrame.minX

            if overlapY {
                // Right edge → Left edge with overlap
                let snapX1 = otherFrame.minX - pageSize.width + overlapMM
                let dist1 = abs(origin.x - snapX1)
                if dist1 < tolerance && dist1 < bestDistX { bestDX = snapX1; bestDistX = dist1 }

                // Left edge → Right edge with overlap
                let snapX2 = otherFrame.maxX - overlapMM
                let dist2 = abs(origin.x - snapX2)
                if dist2 < tolerance && dist2 < bestDistX { bestDX = snapX2; bestDistX = dist2 }

                // Flush: right == left
                let snapX3 = otherFrame.minX - pageSize.width
                let dist3 = abs(origin.x - snapX3)
                if dist3 < tolerance && dist3 < bestDistX { bestDX = snapX3; bestDistX = dist3 }

                // Flush: left == right
                let snapX4 = otherFrame.maxX
                let dist4 = abs(origin.x - snapX4)
                if dist4 < tolerance && dist4 < bestDistX { bestDX = snapX4; bestDistX = dist4 }
            }

            if overlapX {
                // Bottom → Top with overlap
                let snapY1 = otherFrame.minY - pageSize.height + overlapMM
                let dist1 = abs(origin.y - snapY1)
                if dist1 < tolerance && dist1 < bestDistY { bestDY = snapY1; bestDistY = dist1 }

                // Top → Bottom with overlap
                let snapY2 = otherFrame.maxY - overlapMM
                let dist2 = abs(origin.y - snapY2)
                if dist2 < tolerance && dist2 < bestDistY { bestDY = snapY2; bestDistY = dist2 }

                // Flush: bottom == top
                let snapY3 = otherFrame.minY - pageSize.height
                let dist3 = abs(origin.y - snapY3)
                if dist3 < tolerance && dist3 < bestDistY { bestDY = snapY3; bestDistY = dist3 }

                // Flush: top == bottom
                let snapY4 = otherFrame.maxY
                let dist4 = abs(origin.y - snapY4)
                if dist4 < tolerance && dist4 < bestDistY { bestDY = snapY4; bestDistY = dist4 }
            }

            // Edge-aligned: same top or left
            let topDist = abs(origin.y - otherFrame.minY)
            if topDist < tolerance && topDist < bestDistY { bestDY = otherFrame.minY; bestDistY = topDist }
            let leftDist = abs(origin.x - otherFrame.minX)
            if leftDist < tolerance && leftDist < bestDistX { bestDX = otherFrame.minX; bestDistX = leftDist }
        }

        if let dx = bestDX { origin.x = dx; snappedX = true }
        if let dy = bestDY { origin.y = dy; snappedY = true }

        return SnapResult(snappedOrigin: origin, snappedX: snappedX, snappedY: snappedY)
    }
}
