import Foundation

struct GeminiDefectResponse: Codable, Sendable {
    let rawTranscript: String
    let buildingSystem: String
    let severity: String
    let location: String
    let defectTitle: String
    let observationNarrative: String
    let recommendation: String
    let visualObservationsAdded: String?

    enum CodingKeys: String, CodingKey {
        case rawTranscript = "raw_transcript"
        case buildingSystem = "building_system"
        case severity
        case location
        case defectTitle = "defect_title"
        case observationNarrative = "observation_narrative"
        case recommendation
        case visualObservationsAdded = "visual_observations_added"
    }
}

enum GeminiServiceError: LocalizedError {
    case invalidResponse
    case serverError(statusCode: Int, message: String)
    case emptyContent
    case missingMedia

    var errorDescription: String? {
        switch self {
        case .invalidResponse:
            return "Received an invalid response from the AI service."
        case .serverError(let statusCode, let message):
            return "AI service error (\(statusCode)): \(message)"
        case .emptyContent:
            return "AI returned an empty analysis."
        case .missingMedia:
            return "At least one photo, voice memo, or text note is required for AI analysis."
        }
    }
}

/// Stateless client communicating with the Cloudflare Worker Gemini Multimodal proxy.
final class GeminiInspectionService: Sendable {
    static let shared = GeminiInspectionService()

    private let session: URLSession

    init(session: URLSession = .shared) {
        self.session = session
    }

    func analyzeDefect(
        photos: [Data],
        audioMemoData: Data?,
        propertyType: PropertyType,
        yearBuilt: Int,
        inspectorHintNotes: String? = nil
    ) async throws -> GeminiDefectResponse {
        // The capture sheet allows saving a finding with only a typed note ("if unable to speak"),
        // so a text note alone is valid input for synthesis.
        let hasHint = !(inspectorHintNotes?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ?? true)
        guard !photos.isEmpty || audioMemoData != nil || hasHint else {
            throw GeminiServiceError.missingMedia
        }

        let payload = try buildRequestPayload(
            photos: photos,
            audioMemoData: audioMemoData,
            propertyType: propertyType,
            yearBuilt: yearBuilt,
            inspectorHintNotes: inspectorHintNotes
        )

        var request = URLRequest(url: AppConfig.geminiProxyEndpoint)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if !AppConfig.geminiProxyClientToken.isEmpty {
            request.setValue(AppConfig.geminiProxyClientToken, forHTTPHeaderField: "X-FieldInspect-Token")
        }
        request.timeoutInterval = 60
        request.httpBody = try JSONSerialization.data(withJSONObject: payload)

        let (data, response) = try await session.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw GeminiServiceError.invalidResponse
        }

        guard (200...299).contains(httpResponse.statusCode) else {
            let bodyText = String(data: data, encoding: .utf8) ?? "Unknown error"
            throw GeminiServiceError.serverError(statusCode: httpResponse.statusCode, message: bodyText)
        }

        return try decodeResponse(from: data)
    }

    private func buildRequestPayload(
        photos: [Data],
        audioMemoData: Data?,
        propertyType: PropertyType,
        yearBuilt: Int,
        inspectorHintNotes: String?
    ) throws -> [String: Any] {
        var metadata: [String: Any] = [
            "property_type": propertyType.rawValue,
            "year_built": yearBuilt,
            "inspector_notes_language": "English"
        ]
        if let hint = inspectorHintNotes, !hint.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            metadata["inspector_text_notes"] = hint
        }

        let metadataData = try JSONSerialization.data(withJSONObject: metadata)
        let metadataString = String(data: metadataData, encoding: .utf8) ?? "{}"

        var parts: [[String: Any]] = [
            ["text": metadataString]
        ]

        for jpegData in photos.prefix(AppConfig.Media.maxPhotosPerDefect) {
            parts.append([
                "inlineData": [
                    "mimeType": "image/jpeg",
                    "data": jpegData.base64EncodedString()
                ]
            ])
        }

        if let audioData = audioMemoData, !audioData.isEmpty {
            parts.append([
                "inlineData": [
                    "mimeType": "audio/mp4",
                    "data": audioData.base64EncodedString()
                ]
            ])
        }

        return [
            "model": AppConfig.geminiModel,
            "systemInstruction": [
                "parts": [
                    ["text": Self.productionSystemInstruction]
                ]
            ],
            "contents": [
                [
                    "role": "user",
                    "parts": parts
                ]
            ],
            "generationConfig": [
                "temperature": 0.2,
                "responseMimeType": "application/json",
                "responseSchema": Self.responseSchema
            ]
        ]
    }

    private func decodeResponse(from data: Data) throws -> GeminiDefectResponse {
        let decoder = JSONDecoder()

        // 1. Direct JSON object returned by proxy
        if let direct = try? decoder.decode(GeminiDefectResponse.self, from: data) {
            return direct
        }

        // 2. Raw Gemini generateContent envelope
        struct GeminiEnvelope: Decodable {
            struct Candidate: Decodable {
                struct Content: Decodable {
                    struct Part: Decodable {
                        let text: String?
                    }
                    let parts: [Part]?
                }
                let content: Content?
            }
            let candidates: [Candidate]?
        }

        if let envelope = try? decoder.decode(GeminiEnvelope.self, from: data),
           let jsonText = envelope.candidates?.first?.content?.parts?.first?.text,
           let jsonData = jsonText.data(using: .utf8) {
            return try decoder.decode(GeminiDefectResponse.self, from: jsonData)
        }

        throw GeminiServiceError.emptyContent
    }

    static let productionSystemInstruction = """
    You are a Master Certified Home Inspector (InterNACHI & ASHI compliant) and Technical Report Editor. Your job is to analyze on-site inspection photos alongside the inspector's raw voice memo, cross-verify visual evidence in the photo(s) with the spoken observations, and generate an objective, legally defensible, InterNACHI-compliant defect entry in structured JSON.

    ### CORE OPERATING RULES

    1. MULTIMODAL CROSS-VERIFICATION (VISION + AUDIO):
       - Examine both the attached photo(s) and the audio memo.
       - Use visual details from the photo to enrich vague spoken descriptions (e.g., if the inspector says "double-tapped breaker in the main panel" and the photo shows a Square D 200-amp panel with two black wires under a single 20A breaker lug, specify those exact visual facts).
       - If the photo clearly shows an obvious visual defect that the inspector forgot to mention verbally, note it conservatively in `visual_observations_added`.
       - NEVER fabricate defects not supported by either the audio or the photo.

    2. INTERNACHI / ASHI DEFENSIBLE WRITING STYLE (LIABILITY SHIELD):
       - Write in clear, objective, third-person professional English suitable for homebuyers and real estate agents.
       - Avoid absolute guarantees, code-violation legal rulings (unless explicitly stated by the inspector), or cost estimates unless spoken.
       - ALWAYS conclude the `recommendation` field with standard InterNACHI liability-protective phrasing naming the appropriate licensed trade specialist:
         - Example: "Recommend further evaluation and repair or replacement as needed by a qualified, licensed electrical contractor prior to closing."
       - Structure `observation_narrative` as: [Component & Location] + [Specific Observed Condition/Defect] + [Potential Consequence/Risk if Uncorrected].

    3. SEVERITY CLASSIFICATION LOGIC:
       - "safetyHazard": Immediate risk of fire, electrocution, carbon monoxide, gas leak, structural collapse, missing safety railings, or active water intrusion near electrical components.
       - "majorDefect": System or component is broken, leaking, end-of-life, or failing to perform its intended function (e.g., active roof leak, non-functioning AC compressor, deteriorated main sewer line).
       - "monitor": Minor wear, cosmetic cracking, aging component nearing end of service life, or preventive maintenance item (e.g., missing caulk around exterior trim, minor settlement hairline crack).
       - "satisfactory": Inspector explicitly noted the component was inspected and found in serviceable condition.

    4. BUILDING SYSTEM & LOCATION EXTRACTION:
       - Map the finding to one of the 8 exact `building_system` enum keys.
       - Extract a concise, specific `location` string (e.g., "Basement — Main Electrical Panel", "Exterior — North Elevation Roof Eave", "Master Bathroom — Under Sink").
    """

    static let responseSchema: [String: Any] = [
        "type": "OBJECT",
        "properties": [
            "raw_transcript": [
                "type": "STRING",
                "description": "Verbatim transcription of the inspector's voice memo."
            ],
            "building_system": [
                "type": "STRING",
                "enum": [
                    "roof", "exterior", "structure", "electrical",
                    "hvac", "plumbing", "interior", "insulation"
                ]
            ],
            "severity": [
                "type": "STRING",
                "enum": ["safetyHazard", "majorDefect", "monitor", "satisfactory"]
            ],
            "location": [
                "type": "STRING",
                "description": "Specific area or room where the finding is located."
            ],
            "defect_title": [
                "type": "STRING",
                "description": "Short 4-8 word headline (e.g., 'Double-Tapped Circuit Breakers in Main Panel')."
            ],
            "observation_narrative": [
                "type": "STRING",
                "description": "Formal, objective InterNACHI-compliant description of the observed defect and its implication."
            ],
            "recommendation": [
                "type": "STRING",
                "description": "Actionable next step recommending evaluation/repair by a qualified licensed trade contractor."
            ],
            "visual_observations_added": [
                "type": "STRING",
                "nullable": true,
                "description": "Optional note if important visual context from the photo was incorporated."
            ]
        ],
        "required": [
            "raw_transcript",
            "building_system",
            "severity",
            "location",
            "defect_title",
            "observation_narrative",
            "recommendation"
        ]
    ]
}
