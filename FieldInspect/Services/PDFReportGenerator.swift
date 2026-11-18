import Foundation
import UIKit

/// Generates an InterNACHI-compliant, paginated, illustrated US Letter PDF inspection report.
enum PDFReportGenerator {
    static let pageWidth: CGFloat = 612
    static let pageHeight: CGFloat = 792
    static let margin: CGFloat = 40
    static let contentWidth: CGFloat = pageWidth - (margin * 2) // 532 pt
    static let footerHeight: CGFloat = 28
    static let pageBottomMargin: CGFloat = pageHeight - margin - footerHeight // 724 pt

    private struct DefectPageRef {
        let defectID: UUID
        let pageNumber: Int
    }

    static func generateReport(for project: InspectionProject) -> Data {
        let pageRect = CGRect(x: 0, y: 0, width: pageWidth, height: pageHeight)
        let groupedSystems = BuildingSystem.allCases.compactMap { system -> (BuildingSystem, [DefectEntry])? in
            let entries = project.defects(in: system)
            return entries.isEmpty ? nil : (system, entries)
        }

        // Pass 1: Compute exact page numbers for each defect & total page count
        let layoutPlan = computeLayoutPlan(project: project, groupedSystems: groupedSystems)

        // Pass 2: Render final PDF with accurate Page References & "Page X of Y" footers
        let renderer = UIGraphicsPDFRenderer(bounds: pageRect)
        return renderer.pdfData { context in
            var currentPage = 0

            // Page 1: Cover Page
            context.beginPage()
            currentPage += 1
            drawCoverPage(project: project)
            drawFooter(propertyAddress: project.propertyAddress, page: currentPage, totalPages: layoutPlan.totalPages)

            // Page 2: Executive Summary
            context.beginPage()
            currentPage += 1
            drawExecutiveSummary(project: project, pageRefs: layoutPlan.defectPageMap)
            drawFooter(propertyAddress: project.propertyAddress, page: currentPage, totalPages: layoutPlan.totalPages)

            // Page 3+: Detailed Findings Grouped by Building System
            guard !groupedSystems.isEmpty else { return }

            context.beginPage()
            currentPage += 1
            var currentY = margin

            for (system, entries) in groupedSystems {
                let bannerHeight: CGFloat = 34
                let firstCardHeight = measureDefectCardHeight(entries[0])

                // Keep section banner attached to at least its first defect card
                if currentY + bannerHeight + 10 + firstCardHeight > pageBottomMargin && currentY > margin {
                    drawFooter(propertyAddress: project.propertyAddress, page: currentPage, totalPages: layoutPlan.totalPages)
                    context.beginPage()
                    currentPage += 1
                    currentY = margin
                }

                drawSystemBanner(system: system, atY: currentY)
                currentY += bannerHeight + 10

                for entry in entries {
                    let cardHeight = measureDefectCardHeight(entry)
                    if currentY + cardHeight > pageBottomMargin && currentY > margin {
                        drawFooter(propertyAddress: project.propertyAddress, page: currentPage, totalPages: layoutPlan.totalPages)
                        context.beginPage()
                        currentPage += 1
                        currentY = margin
                    }

                    drawDefectCard(entry, atY: currentY, height: cardHeight)
                    currentY += cardHeight + 12
                }

                currentY += 8
            }

            drawFooter(propertyAddress: project.propertyAddress, page: currentPage, totalPages: layoutPlan.totalPages)
        }
    }

    // MARK: - Pass 1 Layout Planning

    private struct LayoutPlan {
        let totalPages: Int
        let defectPageMap: [UUID: Int]
    }

    private static func computeLayoutPlan(
        project: InspectionProject,
        groupedSystems: [(BuildingSystem, [DefectEntry])]
    ) -> LayoutPlan {
        var page = 2 // Cover (1) + Executive Summary (2)
        var map: [UUID: Int] = [:]

        guard !groupedSystems.isEmpty else {
            return LayoutPlan(totalPages: page, defectPageMap: map)
        }

        page += 1
        var currentY = margin

        for (_, entries) in groupedSystems {
            let bannerHeight: CGFloat = 34
            let firstCardHeight = measureDefectCardHeight(entries[0])

            if currentY + bannerHeight + 10 + firstCardHeight > pageBottomMargin && currentY > margin {
                page += 1
                currentY = margin
            }

            currentY += bannerHeight + 10

            for entry in entries {
                let cardHeight = measureDefectCardHeight(entry)
                if currentY + cardHeight > pageBottomMargin && currentY > margin {
                    page += 1
                    currentY = margin
                }
                map[entry.id] = page
                currentY += cardHeight + 12
            }

            currentY += 8
        }

        return LayoutPlan(totalPages: page, defectPageMap: map)
    }

    // MARK: - Page 1: Cover Page

    private static func drawCoverPage(project: InspectionProject) {
        let slate = UIColor(red: 0.118, green: 0.161, blue: 0.231, alpha: 1.0)
        let amber = UIColor(red: 0.851, green: 0.467, blue: 0.024, alpha: 1.0)
        let muted = UIColor(red: 0.35, green: 0.40, blue: 0.48, alpha: 1.0)

        var y = margin

        // Header bar
        let logoSize = CGSize(width: 96, height: 54)
        let hasLogo = UIImage(named: "BrandLogo") != nil
        let titleWidth = hasLogo ? (contentWidth - logoSize.width - 12) : contentWidth

        if let brandLogo = UIImage(named: "BrandLogo") {
            let logoRect = CGRect(x: margin + contentWidth - logoSize.width, y: y - 2, width: logoSize.width, height: logoSize.height)
            drawAspectFit(image: brandLogo, in: logoRect)
        }

        let companyText = project.companyName.isEmpty ? String(localized: "FieldInspect Certified Home Inspections") : project.companyName
        drawText(
            companyText.uppercased(with: locale),
            font: .systemFont(ofSize: 12, weight: .bold),
            color: amber,
            rect: CGRect(x: margin, y: y, width: titleWidth, height: 18)
        )
        y += 22

        drawText(
            String(localized: "RESIDENTIAL PROPERTY INSPECTION REPORT"),
            font: .systemFont(ofSize: 20, weight: .heavy),
            color: slate,
            rect: CGRect(x: margin, y: y, width: titleWidth, height: 32)
        )
        y += 38

        // Accent divider
        let divider = UIBezierPath(rect: CGRect(x: margin, y: y, width: contentWidth, height: 3))
        amber.setFill()
        divider.fill()
        y += 18

        // Hero Cover Photo
        let heroHeight: CGFloat = 250
        let heroRect = CGRect(x: margin, y: y, width: contentWidth, height: heroHeight)
        let heroPath = UIBezierPath(roundedRect: heroRect, cornerRadius: 8)
        UIColor(white: 0.94, alpha: 1.0).setFill()
        heroPath.fill()

        if let coverData = project.coverPhotoData, let image = UIImage(data: coverData) {
            UIGraphicsGetCurrentContext()?.saveGState()
            heroPath.addClip()
            drawAspectFill(image: image, in: heroRect)
            UIGraphicsGetCurrentContext()?.restoreGState()
        } else {
            drawText(
                String(localized: "No Cover Photo Captured"),
                font: .systemFont(ofSize: 13, weight: .medium),
                color: muted,
                rect: CGRect(x: margin, y: y + heroHeight / 2 - 10, width: contentWidth, height: 20),
                alignment: .center
            )
        }
        y += heroHeight + 22

        // Property & Inspector Metadata Card
        let metaRect = CGRect(x: margin, y: y, width: contentWidth, height: 180)
        let metaPath = UIBezierPath(roundedRect: metaRect, cornerRadius: 8)
        UIColor(red: 0.973, green: 0.980, blue: 0.988, alpha: 1.0).setFill()
        metaPath.fill()
        UIColor(white: 0.85, alpha: 1.0).setStroke()
        metaPath.lineWidth = 1
        metaPath.stroke()

        let dateFormatter = DateFormatter()
        dateFormatter.locale = locale
        dateFormatter.dateStyle = .long
        dateFormatter.timeStyle = .none

        let inspectorName = project.inspectorName.isEmpty ? String(localized: "Certified Inspector") : project.inspectorName
        let license = project.licenseNumber.isEmpty ? String(localized: "N/A") : project.licenseNumber
        let rows: [(String, String)] = [
            (String(localized: "Property Address:"), project.propertyAddress.isEmpty ? String(localized: "Unspecified Address") : project.propertyAddress),
            (String(localized: "Client Name:"), project.clientName.isEmpty ? String(localized: "Unspecified Client") : project.clientName),
            (String(localized: "Inspection Date:"), dateFormatter.string(from: project.inspectionDate)),
            (String(localized: "Property Details:"), String(localized: "\(project.propertyType.displayName) • Built \(String(project.yearBuilt))")),
            (String(localized: "Weather / Temp:"), "\(WeatherCondition.displayName(for: project.weatherConditions)) • \(project.ambientTemperature)"),
            (String(localized: "Inspector:"), String(localized: "\(inspectorName) (Lic: \(license))"))
        ]

        var rowY = y + 16
        for (label, value) in rows {
            drawText(label, font: .systemFont(ofSize: 11, weight: .bold), color: muted, rect: CGRect(x: margin + 16, y: rowY, width: 125, height: 18))
            drawText(value, font: .systemFont(ofSize: 11.5, weight: .semibold), color: slate, rect: CGRect(x: margin + 145, y: rowY, width: contentWidth - 160, height: 22))
            rowY += 26
        }

        y += 200

        // Standard InterNACHI Scope & Limitations Disclaimer
        let disclaimerTitle = String(localized: "SCOPE & LIMITATIONS (InterNACHI / ASHI STANDARDS OF PRACTICE)")
        drawText(disclaimerTitle, font: .systemFont(ofSize: 10, weight: .bold), color: slate, rect: CGRect(x: margin, y: y, width: contentWidth, height: 16))
        y += 18

        let disclaimerBody = String(localized: "This residential inspection report is a visual, non-invasive evaluation of the readily accessible building systems and components as observed on the date of inspection. It is performed in accordance with InterNACHI Standards of Practice and is not a building code compliance audit, engineering study, or warranty/guarantee of future performance. Concealed, latent, or inaccessible defects are excluded. Any safety hazards or major defects identified herein should be further evaluated and repaired by qualified, licensed trade specialists prior to closing.")
        drawText(
            disclaimerBody,
            font: .systemFont(ofSize: 9.5, weight: .regular),
            color: muted,
            rect: CGRect(x: margin, y: y, width: contentWidth, height: pageBottomMargin - y)
        )
    }

    // MARK: - Page 2: Executive Summary

    private static func drawExecutiveSummary(project: InspectionProject, pageRefs: [UUID: Int]) {
        let slate = UIColor(red: 0.118, green: 0.161, blue: 0.231, alpha: 1.0)
        let muted = UIColor(red: 0.35, green: 0.40, blue: 0.48, alpha: 1.0)
        var y = margin

        drawText(
            String(localized: "EXECUTIVE SUMMARY"),
            font: .systemFont(ofSize: 18, weight: .heavy),
            color: slate,
            rect: CGRect(x: margin, y: y, width: contentWidth, height: 26)
        )
        y += 30

        drawText(
            String(localized: "Priority overview for buyer and real estate agent review. Refer to the referenced pages for full photographic documentation and recommendations."),
            font: .systemFont(ofSize: 10.5, weight: .regular),
            color: muted,
            rect: CGRect(x: margin, y: y, width: contentWidth, height: 30)
        )
        y += 38

        // Summary Count Badges
        let counts: [(String, Int, UIColor)] = [
            (String(localized: "Safety Hazards"), project.count(for: .safetyHazard), DefectSeverity.safetyHazard.uiColor),
            (String(localized: "Major Defects"), project.count(for: .majorDefect), DefectSeverity.majorDefect.uiColor),
            (String(localized: "Maintenance Items"), project.count(for: .monitor), DefectSeverity.monitor.uiColor)
        ]

        let boxWidth = (contentWidth - 20) / 3
        for (index, item) in counts.enumerated() {
            let x = margin + CGFloat(index) * (boxWidth + 10)
            let boxRect = CGRect(x: x, y: y, width: boxWidth, height: 64)
            let path = UIBezierPath(roundedRect: boxRect, cornerRadius: 8)
            item.2.withAlphaComponent(0.1).setFill()
            path.fill()
            item.2.withAlphaComponent(0.5).setStroke()
            path.lineWidth = 1
            path.stroke()

            drawText(
                item.1.formatted(.number.locale(locale)),
                font: .monospacedDigitSystemFont(ofSize: 24, weight: .heavy),
                color: item.2,
                rect: CGRect(x: x + 10, y: y + 10, width: boxWidth - 20, height: 28),
                alignment: .center
            )
            drawText(
                item.0.uppercased(with: locale),
                font: .systemFont(ofSize: 9, weight: .bold),
                color: slate,
                rect: CGRect(x: x + 6, y: y + 40, width: boxWidth - 12, height: 16),
                alignment: .center
            )
        }
        y += 84

        // Priority Index Table (Safety Hazards & Major Defects)
        let priorityDefects = project.safeDefects
            .filter { $0.severity == .safetyHazard || $0.severity == .majorDefect }
            .sorted {
                if $0.severity.sortPriority != $1.severity.sortPriority {
                    return $0.severity.sortPriority < $1.severity.sortPriority
                }
                return $0.buildingSystem.sortOrder < $1.buildingSystem.sortOrder
            }

        drawText(
            String(localized: "PRIORITY FINDINGS INDEX (SAFETY HAZARDS & MAJOR DEFECTS)"),
            font: .systemFont(ofSize: 11, weight: .bold),
            color: slate,
            rect: CGRect(x: margin, y: y, width: contentWidth, height: 18)
        )
        y += 24

        if priorityDefects.isEmpty {
            drawText(
                String(localized: "No Safety Hazards or Major Defects were recorded during this inspection."),
                font: .systemFont(ofSize: 11, weight: .medium),
                color: muted,
                rect: CGRect(x: margin, y: y, width: contentWidth, height: 22)
            )
            return
        }

        // Table Header
        let headerRect = CGRect(x: margin, y: y, width: contentWidth, height: 22)
        slate.setFill()
        UIBezierPath(rect: headerRect).fill()

        drawText(String(localized: "SEVERITY"), font: .systemFont(ofSize: 9, weight: .bold), color: .white, rect: CGRect(x: margin + 8, y: y + 5, width: 85, height: 14))
        drawText(String(localized: "LOCATION"), font: .systemFont(ofSize: 9, weight: .bold), color: .white, rect: CGRect(x: margin + 98, y: y + 5, width: 150, height: 14))
        drawText(String(localized: "FINDING HEADLINE"), font: .systemFont(ofSize: 9, weight: .bold), color: .white, rect: CGRect(x: margin + 254, y: y + 5, width: 220, height: 14))
        drawText(String(localized: "PAGE"), font: .systemFont(ofSize: 9, weight: .bold), color: .white, rect: CGRect(x: margin + 480, y: y + 5, width: 44, height: 14), alignment: .right)
        y += 22

        for (idx, defect) in priorityDefects.enumerated() {
            if y + 26 > pageBottomMargin {
                drawText(
                    String(localized: "Additional priority items are detailed in the system sections."),
                    font: .italicSystemFont(ofSize: 9.5),
                    color: muted,
                    rect: CGRect(x: margin, y: y + 4, width: contentWidth, height: 16)
                )
                break
            }

            let rowRect = CGRect(x: margin, y: y, width: contentWidth, height: 26)
            if idx % 2 == 1 {
                UIColor(white: 0.96, alpha: 1.0).setFill()
                UIBezierPath(rect: rowRect).fill()
            }

            let title = defect.defectTitle.isEmpty ? String(localized: "Untitled Finding") : defect.defectTitle
            let loc = defect.location.isEmpty ? defect.buildingSystem.shortName : defect.location
            let pageNum = pageRefs[defect.id].map { String(localized: "p. \($0)") } ?? "—"

            drawText(defect.severity.shortLabel.uppercased(with: locale), font: .systemFont(ofSize: 9, weight: .bold), color: defect.severity.uiColor, rect: CGRect(x: margin + 8, y: y + 6, width: 85, height: 16))
            drawText(loc, font: .systemFont(ofSize: 9.5, weight: .medium), color: slate, rect: CGRect(x: margin + 98, y: y + 6, width: 150, height: 16))
            drawText(title, font: .systemFont(ofSize: 9.5, weight: .semibold), color: slate, rect: CGRect(x: margin + 254, y: y + 6, width: 220, height: 16))
            drawText(pageNum, font: .monospacedDigitSystemFont(ofSize: 9.5, weight: .bold), color: muted, rect: CGRect(x: margin + 480, y: y + 6, width: 44, height: 16), alignment: .right)

            y += 26
        }
    }

    // MARK: - Page 3+: System Banner & Defect Cards

    private static func drawSystemBanner(system: BuildingSystem, atY y: CGFloat) {
        let slate = UIColor(red: 0.118, green: 0.161, blue: 0.231, alpha: 1.0)
        let bannerRect = CGRect(x: margin, y: y, width: contentWidth, height: 34)
        let path = UIBezierPath(roundedRect: bannerRect, cornerRadius: 6)
        slate.setFill()
        path.fill()

        drawText(
            system.displayName.uppercased(with: locale),
            font: .systemFont(ofSize: 12.5, weight: .heavy),
            color: .white,
            rect: CGRect(x: margin + 12, y: y + 9, width: contentWidth - 24, height: 18)
        )
    }

    private static func measureDefectCardHeight(_ entry: DefectEntry) -> CGFloat {
        let innerWidth = contentWidth - 24
        var height: CGFloat = 12 // Top padding

        // Top bar: Severity pill + Title + Location
        height += 36

        // Photo rows (max 2 per row)
        let photos = entry.photos
        if !photos.isEmpty {
            let rowCount = Int(ceil(Double(photos.count) / 2.0))
            let photoHeight: CGFloat = 135
            height += CGFloat(rowCount) * photoHeight + CGFloat(max(0, rowCount - 1)) * 8 + 10
        }

        // Observation text
        // Measure the exact attributed strings drawDefectCard renders (bold label + regular body).
        // Measuring with a plain regular font under-estimated wrapped lines, clipping the last line
        // of text and shifting page references in the Executive Summary.
        let slate = UIColor(red: 0.118, green: 0.161, blue: 0.231, alpha: 1.0)
        let observation = entry.observationNarrative.isEmpty ? String(localized: "No observation narrative recorded.") : entry.observationNarrative
        let obsHeight = measureAttributedHeight(
            labeledAttributedString(label: observationLabel, body: observation, slate: slate),
            width: innerWidth
        )
        height += obsHeight + 8

        // Recommendation text
        let recommendation = entry.recommendation.isEmpty ? defaultRecommendation : entry.recommendation
        let recHeight = measureAttributedHeight(
            labeledAttributedString(label: recommendationLabel, body: recommendation, slate: slate),
            width: innerWidth
        )
        height += recHeight + 14

        return height
    }

    private static func drawDefectCard(_ entry: DefectEntry, atY y: CGFloat, height: CGFloat) {
        let slate = UIColor(red: 0.118, green: 0.161, blue: 0.231, alpha: 1.0)
        let muted = UIColor(red: 0.35, green: 0.40, blue: 0.48, alpha: 1.0)

        let cardRect = CGRect(x: margin, y: y, width: contentWidth, height: height)
        let cardPath = UIBezierPath(roundedRect: cardRect, cornerRadius: 8)
        UIColor.white.setFill()
        cardPath.fill()
        UIColor(white: 0.82, alpha: 1.0).setStroke()
        cardPath.lineWidth = 1
        cardPath.stroke()

        // Left severity accent stripe
        let stripeRect = CGRect(x: margin, y: y, width: 5, height: height)
        let stripePath = UIBezierPath(roundedRect: stripeRect, byRoundingCorners: [.topLeft, .bottomLeft], cornerRadii: CGSize(width: 8, height: 8))
        entry.severity.uiColor.setFill()
        stripePath.fill()

        let innerX = margin + 14
        let innerWidth = contentWidth - 24
        var cursorY = y + 12

        // Severity Pill
        let pillWidth: CGFloat = 115
        let pillRect = CGRect(x: innerX, y: cursorY, width: pillWidth, height: 20)
        let pillPath = UIBezierPath(roundedRect: pillRect, cornerRadius: 10)
        entry.severity.uiColor.setFill()
        pillPath.fill()
        drawText(
            entry.severity.displayName.uppercased(with: locale),
            font: fittedFont(for: entry.severity.displayName.uppercased(with: locale), size: 8.5, weight: .bold, maxWidth: pillWidth - 8),
            color: .white,
            rect: CGRect(x: innerX + 4, y: cursorY + 4, width: pillWidth - 8, height: 13),
            alignment: .center
        )

        // Headline & Location
        let title = entry.defectTitle.isEmpty ? String(localized: "Inspection Finding") : entry.defectTitle
        drawText(
            title,
            font: .systemFont(ofSize: 12, weight: .bold),
            color: slate,
            rect: CGRect(x: innerX + pillWidth + 10, y: cursorY, width: innerWidth - pillWidth - 10, height: 16)
        )
        let locationText = entry.location.isEmpty ? entry.buildingSystem.displayName : entry.location
        drawText(
            String(localized: "Location: \(locationText)"),
            font: .systemFont(ofSize: 9.5, weight: .medium),
            color: muted,
            rect: CGRect(x: innerX + pillWidth + 10, y: cursorY + 16, width: innerWidth - pillWidth - 10, height: 14)
        )
        cursorY += 36

        // Photos (max 2 per row)
        let photos = entry.photos
        if !photos.isEmpty {
            let thumbWidth = (innerWidth - 8) / 2
            let thumbHeight: CGFloat = 135
            for (index, photoData) in photos.enumerated() {
                let row = index / 2
                let col = index % 2
                let px = innerX + CGFloat(col) * (thumbWidth + 8)
                let py = cursorY + CGFloat(row) * (thumbHeight + 8)
                let thumbRect = CGRect(x: px, y: py, width: thumbWidth, height: thumbHeight)

                let bgPath = UIBezierPath(roundedRect: thumbRect, cornerRadius: 6)
                UIColor(white: 0.95, alpha: 1.0).setFill()
                bgPath.fill()

                if let image = UIImage(data: photoData) {
                    UIGraphicsGetCurrentContext()?.saveGState()
                    bgPath.addClip()
                    drawAspectFit(image: image, in: thumbRect)
                    UIGraphicsGetCurrentContext()?.restoreGState()
                }
            }
            let rowCount = Int(ceil(Double(photos.count) / 2.0))
            cursorY += CGFloat(rowCount) * thumbHeight + CGFloat(max(0, rowCount - 1)) * 8 + 10
        }

        // Observation
        let observation = entry.observationNarrative.isEmpty ? String(localized: "No observation narrative recorded.") : entry.observationNarrative
        let obsAttributed = labeledAttributedString(label: observationLabel, body: observation, slate: slate)
        let obsHeight = measureAttributedHeight(obsAttributed, width: innerWidth)
        obsAttributed.draw(in: CGRect(x: innerX, y: cursorY, width: innerWidth, height: obsHeight))
        cursorY += obsHeight + 8

        // Recommendation
        let recommendation = entry.recommendation.isEmpty ? defaultRecommendation : entry.recommendation
        let recAttributed = labeledAttributedString(label: recommendationLabel, body: recommendation, slate: slate)
        let recHeight = measureAttributedHeight(recAttributed, width: innerWidth)
        recAttributed.draw(in: CGRect(x: innerX, y: cursorY, width: innerWidth, height: recHeight))
    }

    // MARK: - Footer

    private static func drawFooter(propertyAddress: String, page: Int, totalPages: Int) {
        let footerY = pageHeight - margin - 16
        let muted = UIColor(red: 0.45, green: 0.50, blue: 0.56, alpha: 1.0)

        let line = UIBezierPath()
        line.move(to: CGPoint(x: margin, y: footerY - 6))
        line.addLine(to: CGPoint(x: pageWidth - margin, y: footerY - 6))
        UIColor(white: 0.85, alpha: 1.0).setStroke()
        line.lineWidth = 0.75
        line.stroke()

        let address = propertyAddress.isEmpty ? String(localized: "Property Inspection") : propertyAddress
        // Address column ends before the centered label (x = margin + 170) so long addresses don't overprint it.
        drawText(address, font: .systemFont(ofSize: 8.5, weight: .regular), color: muted, rect: CGRect(x: margin, y: footerY, width: 165, height: 14), alignment: .left)
        drawText(String(localized: "Confidential Home Inspection Report"), font: .systemFont(ofSize: 8.5, weight: .medium), color: muted, rect: CGRect(x: margin + 170, y: footerY, width: 192, height: 14), alignment: .center)
        drawText(String(localized: "Page \(page) of \(totalPages)"), font: .monospacedDigitSystemFont(ofSize: 8.5, weight: .semibold), color: muted, rect: CGRect(x: pageWidth - margin - 100, y: footerY, width: 100, height: 14), alignment: .right)
    }

    // MARK: - Localization Helpers

    /// App UI language + user region; keeps PDF dates/numbers in the same language as the report text.
    private static var locale: Locale { AppLocale.locale }
    private static var observationLabel: String { String(localized: "Observation: ") }
    private static var recommendationLabel: String { String(localized: "Recommendation: ") }
    private static var defaultRecommendation: String {
        String(localized: "Monitor and consult a qualified licensed specialist if condition worsens.")
    }

    /// Shrinks the font (down to 6.5 pt) so longer translations of fixed-width labels don't wrap and clip.
    private static func fittedFont(for text: String, size: CGFloat, weight: UIFont.Weight, maxWidth: CGFloat) -> UIFont {
        var current = size
        while current > 6.5 {
            let font = UIFont.systemFont(ofSize: current, weight: weight)
            if (text as NSString).size(withAttributes: [.font: font]).width <= maxWidth { return font }
            current -= 0.5
        }
        return .systemFont(ofSize: current, weight: weight)
    }

    // MARK: - Drawing & Measurement Helpers

    private static func drawText(
        _ text: String,
        font: UIFont,
        color: UIColor,
        rect: CGRect,
        alignment: NSTextAlignment = .left
    ) {
        let paragraph = NSMutableParagraphStyle()
        paragraph.alignment = alignment
        paragraph.lineBreakMode = .byWordWrapping

        let attrs: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: color,
            .paragraphStyle: paragraph
        ]
        (text as NSString).draw(in: rect, withAttributes: attrs)
    }

    private static func labeledAttributedString(label: String, body: String, slate: UIColor) -> NSAttributedString {
        let result = NSMutableAttributedString(
            string: label,
            attributes: [
                .font: UIFont.systemFont(ofSize: 10.5, weight: .bold),
                .foregroundColor: slate
            ]
        )
        result.append(NSAttributedString(
            string: body,
            attributes: [
                .font: UIFont.systemFont(ofSize: 10.5, weight: .regular),
                .foregroundColor: UIColor(white: 0.18, alpha: 1.0)
            ]
        ))
        return result
    }

    private static func measureAttributedHeight(_ attributed: NSAttributedString, width: CGFloat) -> CGFloat {
        let rect = attributed.boundingRect(
            with: CGSize(width: width, height: .greatestFiniteMagnitude),
            options: [.usesLineFragmentOrigin, .usesFontLeading],
            context: nil
        )
        return ceil(rect.height)
    }

    private static func drawAspectFill(image: UIImage, in rect: CGRect) {
        let imgSize = image.size
        guard imgSize.width > 0, imgSize.height > 0 else { return }
        let scale = max(rect.width / imgSize.width, rect.height / imgSize.height)
        let drawWidth = imgSize.width * scale
        let drawHeight = imgSize.height * scale
        let drawRect = CGRect(
            x: rect.midX - drawWidth / 2,
            y: rect.midY - drawHeight / 2,
            width: drawWidth,
            height: drawHeight
        )
        image.draw(in: drawRect)
    }

    private static func drawAspectFit(image: UIImage, in rect: CGRect) {
        let imgSize = image.size
        guard imgSize.width > 0, imgSize.height > 0 else { return }
        let scale = min(rect.width / imgSize.width, rect.height / imgSize.height)
        let drawWidth = imgSize.width * scale
        let drawHeight = imgSize.height * scale
        let drawRect = CGRect(
            x: rect.midX - drawWidth / 2,
            y: rect.midY - drawHeight / 2,
            width: drawWidth,
            height: drawHeight
        )
        image.draw(in: drawRect)
    }
}
