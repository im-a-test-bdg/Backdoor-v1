// Proprietary Software License Version 1.0
//
// Copyright (C) 2025 BDG
//
// Backdoor App Signer is proprietary software. You may not use, modify, or distribute it except as expressly permitted under the terms of the Proprietary Software License.

import Foundation

/// Adapter class that connects the existing OpenAIService interface to our new CoreML implementation
final class CoreMLServiceAdapter {
    // MARK: - Singleton
    
    static let shared = CoreMLServiceAdapter()
    
    // MARK: - Initialization
    
    private init() {
        Debug.shared.log(message: "Core ML Service Adapter initialized", type: .info)
    }
    
    // MARK: - Adapter Methods
    
    /// Process a request through the Core ML service while maintaining compatibility with OpenAIService
    func processRequest(messages: [OpenAIService.AIMessagePayload], context: AppContext, completion: @escaping (Result<String, OpenAIService.ServiceError>) -> Void) {
        // Extract the conversation history from messages
        let conversationHistory = messages.map { "\($0.role): \($0.content)" }
        
        // Get the user's most recent message
        guard let userMessage = messages.last(where: { $0.role == "user" })?.content else {
            completion(.failure(.processingError("No user message found")))
            return
        }
        
        // Use the Core ML service to process the message
        BDGCoreMLService.shared.processMessage(
            message: userMessage,
            conversationHistory: conversationHistory,
            context: context
        ) { result in
            switch result {
                case .success(let response):
                    completion(.success(response))
                    
                case .failure(let error):
                    // Map Core ML errors to OpenAIService errors for compatibility
                    if let coreMLError = error as? CoreMLError {
                        switch coreMLError {
                            case .modelNotLoaded:
                                completion(.failure(.processingError("AI model is initializing")))
                            case .invalidResponse:
                                completion(.failure(.processingError("Invalid AI response")))
                            case .contextEncodingFailed:
                                completion(.failure(.processingError("Context processing failed")))
                            case .unknownPredictionError:
                                completion(.failure(.processingError("Unknown AI processing error")))
                        }
                    } else {
                        // General error handling
                        completion(.failure(.processingError(error.localizedDescription)))
                    }
            }
        }
        
        // Collect feedback for model improvement if this is not the first message
        if messages.count > 2 {
            // Find the most recent assistant response before this user message
            if let lastAssistantMessage = messages.last(where: { $0.role == "assistant" })?.content,
               let secondLastUserMessage = messages.dropLast().last(where: { $0.role == "user" })?.content {
                
                // Record this interaction for learning (assume it was helpful since the user continued the conversation)
                BDGCoreMLService.shared.addFeedback(
                    userMessage: secondLastUserMessage,
                    assistantResponse: lastAssistantMessage,
                    wasHelpful: true
                )
            }
        }
    }
}
