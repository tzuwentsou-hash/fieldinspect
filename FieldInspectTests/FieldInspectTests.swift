import PDFKit
import SwiftData
import UIKit
import XCTest
@testable import FieldInspect

final class FieldInspectTests: XCTestCase {
    func testBuildingSystemInterNACHIOrder() {
        let expected: [BuildingSystem] = [
            .roof, .exterior, .structure, .electrical,
            .hvac, .plumbing, .interior, .insulation
        ]
        XCTAssertEqual(BuildingSystem.allCases, expected)
    }

    func testImageProcessorDownsamplesToMax1600AndUnder300KB() throws {
        let largeSize = CGSize(width: 3200, height: 2400)
        let renderer = UIGraphicsImageRenderer(size: largeSize)
        let largeImage = renderer.image { ctx in
            UIColor.darkGray.setFill()
            ctx.fill(CGRect(origin: .zero, size: largeSize))
            UIColor.orange.setFill()
            ctx.fill(CGRect(x: 400, y: 400, width: 800, height: 800))
        }

        let compressed = try XCTUnwrap(ImageProcessor.processUIImage(largeImage))
        XCTAssertLessThanOrEqual(compressed.count, AppConfig.Media.targetMaxBytes)

        let decoded = try XCTUnwrap(UIImage(data: compressed))
        let longest = max(decoded.size.width, decoded.size.height)
        XCTAssertLessThanOrEqual(longest, AppConfig.Media.maxImageDimension)
    }

    func testImageProcessorBakesRedCalloutAnnotations() throws {
        let baseRenderer = UIGraphicsImageRenderer(size: CGSize(width: 800, height: 600))
        let baseImage = baseRenderer.image { ctx in
            UIColor.white.setFill()
            ctx.fill(CGRect(x: 0, y: 0, width: 800, height: 600))
        }
        let baseJPEG = try XCTUnwrap(ImageProcessor.processUIImage(baseImage))

        let strokes = [
            CalloutStroke(tool: .freehand, points: [
                CGPoint(x: 0.2, y: 0.2),
                CGPoint(x: 0.4, y: 0.2),
                CGPoint(x: 0.4, y: 0.4)
            ]),
            CalloutStroke(tool: .arrow, points: [
                CGPoint(x: 0.6, y: 0.6),
                CGPoint(x: 0.8, y: 0.3)
            ])
        ]

        let baked = ImageProcessor.bakeAnnotations(onto: baseJPEG, strokes: strokes)
        XCTAssertNotEqual(baked, baseJPEG)
        XCTAssertNotNil(UIImage(data: baked))
    }

    func testDefectEntryClampsToFourPhotos() {
        let entry = DefectEntry()
        let dummyPhotos = (0..<6).map { Data([UInt8($0)]) }
        entry.setPhotos(dummyPhotos)
        XCTAssertEqual(entry.photos.count, 4)
    }

    func testAspectFitRectMatchesLetterboxedPreview() {
        // 4:3 photo inside a wide 400x270 canvas -> pillarboxed, 360x270 centered.
        let rect = ImageProcessor.aspectFitRect(imageSize: CGSize(width: 1600, height: 1200), in: CGSize(width: 400, height: 270))
        XCTAssertEqual(rect.width, 360, accuracy: 0.01)
        XCTAssertEqual(rect.height, 270, accuracy: 0.01)
        XCTAssertEqual(rect.minX, 20, accuracy: 0.01)
        XCTAssertEqual(rect.minY, 0, accuracy: 0.01)

        // Portrait photo -> large horizontal bars.
        let portrait = ImageProcessor.aspectFitRect(imageSize: CGSize(width: 1200, height: 1600), in: CGSize(width: 400, height: 270))
        XCTAssertEqual(portrait.height, 270, accuracy: 0.01)
        XCTAssertEqual(portrait.width, 202.5, accuracy: 0.01)
        XCTAssertEqual(portrait.midX, 200, accuracy: 0.01)
    }

    @MainActor
    func testPDFReportGeneratorProducesMultiPageUSLetterReport() throws {
        let container = try ModelContainer(
            for: InspectionProject.self, DefectEntry.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        let context = container.mainContext

        let project = InspectionProject(
            propertyAddress: "742 Evergreen Terrace, Springfield",
            clientName: "Jane Buyer",
            propertyType: .singleFamily,
            yearBuilt: 1988,
            weatherConditions: "Clear",
            ambientTemperature: "68°F",
            inspectorName: "Alex Mercer",
            companyName: "Apex Home Inspections",
            licenseNumber: "HI-40921"
        )
        // Insert before wiring relationships so SwiftData manages both sides of the inverse.
        context.insert(project)

        let photoRenderer = UIGraphicsImageRenderer(size: CGSize(width: 400, height: 300))
        let samplePhoto = try XCTUnwrap(photoRenderer.image { ctx in
            UIColor.systemBlue.setFill()
            ctx.fill(CGRect(x: 0, y: 0, width: 400, height: 300))
        }.jpegData(compressionQuality: 0.75))

        let d1 = DefectEntry(
            buildingSystem: .electrical,
            severity: .safetyHazard,
            syncStatus: .synced,
            location: "Basement — Main Electrical Panel",
            defectTitle: "Double-Tapped 20A Circuit Breaker",
            observationNarrative: "Two conductors observed under a single 20A breaker lug in the Square D 200-amp main panel, creating a potential overheating and fire hazard.",
            recommendation: "Recommend further evaluation and repair as needed by a qualified, licensed electrical contractor prior to closing.",
            photos: [samplePhoto, samplePhoto],
            project: project
        )

        let d2 = DefectEntry(
            buildingSystem: .roof,
            severity: .majorDefect,
            syncStatus: .synced,
            location: "Exterior — North Elevation Chimney",
            defectTitle: "Deteriorated Chimney Step Flashing",
            observationNarrative: "Missing sealant and lifted step flashing observed along the chimney cricket, allowing potential moisture intrusion into the attic.",
            recommendation: "Recommend further evaluation and repair as needed by a qualified, licensed roofing contractor prior to closing.",
            photos: [samplePhoto],
            project: project
        )

        context.insert(d1)
        context.insert(d2)
        try context.save()
        XCTAssertEqual(project.safeDefects.count, 2)

        let pdfData = PDFReportGenerator.generateReport(for: project)
        let document = try XCTUnwrap(PDFDocument(data: pdfData))
        XCTAssertGreaterThanOrEqual(document.pageCount, 3)

        let firstPage = try XCTUnwrap(document.page(at: 0))
        let bounds = firstPage.bounds(for: .mediaBox)
        XCTAssertEqual(bounds.width, 612, accuracy: 0.5)
        XCTAssertEqual(bounds.height, 792, accuracy: 0.5)
    }

    func testGeminiDefectResponseDecoding() throws {
        let json = """
        {
          "raw_transcript": "Double tapped breaker in the main panel basement.",
          "building_system": "electrical",
          "severity": "safetyHazard",
          "location": "Basement — Main Electrical Panel",
          "defect_title": "Double-Tapped Circuit Breaker in Main Panel",
          "observation_narrative": "Two conductors are terminated under a single 20A breaker lug.",
          "recommendation": "Recommend evaluation and repair by a qualified, licensed electrical contractor prior to closing.",
          "visual_observations_added": "Square D 200A panel visible."
        }
        """.data(using: .utf8)!

        let decoded = try JSONDecoder().decode(GeminiDefectResponse.self, from: json)
        XCTAssertEqual(decoded.buildingSystem, "electrical")
        XCTAssertEqual(decoded.severity, "safetyHazard")
        XCTAssertEqual(decoded.visualObservationsAdded, "Square D 200A panel visible.")
    }
}
