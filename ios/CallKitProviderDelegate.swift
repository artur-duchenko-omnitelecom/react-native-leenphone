//
//  ProviderDelegate.swift
//  CallTutorial
//
//  Created by QuentinArguillere on 05/08/2020.
//  Copyright © 2020 BelledonneCommunications. All rights reserved.
//

import AVFoundation
import CallKit
import Foundation
import linphonesw

class CallKitProviderDelegate: NSObject {
    private let provider: CXProvider
    let mCallController = CXCallController()
    var tutorialContext: Sip!

    var callUUID: UUID!

    init(context: Sip) {
        tutorialContext = context
        let providerConfiguration = CXProviderConfiguration(
            localizedName: Bundle.main.infoDictionary!["CFBundleName"] as! String)
        providerConfiguration.supportsVideo = false
        providerConfiguration.supportedHandleTypes = [.generic]

        providerConfiguration.maximumCallsPerCallGroup = 1
        providerConfiguration.maximumCallGroups = 1

        provider = CXProvider(configuration: providerConfiguration)
        super.init()
        provider.setDelegate(self, queue: nil)  // The CXProvider delegate will trigger CallKit related callbacks

    }

    func incomingCall() {
        callUUID = UUID()
        let update = CXCallUpdate()
        update.remoteHandle = CXHandle(type: .generic, value: tutorialContext.incomingCallName)

        provider.reportNewIncomingCall(
            with: callUUID, update: update, completion: { error in })  // Report to CallKit a call is incoming
    }

    func outgoingCall(uuid: UUID, handle: String) {
        let handle = CXHandle(type: .generic, value: handle)
        let startCallAction: CXStartCallAction = CXStartCallAction(call: uuid, handle: handle)
        let transaction = CXTransaction(action: startCallAction)

        let update = CXCallUpdate()
        update.remoteHandle = handle
        update.supportsHolding = true
        update.supportsDTMF = true
        update.hasVideo = false

        callUUID = uuid

        provider.reportCall(with: callUUID, updated: update)

        mCallController.request(transaction) { error in
            if let error = error {
                NSLog("Failed to report outgoing call to CallKit: \(error.localizedDescription)")
            } else {
                NSLog("Outgoing call reported to CallKit.")
            }
        }
    }

    // Accept incoming call
    func acceptCall() {
        guard let uuid = callUUID else {
            print("❌ callUUID is nil. Cannot accept call.")
            return
        }

        let acceptCallAction = CXAnswerCallAction(call: uuid)
        let transaction = CXTransaction(action: acceptCallAction)

        mCallController.request(transaction) { error in
            if let error = error {
                print("❌ Error accepting call: \(error.localizedDescription)")
            } else {
                print("✅ Call accepted")
            }
        }
    }

    // End/decline call
    func stopCall() {
        guard let uuid = callUUID else {
            print("❌ callUUID is nil. Cannot end call.")
            return
        }

        let endCallAction = CXEndCallAction(call: uuid)
        let transaction = CXTransaction(action: endCallAction)

        mCallController.request(transaction) { error in
            if let error = error {
                print("❌ Error ending call: \(error.localizedDescription)")
            } else {
                print("✅ Call ended")
            }
        }
    }
}

// In this extension, we implement the action we want to be done when CallKit is notified of something.
// This can happen through the CallKit GUI in the app, or directly in the code (see, incomingCall(), stopCall() functions above)
extension CallKitProviderDelegate: CXProviderDelegate {

    func provider(_ provider: CXProvider, perform action: CXEndCallAction) {
        do {
            if tutorialContext.mCall?.state != .End && tutorialContext.mCall?.state != .Released {
                try tutorialContext.mCall?.terminate()
            } else if tutorialContext.mCall?.state == .OutgoingRinging {
                tutorialContext.declineCall()
            }
        } catch { NSLog(error.localizedDescription) }

        tutorialContext.isCallRunning = false
        tutorialContext.isCallIncoming = false
        action.fulfill()
    }

    func provider(_ provider: CXProvider, perform action: CXAnswerCallAction) {
        do {
            // The audio stream is going to start shortly: the AVAudioSession must be configured now.
            // It is worth to note that an application does not have permission to configure the
            // AVAudioSession outside of this delegate action while it is running in background,
            // which is usually the case in an incoming call scenario.
            tutorialContext.acceptCall()
        } catch {
            print(error)
        }
        action.fulfill()
    }

    func provider(_ provider: CXProvider, perform action: CXSetHeldCallAction) {}
    func provider(_ provider: CXProvider, perform action: CXStartCallAction) {
        // This tutorial is not doing outgoing calls. If it had to do so,
        // configureAudioSession() shall be called from here, just before launching the
        // call.
        tutorialContext.configureAudioSession()
        action.fulfill()
    }
    func provider(_ provider: CXProvider, perform action: CXSetMutedCallAction) {
        tutorialContext.toggleMute(
            resolve: { result in
                print("Mute call success: \(result ?? "no result")")
            },
            reject: { code, message, error in
                print("Mute call failed: \(message ?? "Unknown error")")
            })
        action.fulfill()
    }
    func provider(_ provider: CXProvider, perform action: CXPlayDTMFCallAction) {}
    func provider(_ provider: CXProvider, timedOutPerforming action: CXAction) {}
    func providerDidReset(_ provider: CXProvider) {}

    func provider(_ provider: CXProvider, didActivate audioSession: AVAudioSession) {
        // The linphone Core must be notified that CallKit has activated the AVAudioSession
        // in order to start streaming audio.
        tutorialContext.activateAudioSession(actived: true)
    }

    func provider(_ provider: CXProvider, didDeactivate audioSession: AVAudioSession) {
        // The linphone Core must be notified that CallKit has deactivated the AVAudioSession.
        tutorialContext.activateAudioSession(actived: false)
    }
}
