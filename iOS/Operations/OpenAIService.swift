// Proprietary Software License Version 1.0
//
// Copyright (C) 2025 BDG
//
// Backdoor App Signer is proprietary software. You may not use, modify, or distribute it except as expressly permitted under the terms of the Proprietary Software License.

import Foundation
import CoreML

/// Service for interacting with the built-in AI system using Core ML (maintains OpenAIService name for compatibility)
final class OpenAIService {
    // Singleton instance for app-wide use
    static let shared = OpenAIService()

    private init() {
        Debug.shared.log(message: "Initializing Core ML-powered AI service with OpenAIService wrapper", type: .info)
        
        // Verify Core ML model integrity
        let modelVerified = CustomAIService.shared.verifyModelIntegrity()
        Debug.shared.log(message: "Core ML model integrity check: \(modelVerified ? "Passed" : "Failed")", type: .info)
    }

    /// This method is maintained for backward compatibility but has no effect with the Core ML implementation
    func updateAPIKey(_: String) {
        Debug.shared.log(message: "API key updates not required for Core ML AI", type: .debug)
    }

    enum ServiceError: Error, LocalizedError {
        case invalidURL
        case invalidAPIKey
        case networkError(Error)
        case decodingError(Error)
        case noData
        case rateLimitExceeded
        case serverError(Int)
        case processingError(String)

        var errorDescription: String? {
            switch self {
                case .invalidURL:
                    return "Invalid API URL"
                case .invalidAPIKey:
                    return "API key error. Please contact support."
                case let .networkError(error):
                    return "Network error: \(error.localizedDescription)"
                case let .decodingError(error):
                    return "Failed to process AI response: \(error.localizedDescription)"
                case .noData:
                    return "No response received from AI service"
                case .rateLimitExceeded:
                    return "AI service rate limit exceeded. Please try again later."
                case let .serverError(code):
                    return "AI service error (code: \(code)). Please try again later."
                case let .processingError(reason):
                    return "Processing error: \(reason)"
            }
        }
    }

    // Maintained for compatibility with existing code
    struct AIMessagePayload {
        let role: String
        let content: String
    }

    func getAIResponse(messages: [AIMessagePayload], context: AppContext, completion: @escaping (Result<String, ServiceError>) -> Void) {
        // Log that we're using the Core ML implementation
        Debug.shared.log(message: "Processing AI request with Core ML implementation", type: .info)

        // Convert OpenAIService.AIMessagePayload to CustomAIService.AIMessagePayload
        let customMessages = messages.map { CustomAIService.AIMessagePayload(role: $0.role, content: $0.content) }

        // Delegate to our custom implementation with the converted messages
        CustomAIService.shared.getAIResponse(messages: customMessages, context: context) { result in
            switch result {
                case let .success(response):
                    // Record successful response for learning if it's a user-assistant exchange
                    if let lastUserMessage = messages.last(where: { $0.role == "user" })?.content {
                        // Assume the response was helpful (can be refined with user feedback)
                        CustomAIService.shared.provideResponseFeedback(for: lastUserMessage, response: response, wasHelpful: true)
                    }
                    
                    completion(.success(response))
                    
                case let .failure(customError):
                    // Map the custom error to the compatible error type
                    switch customError {
                        case let .processingError(reason):
                            completion(.failure(.processingError(reason)))
                        case .contextMissing:
                            completion(.failure(.processingError("App context missing")))
                    }
            }
        }
    }
    
    /// Provide feedback about AI responses for model improvement
    func provideFeedback(userMessage: String, aiResponse: String, wasHelpful: Bool) {
        CustomAIService.shared.provideResponseFeedback(
            for: userMessage,
            response: aiResponse,
            wasHelpful: wasHelpful
        )
    }
}
