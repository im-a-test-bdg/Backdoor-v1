// Proprietary Software License Version 1.0
//
// Copyright (C) 2025 BDG
//
// Backdoor App Signer is proprietary software. You may not use, modify, or distribute it except as expressly permitted under the terms of the Proprietary Software License.

import CoreML
import Foundation
import NaturalLanguage
import UIKit

/// Custom AI service that uses CoreML for on-device intelligence when available
final class CustomAIService {
    // Singleton instance for app-wide use
    static let shared = CustomAIService()
    
    // Flag to track if CoreML integration is initialized
    private var isCoreMLInitialized = false
    
    // Mode tracking - whether we're using on-device ML or cloud-based processing
    enum ProcessingMode {
        case onDevice
        case hybrid
        case cloud
        
        var displayName: String {
            switch self {
            case .onDevice: return "On-Device Intelligence"
            case .hybrid: return "Hybrid Processing"
            case .cloud: return "Cloud Processing"
            }
        }
        
        var iconName: String {
            switch self {
            case .onDevice: return "brain"
            case .hybrid: return "brain.head.profile"
            case .cloud: return "cloud"
            }
        }
    }
    
    // Current processing mode
    private var _currentMode: ProcessingMode = .cloud
    var currentMode: ProcessingMode {
        get {
            // Check if CoreML is available and models are loaded
            if CoreMLManager.shared.isOnDeviceIntelligenceAvailable() {
                return .onDevice
            } else if isCoreMLInitialized {
                return .hybrid
            } else {
                return .cloud
            }
        }
    }

    private init() {
        Debug.shared.log(message: "Initializing custom AI service with CoreML support", type: .info)
        
        // Initialize CoreML integration
        initializeCoreML()
        
        // Setup observers for CoreML status changes
        setupObservers()
    }
    
    private func initializeCoreML() {
        // Initialize CoreML integration in the background
        DispatchQueue.global(qos: .userInitiated).async {
            CoreMLAIIntegration.shared.initialize()
            
            DispatchQueue.main.async {
                self.isCoreMLInitialized = true
                
                // Notify UI that AI mode has changed
                NotificationCenter.default.post(
                    name: NSNotification.Name("AIProcessingModeChanged"),
                    object: nil,
                    userInfo: ["mode": self.currentMode]
                )
                
                Debug.shared.log(message: "CoreML integration initialized", type: .info)
            }
        }
    }
    
    private func setupObservers() {
        // Observe when on-device AI status changes
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(onDeviceAIStatusChanged),
            name: NSNotification.Name("OnDeviceAIStatusChanged"),
            object: nil
        )
    }
    
    @objc private func onDeviceAIStatusChanged() {
        // Notify UI that AI mode has changed
        DispatchQueue.main.async {
            NotificationCenter.default.post(
                name: NSNotification.Name("AIProcessingModeChanged"),
                object: nil,
                userInfo: ["mode": self.currentMode]
            )
        }
    }

    enum ServiceError: Error, LocalizedError {
        case processingError(String)
        case contextMissing
        case modelError(Error)

        var errorDescription: String? {
            switch self {
                case let .processingError(reason):
                    return "Processing error: \(reason)"
                case .contextMissing:
                    return "App context is missing or invalid"
                case let .modelError(error):
                    return "ML model error: \(error.localizedDescription)"
            }
        }
    }

    // Maintained for compatibility with existing code
    struct AIMessagePayload {
        let role: String
        let content: String
    }

    /// Process user input and generate an AI response
    func getAIResponse(messages: [AIMessagePayload], context: AppContext, completion: @escaping (Result<String, ServiceError>) -> Void) {
        // Log the request
        Debug.shared.log(message: "Processing AI request with \(messages.count) messages using mode: \(currentMode)", type: .info)

        // Get the user's last message
        guard let lastUserMessage = messages.last(where: { $0.role == "user" })?.content else {
            completion(.failure(.processingError("No user message found")))
            return
        }

        // Use a background thread for processing to keep UI responsive
        DispatchQueue.global(qos: .userInitiated).async {
            // First, determine intent using CoreML if available
            self.analyzeIntentWithCoreML(message: lastUserMessage) { intentResult in
                // Get conversation history for context
                let conversationContext = self.extractConversationContext(messages: messages)
                
                // Determine sentiment with CoreML if available
                self.analyzeSentimentWithCoreML(message: lastUserMessage) { sentimentResult in
                    let sentiment = sentimentResult.flatMap { $0 } ?? "neutral"
                    Debug.shared.log(message: "Message sentiment detected: \(sentiment)", type: .debug)
                    
                    // Generate response based on intent and context
                    let baseResponse = self.generateResponse(
                        intentData: intentResult,
                        userMessage: lastUserMessage,
                        conversationHistory: messages,
                        conversationContext: conversationContext,
                        appContext: context,
                        sentiment: sentiment
                    )
                    
                    // Enhance response with CoreML if available
                    if self.currentMode == .onDevice || self.currentMode == .hybrid {
                        CoreMLAIIntegration.shared.enhanceResponseWithCoreML(
                            baseResponse: baseResponse,
                            context: conversationContext
                        ) { enhanceResult in
                            switch enhanceResult {
                            case .success(let enhancedResponse):
                                // Add a small delay to simulate processing time
                                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                                    completion(.success(enhancedResponse))
                                }
                            case .failure(let error):
                                // Fall back to base response
                                Debug.shared.log(message: "Response enhancement failed: \(error)", type: .warning)
                                DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) {
                                    completion(.success(baseResponse))
                                }
                            }
                        }
                    } else {
                        // We're in cloud mode, use base response with a delay
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) {
                            completion(.success(baseResponse))
                        }
                    }
                }
            }
        }
    }
    
    // Extract meaningful context from conversation history
    private func extractConversationContext(messages: [AIMessagePayload]) -> String {
        // Get the last 5 messages for context (or fewer if there aren't 5)
        let contextMessages = messages.suffix(min(5, messages.count))
        
        return contextMessages.map { "\($0.role): \($0.content)" }.joined(separator: "\n")
    }

    // MARK: - CoreML Integration
    
    /// Analyze intent using CoreML if available
    private func analyzeIntentWithCoreML(message: String, completion: @escaping ((intent: String, confidence: Float)?) -> Void) {
        // Only use CoreML if we're in onDevice or hybrid mode
        if currentMode == .onDevice || currentMode == .hybrid {
            CoreMLAIIntegration.shared.processTextWithCoreML(text: message) { result in
                switch result {
                case .success(let intentData):
                    completion(intentData)
                case .failure(let error):
                    Debug.shared.log(message: "CoreML intent analysis failed: \(error)", type: .warning)
                    completion(nil)
                }
            }
        } else {
            // We're in cloud mode, use fallback method
            completion(nil)
        }
    }
    
    /// Analyze sentiment using CoreML if available
    private func analyzeSentimentWithCoreML(message: String, completion: @escaping (Result<String, Error>?) -> Void) {
        // Only use CoreML if we're in onDevice or hybrid mode
        if currentMode == .onDevice || currentMode == .hybrid {
            CoreMLAIIntegration.shared.analyzeSentimentWithCoreML(text: message) { result in
                completion(result)
            }
        } else {
            // We're in cloud mode, return nil
            completion(nil)
        }
    }

    // MARK: - Intent Analysis

    private enum MessageIntent {
        case question(topic: String)
        case appNavigation(destination: String)
        case appInstall(appName: String)
        case appSign(appName: String)
        case sourceAdd(url: String)
        case generalHelp
        case greeting
        case unknown
    }

    private func analyzeUserIntent(message: String) -> MessageIntent {
        let lowercasedMessage = message.lowercased()

        // Check for greetings
        if lowercasedMessage.contains("hello") || lowercasedMessage.contains("hi ") || lowercasedMessage == "hi" || lowercasedMessage.contains("hey") {
            return .greeting
        }

        // Check for help requests
        if lowercasedMessage.contains("help") || lowercasedMessage.contains("how do i") || lowercasedMessage.contains("how to") {
            return .generalHelp
        }

        // Use regex patterns to identify specific intents
        if let match = lowercasedMessage.range(of: "sign\\s+(the\\s+)?app\\s+(?:called\\s+|named\\s+)?([^?]+)", options: .regularExpression) {
            let appName = String(lowercasedMessage[match]).replacing(regularExpression: "sign\\s+(the\\s+)?app\\s+(?:called\\s+|named\\s+)?", with: "").trimmingCharacters(in: .whitespacesAndNewlines)
            return .appSign(appName: appName)
        }

        if let match = lowercasedMessage.range(of: "(?:go\\s+to|navigate\\s+to|open|show)\\s+(?:the\\s+)?([^?]+?)\\s+(?:tab|screen|page|section)", options: .regularExpression) {
            let destination = String(lowercasedMessage[match]).replacing(regularExpression: "(?:go\\s+to|navigate\\s+to|open|show)\\s+(?:the\\s+)?|\\s+(?:tab|screen|page|section)", with: "").trimmingCharacters(in: .whitespacesAndNewlines)
            return .appNavigation(destination: destination)
        }

        if let match = lowercasedMessage.range(of: "add\\s+(?:a\\s+)?(?:new\\s+)?source\\s+(?:with\\s+url\\s+|at\\s+|from\\s+)?([^?]+)", options: .regularExpression) {
            let url = String(lowercasedMessage[match]).replacing(regularExpression: "add\\s+(?:a\\s+)?(?:new\\s+)?source\\s+(?:with\\s+url\\s+|at\\s+|from\\s+)?", with: "").trimmingCharacters(in: .whitespacesAndNewlines)
            return .sourceAdd(url: url)
        }

        if let match = lowercasedMessage.range(of: "install\\s+(?:the\\s+)?app\\s+(?:called\\s+|named\\s+)?([^?]+)", options: .regularExpression) {
            let appName = String(lowercasedMessage[match]).replacing(regularExpression: "install\\s+(?:the\\s+)?app\\s+(?:called\\s+|named\\s+)?", with: "").trimmingCharacters(in: .whitespacesAndNewlines)
            return .appInstall(appName: appName)
        }

        // If it contains a question mark, assume it's a question
        if lowercasedMessage.contains("?") {
            // Extract topic from question
            let topic = lowercasedMessage.replacing(regularExpression: "\\?|what|how|when|where|why|who|is|are|can|could|would|will|should", with: "").trimmingCharacters(in: .whitespacesAndNewlines)
            return .question(topic: topic)
        }

        // Default case
        return .unknown
    }

    // MARK: - Response Generation

    private func generateResponse(
        intentData: (intent: String, confidence: Float)?,
        userMessage: String,
        conversationHistory: [AIMessagePayload],
        conversationContext: String,
        appContext: AppContext,
        sentiment: String
    ) -> String {
        // First, use CoreML intent if available and with high confidence
        let intent: MessageIntent
        
        if let intentData = intentData, intentData.confidence > 0.7 {
            // Map CoreML intent to our MessageIntent enum
            switch intentData.intent {
            case "sign_app":
                // Extract app name
                if let appName = extractParameter(from: userMessage, type: "app") {
                    intent = .appSign(appName: appName)
                } else {
                    intent = .appSign(appName: "the selected app")
                }
            case "navigation":
                // Extract destination
                if let destination = extractParameter(from: userMessage, type: "destination") {
                    intent = .appNavigation(destination: destination)
                } else {
                    intent = .appNavigation(destination: "home")
                }
            case "install_app":
                // Extract app name
                if let appName = extractParameter(from: userMessage, type: "app") {
                    intent = .appInstall(appName: appName)
                } else {
                    intent = .appInstall(appName: "the selected app")
                }
            case "source_management":
                // Extract URL
                if let url = extractParameter(from: userMessage, type: "url") {
                    intent = .sourceAdd(url: url)
                } else {
                    intent = .sourceAdd(url: "the provided URL")
                }
            case "help":
                intent = .generalHelp
            case "conversation":
                // Fall back to our own intent analysis for conversation
                intent = analyzeUserIntent(message: userMessage)
            default:
                // Unrecognized CoreML intent, use our own analysis
                intent = analyzeUserIntent(message: userMessage)
            }
        } else {
            // CoreML intent not available or low confidence, use our own analysis
            intent = analyzeUserIntent(message: userMessage)
        }
        
        // Get context information
        let contextInfo = appContext.currentScreen
        // Get available commands for use in help responses
        let commandsList = AppContextManager.shared.availableCommands()
        
        // Get additional context from the app
        let additionalContext = CustomAIContextProvider.shared.getContextSummary()
        
        // Generate response based on intent and sentiment
        let sentimentAdjustment = sentiment == "negative" ? 
            "I understand you might be frustrated. " : 
            (sentiment == "positive" ? "Great! " : "")

        switch intent {
            case .greeting:
                return "\(sentimentAdjustment)Hello! I'm your Backdoor assistant with on-device ML capabilities. I can help you sign apps, manage sources, and navigate through the app. How can I assist you today?"

            case .generalHelp:
                let availableCommandsText = commandsList.isEmpty ?
                    "" :
                    "\n\nAvailable commands: " + commandsList.joined(separator: ", ")

                return """
                \(sentimentAdjustment)I'm here to help you with Backdoor! Here are some things I can do:

                • Sign apps with your certificates
                • Add new sources for app downloads
                • Help you navigate through different sections
                • Install apps from your sources
                • Provide information about Backdoor's features\(availableCommandsText)

                What would you like help with specifically?
                """

            case let .question(topic):
                // Handle different topics the user might ask about
                if topic.contains("certificate") || topic.contains("cert") {
                    return "\(sentimentAdjustment)Certificates are used to sign apps so they can be installed on your device. You can manage your certificates in the Settings tab. If you need to add a new certificate, go to Settings > Certificates and tap the + button. Would you like me to help you navigate there? [navigate to:certificates]"
                } else if topic.contains("sign") {
                    return "\(sentimentAdjustment)To sign an app, first navigate to the Library tab where your downloaded apps are listed. Select the app you want to sign, then tap the Sign button. Make sure you have a valid certificate set up first. Would you like me to help you navigate to the Library? [navigate to:library]"
                } else if topic.contains("source") || topic.contains("repo") {
                    return "\(sentimentAdjustment)Sources are repositories where you can find apps to download. To add a new source, go to the Sources tab and tap the + button. Enter the URL of the source you want to add. Would you like me to help you navigate to the Sources tab? [navigate to:sources]"
                } else if topic.contains("backdoor") || topic.contains("app") {
                    return "\(sentimentAdjustment)Backdoor is an app signing tool that allows you to sign and install apps using your own certificates. It helps you manage app sources, download apps, and sign them for installation on your device. \(additionalContext) Is there something specific about Backdoor you'd like to know?"
                } else if topic.contains("coreml") || topic.contains("machine learning") || topic.contains("ml") || topic.contains("ai") {
                    return "\(sentimentAdjustment)Backdoor now uses Core ML for on-device intelligence! This provides faster responses, better privacy, and works even when you're offline. The AI assistant can understand your questions, classify intents, and generate responses directly on your device. Currently using: \(currentMode.displayName)."
                } else {
                    // General response when we don't have specific information about the topic
                    return "\(sentimentAdjustment)That's a good question about \(topic). Based on the current state of the app, I can see you're on the \(contextInfo) screen. \(additionalContext) Would you like me to help you navigate somewhere specific or perform an action related to your question?"
                }

            case let .appNavigation(destination):
                return "\(sentimentAdjustment)I'll help you navigate to the \(destination) section. [navigate to:\(destination)]"

            case let .appSign(appName):
                return "\(sentimentAdjustment)I'll help you sign the app \"\(appName)\". Let's get started with the signing process. [sign app:\(appName)]"

            case let .appInstall(appName):
                return "\(sentimentAdjustment)I'll help you install \"\(appName)\". First, let me check if it's available in your sources. [install app:\(appName)]"

            case let .sourceAdd(url):
                return "\(sentimentAdjustment)I'll add the source from \"\(url)\" to your repositories. [add source:\(url)]"

            case .unknown:
                // Extract any potential commands from the message using regex
                let commandPattern = "(sign|navigate to|install|add source)\\s+([\\w\\s.:/\\-]+)"
                if let match = userMessage.range(of: commandPattern, options: .regularExpression) {
                    let commandText = String(userMessage[match])
                    let components = commandText.split(separator: " ", maxSplits: 1).map(String.init)

                    if components.count == 2 {
                        let command = components[0]
                        let parameter = components[1].trimmingCharacters(in: .whitespacesAndNewlines)

                        return "\(sentimentAdjustment)I'll help you with that request. [\(command):\(parameter)]"
                    }
                }

                // Check if the message contains keywords related to app functionality
                let appKeywords = ["sign", "certificate", "source", "install", "download", "app", "library", "settings"]
                let containsAppKeywords = appKeywords.contains { userMessage.lowercased().contains($0) }
                
                if containsAppKeywords {
                    return """
                    \(sentimentAdjustment)I understand you need assistance with Backdoor. Based on your current context (\(contextInfo)), here are some actions I can help with:

                    - Sign apps
                    - Install apps
                    - Add sources
                    - Navigate to different sections

                    \(additionalContext)
                    
                    Please let me know specifically what you'd like to do.
                    """
                } else {
                    // For completely unrelated queries, provide a friendly response
                    return """
                    \(sentimentAdjustment)I'm your Backdoor assistant, focused on helping you with app signing, installation, and management. 
                    
                    \(additionalContext)
                    
                    If you have questions about using Backdoor, I'm here to help! What would you like to know about the app?
                    """
                }
        }
    }
    
    // Helper method to extract parameters from user messages
    private func extractParameter(from message: String, type: String) -> String? {
        let lowercasedMessage = message.lowercased()
        
        switch type {
        case "app":
            // Try to extract app name
            if let match = lowercasedMessage.range(of: "(sign|install)\\s+(the\\s+)?app\\s+(?:called\\s+|named\\s+)?([^?.,]+)", options: .regularExpression) {
                if let appNameRange = lowercasedMessage[match].range(of: "(?:called\\s+|named\\s+)?([^?.,]+)$", options: .regularExpression) {
                    return String(lowercasedMessage[appNameRange]).replacing(regularExpression: "called\\s+|named\\s+", with: "").trimmingCharacters(in: .whitespacesAndNewlines)
                }
            }
            
        case "destination":
            // Try to extract destination
            if let match = lowercasedMessage.range(of: "(?:go\\s+to|navigate\\s+to|open|show)\\s+(?:the\\s+)?([^?.,]+?)\\s+(?:tab|screen|page|section)", options: .regularExpression) {
                if let destRange = lowercasedMessage[match].range(of: "(?:the\\s+)?([^?.,]+?)\\s+(?:tab|screen|page|section)$", options: .regularExpression) {
                    return String(lowercasedMessage[destRange]).replacing(regularExpression: "the\\s+|\\s+(?:tab|screen|page|section)$", with: "").trimmingCharacters(in: .whitespacesAndNewlines)
                }
            }
            
        case "url":
            // Try to extract URL
            if let match = lowercasedMessage.range(of: "(?:add|with|from)\\s+(?:a\\s+)?(?:new\\s+)?(?:source\\s+)?(?:with\\s+url\\s+|at\\s+|from\\s+)?([^\\s]+\\.[^\\s]+)", options: .regularExpression) {
                if let urlRange = lowercasedMessage[match].range(of: "([^\\s]+\\.[^\\s]+)$", options: .regularExpression) {
                    return String(lowercasedMessage[urlRange]).trimmingCharacters(in: .whitespacesAndNewlines)
                }
            }
            
        default:
            return nil
        }
        
        return nil
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
