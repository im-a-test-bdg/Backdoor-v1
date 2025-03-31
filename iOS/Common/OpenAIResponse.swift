// Proprietary Software License Version 1.0
//
// Copyright (C) 2025 BDG
//
// Backdoor App Signer is proprietary software. You may not use, modify, or distribute it except as expressly permitted under the terms of the Proprietary Software License.

import Foundation
import CoreML

/// Model for AI responses - structure maintained for compatibility
struct OpenAIResponse: Codable {
    let choices: [Choice]
    let id: String?
    let model: String?

    struct Choice: Codable {
        let message: Message
        let index: Int?
        let finish_reason: String?
    }

    struct Message: Codable {
        let content: String
        let role: String?
    }

    /// Creates a response with the given content
    static func createLocal(content: String) -> OpenAIResponse {
        return OpenAIResponse(
            choices: [
                Choice(
                    message: Message(content: content, role: "assistant"),
                    index: 0,
                    finish_reason: "stop"
                ),
            ],
            id: UUID().uuidString,
            model: "backdoor-coreml-model"
        )
    }
    
    /// Creates a response from a Core ML prediction
    static func createFromCoreML(content: String, modelName: String = "BackdoorAssistant") -> OpenAIResponse {
        return OpenAIResponse(
            choices: [
                Choice(
                    message: Message(content: content, role: "assistant"),
                    index: 0,
                    finish_reason: "stop"
                ),
            ],
            id: UUID().uuidString,
            model: modelName
        )
    }
    
    /// Creates an error response
    static func createError(errorMessage: String) -> OpenAIResponse {
        return OpenAIResponse(
            choices: [
                Choice(
                    message: Message(
                        content: "I encountered an error processing your request: \(errorMessage). Please try again.",
                        role: "assistant"
                    ),
                    index: 0,
                    finish_reason: "error"
                ),
            ],
            id: UUID().uuidString,
            model: "backdoor-coreml-model"
        )
    }
}
