// Proprietary Software License Version 1.0
//
// Copyright (C) 2025 BDG
//
// Backdoor App Signer is proprietary software. You may not use, modify, or distribute it except as expressly permitted under the terms of the Proprietary Software License.

import Foundation
import UIKit
import CoreML
import NaturalLanguage

/// Custom AI service that uses Core ML for on-device AI processing
final class CustomAIService {
    // Singleton instance for app-wide use
    static let shared = CustomAIService()

    private init() {
        Debug.shared.log(message: "Initializing Core ML powered AI service", type: .info)
        
        // Initialize the Core ML components
        _ = CoreMLModelHandler.shared
        _ = CoreMLModelSecurity.shared
        _ = CoreMLContextEncoder.shared
    }

    enum ServiceError: Error, LocalizedError {
        case processingError(String)
        case contextMissing

        var errorDescription: String? {
            switch self {
                case let .processingError(reason):
                    return "Processing error: \(reason)"
                case .contextMissing:
                    return "App context is missing or invalid"
            }
        }
    }

    // Maintained for compatibility with existing code
    struct AIMessagePayload {
        let role: String
        let content: String
    }

    /// Process user input and generate an AI response using Core ML
    func getAIResponse(messages: [AIMessagePayload], context: AppContext, completion: @escaping (Result<String, ServiceError>) -> Void) {
        // Log the request
        Debug.shared.log(message: "Processing AI request with Core ML - \(messages.count) messages", type: .info)

        // Get the user's last message
        guard let lastUserMessage = messages.last(where: { $0.role == "user" })?.content else {
            completion(.failure(.processingError("No user message found")))
            return
        }

        // Ensure we have valid context
        guard context.currentScreen.isEmpty == false else {
            completion(.failure(.contextMissing))
            return
        }
        
        // Extract conversation history
        let conversationHistory = messages.map { "\($0.role): \($0.content)" }
        
        // Use Core ML service adapter for actual processing
        CoreMLServiceAdapter.shared.processRequest(messages: messages, context: context) { result in
            switch result {
                case .success(let response):
                    completion(.success(response))
                    
                case .failure(let error):
                    completion(.failure(.processingError(error.localizedDescription)))
            }
        }
    }
    
    /// Provide feedback to improve the Core ML model
    func provideResponseFeedback(for userMessage: String, response: String, wasHelpful: Bool) {
        BDGCoreMLService.shared.addFeedback(
            userMessage: userMessage,
            assistantResponse: response,
            wasHelpful: wasHelpful
        )
    }
    
    /// Check the Core ML model's health and integrity
    func verifyModelIntegrity() -> Bool {
        return CoreMLModelSecurity.shared.preventModelUpload()
    }
}

// Helper extension for string regex replacement
extension String {
    func replacing(regularExpression pattern: String, with replacement: String) -> String {
        do {
            let regex = try NSRegularExpression(pattern: pattern)
            let range = NSRange(self.startIndex..., in: self)
            return regex.stringByReplacingMatches(in: self, range: range, withTemplate: replacement)
        } catch {
            return self
        }
    }
}
