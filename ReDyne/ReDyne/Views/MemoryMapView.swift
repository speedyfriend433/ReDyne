import UIKit

protocol MemoryMapViewDelegate: AnyObject {
    func memoryMapView(_ view: MemoryMapView, didSelectSegment segment: SegmentModel)
}

class MemoryMapView: UIView {
    
    // MARK: - Color Scheme
    
    enum Colors {
        static let text = UIColor.systemBlue
        static let data = UIColor.systemGreen
        static let linkedit = UIColor.systemOrange
        static let objc = UIColor.systemPurple
        static let other = UIColor.systemGray
        static let executable = UIColor.systemRed.withAlphaComponent(0.3)
        static let writable = UIColor.systemYellow.withAlphaComponent(0.3)
    }
    
    // MARK: - Properties
    
    weak var delegate: MemoryMapViewDelegate?
    
    private let segments: [SegmentModel]
    private let sections: [SectionModel]
    private let fileSize: UInt64
    private let baseAddress: UInt64
    private var segmentRects: [(rect: CGRect, segment: SegmentModel)] = []
    
    private let padding: CGFloat = 40
    private let segmentSpacing: CGFloat = 4
    private let minSegmentHeight: CGFloat = 20
    
    // MARK: - Initialization
    
    init(segments: [SegmentModel], sections: [SectionModel], fileSize: UInt64, baseAddress: UInt64) {
        self.segments = segments
        self.sections = sections
        self.fileSize = fileSize
        self.baseAddress = baseAddress
        super.init(frame: .zero)
        
        backgroundColor = Constants.Colors.secondaryBackground
        layer.cornerRadius = 12
        layer.borderWidth = 1
        layer.borderColor = UIColor.separator.cgColor
        
        let tapGesture = UITapGestureRecognizer(target: self, action: #selector(handleTap(_:)))
        addGestureRecognizer(tapGesture)
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    // MARK: - Drawing
    
    override func draw(_ rect: CGRect) {
        super.draw(rect)
        
        guard let context = UIGraphicsGetCurrentContext() else { return }
        
        segmentRects.removeAll()
        
        // Calculate total VM size
        let totalVMSize = segments.reduce(0) { $0 + $1.vmSize }
        guard totalVMSize > 0 else { return }
        
        // Calculate available height for segments
        let availableHeight = rect.height - (padding * 2)
        let totalSpacing = CGFloat(max(0, segments.count - 1)) * segmentSpacing
        let drawableHeight = availableHeight - totalSpacing
        
        // Draw title
        drawTitle(in: rect, context: context)
        
        // Draw segments
        var currentY = padding + 30
        
        for segment in segments {
            let proportion = Double(segment.vmSize) / Double(totalVMSize)
            var segmentHeight = CGFloat(proportion) * drawableHeight
            segmentHeight = max(segmentHeight, minSegmentHeight)
            
            let segmentRect = CGRect(
                x: padding,
                y: currentY,
                width: rect.width - (padding * 2),
                height: segmentHeight
            )
            
            drawSegment(segment, in: segmentRect, context: context)
            segmentRects.append((segmentRect, segment))
            
            currentY += segmentHeight + segmentSpacing
        }
        
        // Draw scale
        drawScale(in: rect, totalSize: totalVMSize, context: context)
    }
    
    private func drawTitle(in rect: CGRect, context: CGContext) {
        let title = "Virtual Memory Layout"
        let attributes: [NSAttributedString.Key: Any] = [
            .font: UIFont.systemFont(ofSize: 16, weight: .semibold),
            .foregroundColor: UIColor.label
        ]
        
        let titleSize = (title as NSString).size(withAttributes: attributes)
        let titleRect = CGRect(
            x: padding,
            y: 8,
            width: titleSize.width,
            height: titleSize.height
        )
        
        (title as NSString).draw(in: titleRect, withAttributes: attributes)
    }
    
    private func drawSegment(_ segment: SegmentModel, in rect: CGRect, context: CGContext) {
        let fillColor = colorForSegment(segment)
        let strokeColor = fillColor.withAlphaComponent(1.0)
        
        context.setFillColor(fillColor.cgColor)
        context.setStrokeColor(strokeColor.cgColor)
        context.setLineWidth(2)
        
        let path = UIBezierPath(roundedRect: rect, cornerRadius: 6)
        context.addPath(path.cgPath)
        context.drawPath(using: .fillStroke)
        
        drawSegmentPattern(segment, in: rect, context: context)
        drawSegmentInfo(segment, in: rect, context: context)
        
        if rect.height > 60 {
            drawSections(segment, in: rect, context: context)
        }
    }
    
    private func drawSegmentPattern(_ segment: SegmentModel, in rect: CGRect, context: CGContext) {
        let protection = segment.protection.uppercased()
        
        if protection.contains("X") || protection.contains("E") {
            context.saveGState()
            context.clip(to: rect)
            
            context.setStrokeColor(Colors.executable.cgColor)
            context.setLineWidth(2)
            
            let spacing: CGFloat = 8
            var x = rect.minX - rect.height
            while x < rect.maxX {
                context.move(to: CGPoint(x: x, y: rect.maxY))
                context.addLine(to: CGPoint(x: x + rect.height, y: rect.minY))
                x += spacing
            }
            context.strokePath()
            
            context.restoreGState()
        }
        
        if protection.contains("W") {
            context.saveGState()
            context.clip(to: rect)
            
            context.setFillColor(Colors.writable.cgColor)
            
            let spacing: CGFloat = 10
            var y = rect.minY + 5
            while y < rect.maxY {
                var x = rect.minX + 5
                while x < rect.maxX {
                    context.fillEllipse(in: CGRect(x: x - 2, y: y - 2, width: 4, height: 4))
                    x += spacing
                }
                y += spacing
            }
            
            context.restoreGState()
        }
    }
    
    private func drawSegmentInfo(_ segment: SegmentModel, in rect: CGRect, context: CGContext) {
        let infoY = rect.minY + 8
        
        let nameAttributes: [NSAttributedString.Key: Any] = [
            .font: UIFont.monospacedSystemFont(ofSize: 14, weight: .bold),
            .foregroundColor: UIColor.label
        ]
        
        let nameRect = CGRect(
            x: rect.minX + 8,
            y: infoY,
            width: rect.width - 16,
            height: 20
        )
        
        (segment.name as NSString).draw(in: nameRect, withAttributes: nameAttributes)
        
        let detailAttributes: [NSAttributedString.Key: Any] = [
            .font: UIFont.monospacedSystemFont(ofSize: 11, weight: .regular),
            .foregroundColor: UIColor.secondaryLabel
        ]
        
        let addressText = String(format: "0x%llX", segment.vmAddress)
        let sizeText = formatBytes(segment.vmSize)
        let detailText = "\(addressText) • \(sizeText)"
        
        let detailRect = CGRect(
            x: rect.minX + 8,
            y: infoY + 18,
            width: rect.width - 16,
            height: 14
        )
        
        (detailText as NSString).draw(in: detailRect, withAttributes: detailAttributes)
    }
    
    private func drawSections(_ segment: SegmentModel, in rect: CGRect, context: CGContext) {
        let segmentSections = sections.filter { $0.segmentName == segment.name }
        guard !segmentSections.isEmpty else { return }
        
        let sectionsStartY = rect.minY + 40
        let availableHeight = rect.height - 48
        
        guard availableHeight > 20 else { return }
        
        let totalSectionSize = segmentSections.reduce(0) { $0 + $1.size }
        guard totalSectionSize > 0 else { return }
        
        var currentY = sectionsStartY
        
        for section in segmentSections.prefix(5) {
            let proportion = Double(section.size) / Double(totalSectionSize)
            var sectionHeight = CGFloat(proportion) * availableHeight
            sectionHeight = max(sectionHeight, 12)
            
            if currentY + sectionHeight > rect.maxY - 4 {
                break
            }
            
            let sectionRect = CGRect(
                x: rect.minX + 12,
                y: currentY,
                width: rect.width - 24,
                height: sectionHeight
            )
            
            context.setFillColor(UIColor.tertiarySystemBackground.cgColor)
            context.setStrokeColor(UIColor.separator.cgColor)
            context.setLineWidth(0.5)
            
            let sectionPath = UIBezierPath(roundedRect: sectionRect, cornerRadius: 3)
            context.addPath(sectionPath.cgPath)
            context.drawPath(using: .fillStroke)
            
            if sectionHeight > 14 {
                let sectionNameAttributes: [NSAttributedString.Key: Any] = [
                    .font: UIFont.monospacedSystemFont(ofSize: 9, weight: .medium),
                    .foregroundColor: UIColor.tertiaryLabel
                ]
                
                let sectionNameRect = CGRect(
                    x: sectionRect.minX + 4,
                    y: sectionRect.minY + 2,
                    width: sectionRect.width - 8,
                    height: sectionRect.height - 4
                )
                
                (section.sectionName as NSString).draw(in: sectionNameRect, withAttributes: sectionNameAttributes)
            }
            
            currentY += sectionHeight + 2
        }
    }
    
    private func drawScale(in rect: CGRect, totalSize: UInt64, context: CGContext) {
        let scaleX = rect.maxX - padding + 10
        let scaleStartY = padding + 30
        let scaleEndY = rect.maxY - padding
        
        context.setStrokeColor(UIColor.separator.cgColor)
        context.setLineWidth(1)
        context.move(to: CGPoint(x: scaleX, y: scaleStartY))
        context.addLine(to: CGPoint(x: scaleX, y: scaleEndY))
        context.strokePath()
        
        let markers: [(Double, String)] = [
            (0.0, "0"),
            (0.5, formatBytes(totalSize / 2)),
            (1.0, formatBytes(totalSize))
        ]
        
        let scaleAttributes: [NSAttributedString.Key: Any] = [
            .font: UIFont.monospacedSystemFont(ofSize: 9, weight: .regular),
            .foregroundColor: UIColor.tertiaryLabel
        ]
        
        for (position, label) in markers {
            let y = scaleStartY + CGFloat(position) * (scaleEndY - scaleStartY)
            
            context.move(to: CGPoint(x: scaleX, y: y))
            context.addLine(to: CGPoint(x: scaleX + 4, y: y))
            context.strokePath()
            
            let labelSize = (label as NSString).size(withAttributes: scaleAttributes)
            let labelRect = CGRect(
                x: scaleX + 6,
                y: y - labelSize.height / 2,
                width: labelSize.width,
                height: labelSize.height
            )
            
            (label as NSString).draw(in: labelRect, withAttributes: scaleAttributes)
        }
    }
    
    // MARK: - Helper Methods
    
    private func colorForSegment(_ segment: SegmentModel) -> UIColor {
        let name = segment.name.uppercased()
        
        if name.contains("TEXT") {
            return Colors.text
        } else if name.contains("DATA") {
            return Colors.data
        } else if name.contains("LINKEDIT") {
            return Colors.linkedit
        } else if name.contains("OBJC") {
            return Colors.objc
        } else {
            return Colors.other
        }
    }
    
    private func formatBytes(_ bytes: UInt64) -> String {
        if bytes >= 1024 * 1024 {
            return String(format: "%.1f MB", Double(bytes) / (1024 * 1024))
        } else if bytes >= 1024 {
            return String(format: "%.1f KB", Double(bytes) / 1024)
        } else {
            return "\(bytes) B"
        }
    }
    
    // MARK: - Interaction
    
    @objc private func handleTap(_ gesture: UITapGestureRecognizer) {
        let location = gesture.location(in: self)
        
        for (rect, segment) in segmentRects {
            if rect.contains(location) {
                UIView.animate(withDuration: 0.1, animations: {
                    self.alpha = 0.8
                }) { _ in
                    UIView.animate(withDuration: 0.1) {
                        self.alpha = 1.0
                    }
                }
                
                delegate?.memoryMapView(self, didSelectSegment: segment)
                return
            }
        }
    }
}

