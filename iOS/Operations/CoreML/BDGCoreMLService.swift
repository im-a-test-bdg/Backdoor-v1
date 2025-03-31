// Proprietary Software License Version 1.0
//
// Copyright (C) 2025 BDG
//
// Backdoor App Signer is proprietary software. You may not use, modify, or distribute it except as expressly permitted under the terms of the Proprietary Software License.

import Foundation
import CoreML
import NaturalLanguage

/// Main service that interfaces between the app and Core ML backend
final class BDGCoreMLService {
    // MARK: - Singleton
    
    static let shared = BDGCoreMLService()
    
    // MARK: - Properties
    
    /// Queue to manage feedback processing
    private let feedbackQueue = DispatchQueue(label: "com.backdoor.coreml.feedback", qos: .background)
    
    /// Feedback buffer to collect items for periodic model updates
    private var feedbackBuffer: [(input: String, response: String)] = []
    
    /// Limit for feedback buffer before triggering model update
    private let feedbackUpdateThreshold = 20
    
    // MARK: - Initialization
    
    private init() {
        Debug.shared.log(message: "BDG Core ML Service initialized", type: .info)
        
        // Schedule periodic feedback processing
        scheduleFeedbackProcessing()
    }
    
    // MARK: - Public API
    
    /// Process a user message and generate a response
    func processMessage(message: String, conversationHistory: [String], context: AppContext, completion: @escaping (Result<String, Error>) -> Void) {
        // Extract intent from the message to provide additional context
        let intent = CoreMLContextEncoder.shared.encodeUserIntent(message)
        
        // Check for explicit commands in the message
        if let commandInfo = extractCommand(from: message) {
            Debug.shared.log(message: "Extracted command: \(commandInfo.command) with parameter: \(commandInfo.parameter)", type: .debug)
            
            // Pass to command execution directly
            AppContextManager.shared.executeCommand(commandInfo.command, parameter: commandInfo.parameter) { result in
                switch result {
                    case let .successWithResult(response):
                        // Add this as a successful command execution for learning
                        self.recordCommandSuccess(message: message, command: commandInfo.command, parameter: commandInfo.parameter)
                        
                        // Return the command execution result
                        completion(.success("Command executed: \(response)"))
                        
                    case let .unknownCommand(command):
                        // Fall back to natural language response
                        Debug.shared.log(message: "Unknown command, falling back to natural language response", type: .debug)
                        self.generateNaturalLanguageResponse(message: message, intent: intent, conversationHistory: conversationHistory, context: context, completion: completion)
                }
            }
        } else {
            // Analyze for intent
            let intentInfo = AppContextManager.shared.processUserInput(message)
            
            if intentInfo?.confidence ?? 0 > 0.7 {
                // High confidence in intent recognition, try to execute as command
                AppContextManager.shared.executeCommand(intentInfo!.intent, parameter: intentInfo!.parameter) { result in
                    switch result {
                        case let .successWithResult(response):
                            // Add this as a successful intent recognition for learning
                            self.recordIntentSuccess(message: message, intent: intentInfo!.intent, parameter: intentInfo!.parameter)
                            
                            // Return the command execution result
                            completion(.success(response))
                            
                        case .unknownCommand:
                            // Fall back to natural language response
                            self.generateNaturalLanguageResponse(message: message, intent: intent, conversationHistory: conversationHistory, context: context, completion: completion)
                    }
                }
            } else {
                // No clear command or low confidence, use natural language processing
                generateNaturalLanguageResponse(message: message, intent: intent, conversationHistory: conversationHistory, context: context, completion: completion)
            }
        }
    }
    
    /// Add feedback for model improvement
    func addFeedback(userMessage: String, assistantResponse: String, wasHelpful: Bool) {
        feedbackQueue.async {
            // Only use positive feedback for learning
            if wasHelpful {
                self.feedbackBuffer.append((input: userMessage, response: assistantResponse))
                
                // Check if we've reached the threshold for model update
                if self.feedbackBuffer.count >= self.feedbackUpdateThreshold {
                    self.processFeedbackBuffer()
                }
            }
        }
    }
    
    // MARK: - Private Methods
    
    /// Generate a natural language response using Core ML
    private func generateNaturalLanguageResponse(message: String, intent: String, conversationHistory: [String], context: AppContext, completion: @escaping (Result<String, Error>) -> Void) {
        // Augment the user message with intent information
        let augmentedMessage = "INTENT:\(intent) MESSAGE:\(message)"
        
        // Generate response using Core ML
        CoreMLModelHandler.shared.generateResponse(
            userInput: augmentedMessage,
            context: context,
            conversationHistory: conversationHistory
        ) { result in
            switch result {
                case .success(let response):
                    // Post-process the response
                    let processedResponse = self.processResponseForCommands(response)
                    completion(.success(processedResponse))
                    
                case .failure(let error):
                    // Handle errors intelligently
                    if let coreMLError = error as? CoreMLError {
                        // Use fallback for specific CoreML errors
                        let fallbackResponse = self.getFallbackResponse(for: coreMLError, message: message, context: context)
                        completion(.success(fallbackResponse))
                    } else {
                        // Pass through general errors
                        completion(.failure(error))
                    }
            }
        }
    }
    
    /// Extract command from message if present
    private func extractCommand(from message: String) -> (command: String, parameter: String)? {
        // Look for [command:parameter] pattern
        let pattern = "\\[(.*?):(.*?)\\]"
        guard let regex = try? NSRegularExpression(pattern: pattern) else {
            return nil
        }
        
        let nsString = message as NSString
        let matches = regex.matches(in: message, range: NSRange(location: 0, length: nsString.length))
        
        if let match = matches.first, match.numberOfRanges >= 3 {
            let commandRange = match.range(at: 1)
            let parameterRange = match.range(at: 2)
            
            let command = nsString.substring(with: commandRange).lowercased()
            let parameter = nsString.substring(with: parameterRange)
            
            return (command: command, parameter: parameter)
        }
        
        return nil
    }
    
    /// Process response to ensure any commands are properly formatted
    private func processResponseForCommands(_ response: String) -> String {
        // Ensure command placeholders are properly formatted with brackets
        let pattern = "(command|navigate to|sign app|add source|install app|list|help)(\\s+|:)([^\\[\\]]+)"
        let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive])
        
        guard let regex = regex else { return response }
        
        let nsString = response as NSString
        var processedResponse = response
        
        // Find all matches and replace with properly formatted commands
        regex.enumerateMatches(in: response, options: [], range: NSRange(location: 0, length: nsString.length)) { match, _, _ in
            guard let match = match, match.numberOfRanges >= 4 else { return }
            
            let commandTypeRange = match.range(at: 1)
            let separatorRange = match.range(at: 2)
            let parameterRange = match.range(at: 3)
            
            let fullRange = NSRange(location: match.range.location, length: match.range.length)
            let commandType = nsString.substring(with: commandTypeRange).lowercased()
            let parameter = nsString.substring(with: parameterRange).trimmingCharacters(in: .whitespacesAndNewlines)
            
            // Create properly formatted command
            let formattedCommand = "[\(commandType):\(parameter)]"
            
            // Replace in the string
            processedResponse = (processedResponse as NSString).replacingCharacters(in: fullRange, with: formattedCommand)
        }
        
        return processedResponse
    }
    
    /// Get fallback response for errors
    private func getFallbackResponse(for error: CoreMLError, message: String, context: AppContext) -> String {
        switch error {
            case .modelNotLoaded:
                return "I'm still initializing my knowledge base. Please try again in a moment."
                
            case .invalidResponse:
                return "I apologize, but I couldn't generate a proper response. Can you rephrase your question?"
                
            case .contextEncodingFailed:
                return "I'm having trouble processing the current app context. Let me focus on your specific question instead. How can I help you?"
                
            case .unknownPredictionError:
                // For unknown errors, try to give a helpful response based on the screen
                let screen = context.currentScreen
                return "I encountered an issue processing your request. I see you're on the \(screen) screen. Can I help you with something related to that?"
        }
    }
    
    // MARK: - Feedback Processing
    
    /// Schedule periodic feedback processing
    private func scheduleFeedbackProcessing() {
        // Process feedback every hour to update the model
        Timer.scheduledTimer(withTimeInterval: 3600, repeats: true) { [weak self] _ in
            self?.processFeedbackBuffer()
        }
    }
    
    /// Process the feedback buffer to update the model
    private func processFeedbackBuffer() {
        feedbackQueue.async {
            guard !self.feedbackBuffer.isEmpty else { return }
            
            Debug.shared.log(message: "Processing \(self.feedbackBuffer.count) feedback items for model improvement", type: .info)
            
            // Process each feedback item
            for feedback in self.feedbackBuffer {
                CoreMLModelHandler.shared.addFeedback(
                    userInput: feedback.input,
                    expectedResponse: feedback.response
                )
            }
            
            // Clear the buffer
            self.feedbackBuffer.removeAll()
            
            // Initiate model update if we have enough data
            // This is handled internally by CoreMLModelHandler
        }
    }
    
    /// Record successful command execution for learning
    private func recordCommandSuccess(message: String, command: String, parameter: String) {
        feedbackQueue.async {
            let feedbackInput = message
            let expectedResponse = "[\(command):\(parameter)]"
            
            self.feedbackBuffer.append((input: feedbackInput, response: expectedResponse))
        }
    }
    
    /// Record successful intent recognition for learning
    private func recordIntentSuccess(message: String, intent: String, parameter: String) {
        feedbackQueue.async {
            let feedbackInput = message
            
            // Create an appropriate response format for the intent
            var expectedResponse = "INTENT:\(intent)"
            if !parameter.isEmpty {
                expectedResponse += " PARAMETER:\(parameter)"
            }
            
            self.feedbackBuffer.append((input: feedbackInput, response: expectedResponse))
        }
    }
}
