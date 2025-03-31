// Proprietary Software License Version 1.0
//
// Copyright (C) 2025 BDG
//
// Backdoor App Signer is proprietary software. You may not use, modify, or distribute it except as expressly permitted under the terms of the Proprietary Software License.

import CoreML
import Foundation
import NaturalLanguage

/// CoreMLAIIntegration provides an interface to integrate CoreML models into the app's AI system
class CoreMLAIIntegration {
    // Singleton instance
    static let shared = CoreMLAIIntegration()
    
    // Track whether CoreML is initialized
    private var isInitialized = false
    
    // Track which models we've attempted to load
    private var modelLoadAttempted: [CoreMLManager.ModelType: Bool] = [:]
    
    private init() {
        Debug.shared.log(message: "CoreMLAIIntegration initializing", type: .info)
    }
    
    /// Initialize the CoreML integration
    func initialize() {
        // Ensure we only initialize once
        guard !isInitialized else { return }
        
        // Load essential models
        preloadEssentialModels()
        
        // Add observers for app state changes
        setupObservers()
        
        isInitialized = true
        Debug.shared.log(message: "CoreMLAIIntegration initialized", type: .info)
    }
    
    /// Preload essential CoreML models for immediate use
    private func preloadEssentialModels() {
        let essentialModels: [CoreMLManager.ModelType] = [.intentClassifier]
        
        for modelType in essentialModels {
            modelLoadAttempted[modelType] = true
            
            // Start loading the model
            CoreMLManager.shared.loadModel(for: modelType) { (result: Result<MLModel, Error>) in
                switch result {
                case .success(_):
                    Debug.shared.log(message: "Successfully preloaded \(modelType.rawValue) model", type: .info)
                    
                    // Notify that on-device AI is ready
                    DispatchQueue.main.async {
                        NotificationCenter.default.post(
                            name: NSNotification.Name("OnDeviceAIStatusChanged"),
                            object: nil,
                            userInfo: ["available": true]
                        )
                    }
                    
                case .failure(let error):
                    Debug.shared.log(message: "Failed to preload \(modelType.rawValue) model: \(error)", type: .warning)
                    
                    // Try to download if not available
                    self.downloadModelIfNeeded(modelType)
                }
            }
        }
    }
    
    /// Process text using CoreML for intent classification
    func processTextWithCoreML(text: String, completion: @escaping (Result<(intent: String, confidence: Float), Error>) -> Void) {
        // First try to use the CoreML model
        CoreMLManager.shared.classifyIntent(text: text) { result in
            switch result {
            case .success(let intent):
                // Log the intent recognition
                Debug.shared.log(message: "CoreML classified intent as: \(intent)", type: .debug)
                
                // Return with high confidence since we used CoreML
                completion(.success((intent: intent, confidence: 0.85)))
                
            case .failure(let error):
                // Log the error
                Debug.shared.log(message: "CoreML intent classification failed: \(error)", type: .warning)
                
                // Fall back to basic classification
                let basicIntent = self.fallbackIntentClassification(text: text)
                completion(.success((intent: basicIntent, confidence: 0.6)))
            }
        }
    }
    
    /// Enhance a response using CoreML
    func enhanceResponseWithCoreML(
        baseResponse: String,
        context: String,
        completion: @escaping (Result<String, Error>) -> Void
    ) {
        CoreMLManager.shared.enhanceResponse(baseResponse: baseResponse, context: context) { result in
            switch result {
            case .success(let enhancedResponse):
                completion(.success(enhancedResponse))
            case .failure(let error):
                Debug.shared.log(message: "CoreML response enhancement failed: \(error)", type: .warning)
                completion(.success(baseResponse)) // Fall back to the original response
            }
        }
    }
    
    /// Analyze text sentiment using CoreML
    func analyzeSentimentWithCoreML(text: String, completion: @escaping (Result<String, Error>) -> Void) {
        CoreMLManager.shared.analyzeSentiment(text: text, completion: completion)
    }
    
    // MARK: - Model Management
    
    /// Download a model if it's not already available
    func downloadModelIfNeeded(_ modelType: CoreMLManager.ModelType) {
        // Check if we've already attempted to download this model
        guard modelLoadAttempted[modelType] != true else { return }
        
        modelLoadAttempted[modelType] = true
        
        // Check if the model is available
        if !CoreMLManager.shared.isModelAvailable(modelType) {
            Debug.shared.log(message: "Downloading \(modelType.rawValue) model", type: .info)
            
            // Notify UI that a download is starting
            DispatchQueue.main.async {
                NotificationCenter.default.post(
                    name: NSNotification.Name("MLModelDownloadStarted"),
                    object: nil,
                    userInfo: ["modelType": modelType]
                )
            }
            
            // Start the download
            CoreMLManager.shared.downloadModel(for: modelType) { success in
                if success {
                    Debug.shared.log(message: "Successfully downloaded \(modelType.rawValue) model", type: .info)
                    
                    // Notify that on-device AI status might have changed
                    DispatchQueue.main.async {
                        NotificationCenter.default.post(
                            name: NSNotification.Name("OnDeviceAIStatusChanged"),
                            object: nil
                        )
                    }
                } else {
                    Debug.shared.log(message: "Failed to download \(modelType.rawValue) model", type: .error)
                }
                
                // Notify UI that download finished
                DispatchQueue.main.async {
                    NotificationCenter.default.post(
                        name: NSNotification.Name("MLModelDownloadFinished"),
                        object: nil,
                        userInfo: [
                            "modelType": modelType,
                            "success": success
                        ]
                    )
                }
            }
        }
    }
    
    /// Download all available models
    func downloadAllModels() {
        for modelType in CoreMLManager.ModelType.allCases {
            downloadModelIfNeeded(modelType)
        }
    }
    
    // MARK: - Observers
    
    private func setupObservers() {
        // Observe when app comes to foreground
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(appDidBecomeActive),
            name: UIApplication.didBecomeActiveNotification,
            object: nil
        )
        
        // Observe when app has good connectivity (could check Reachability here)
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(connectivityChanged),
            name: NSNotification.Name("ConnectivityStatusChanged"),
            object: nil
        )
    }
    
    @objc private func appDidBecomeActive() {
        // Check for model updates when app becomes active
        for modelType in CoreMLManager.ModelType.allCases {
            // Only try to download if not already available
            if !CoreMLManager.shared.isModelAvailable(modelType) {
                downloadModelIfNeeded(modelType)
            }
        }
    }
    
    @objc private func connectivityChanged(_ notification: Notification) {
        if let isConnected = notification.userInfo?["isConnected"] as? Bool, isConnected {
            // We have connectivity, try to download missing models
            for modelType in CoreMLManager.ModelType.allCases {
                if !CoreMLManager.shared.isModelAvailable(modelType) {
                    downloadModelIfNeeded(modelType)
                }
            }
        }
    }
    
    // MARK: - Fallback methods
    
    /// Basic intent classification as a fallback when CoreML fails
    private func fallbackIntentClassification(text: String) -> String {
        let lowercasedText = text.lowercased()
        
        // Simple rule-based classification
        if lowercasedText.contains("sign") || lowercasedText.contains("certificate") {
            return "sign_app"
        } else if lowercasedText.contains("navigate") || lowercasedText.contains("go to") {
            return "navigation"
        } else if lowercasedText.contains("install") || lowercasedText.contains("download") {
            return "install_app"
        } else if lowercasedText.contains("source") || lowercasedText.contains("repo") {
            return "source_management"
        } else if lowercasedText.contains("help") {
            return "help"
        }
        
        return "conversation"
    }
}
