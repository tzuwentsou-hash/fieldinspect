import PDFKit
import SwiftUI

struct ReportPreviewView: View {
    @Environment(\.dismiss) private var dismiss
    let project: InspectionProject

    @State private var pdfData: Data?
    @State private var exportURL: URL?

    var body: some View {
        NavigationStack {
            Group {
                if let pdfData {
                    PDFKitRepresentable(data: pdfData)
                        .ignoresSafeArea(edges: .bottom)
                } else {
                    VStack(spacing: 12) {
                        ProgressView()
                        Text("Compiling Illustrated Inspection Report…")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
            .navigationTitle("Report Preview")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Done") { dismiss() }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    if let exportURL {
                        ShareLink(item: exportURL) {
                            Label("Share PDF", systemImage: "square.and.arrow.up")
                        }
                    }
                }
            }
            .task {
                await generatePDF()
            }
        }
    }

    private func generatePDF() async {
        let data = PDFReportGenerator.generateReport(for: project)
        let sanitizedAddress = project.propertyAddress
            .replacingOccurrences(of: "[^A-Za-z0-9_-]", with: "_", options: .regularExpression)
            .trimmingCharacters(in: CharacterSet(charactersIn: "_"))
        let fileName = (sanitizedAddress.isEmpty ? "Inspection_Report" : sanitizedAddress) + "_Report.pdf"
        let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent(fileName)
        try? data.write(to: tempURL, options: .atomic)

        self.pdfData = data
        self.exportURL = tempURL
    }
}

private struct PDFKitRepresentable: UIViewRepresentable {
    let data: Data

    func makeUIView(context: Context) -> PDFView {
        let pdfView = PDFView()
        pdfView.autoScales = true
        pdfView.displayMode = .singlePageContinuous
        pdfView.displayDirection = .vertical
        pdfView.backgroundColor = .secondarySystemBackground
        pdfView.document = PDFDocument(data: data)
        return pdfView
    }

    func updateUIView(_ uiView: PDFView, context: Context) {
        if uiView.document == nil {
            uiView.document = PDFDocument(data: data)
        }
    }
}
