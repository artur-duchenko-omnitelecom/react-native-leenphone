import React
import linphonesw

@objc(Sip)
class Sip: RCTEventEmitter {
    private var mCore: Core!
    private var mRegistrationDelegate: CoreDelegate!

    private var bluetoothMic: AudioDevice?
    private var bluetoothSpeaker: AudioDevice?
    private var earpiece: AudioDevice?
    private var loudMic: AudioDevice?
    private var loudSpeaker: AudioDevice?
    private var microphone: AudioDevice?

    var isCallIncoming: Bool = false
    var isCallRunning: Bool = false

    /*------------ Callkit tutorial related variables ---------------*/
    let incomingCallName = "Incoming call example"
    var mCall: Call?
    var mProviderDelegate: CallKitProviderDelegate!
    var mCallAlreadyStopped: Bool = false

    func stopCall() {
        // Call has been terminated by any side

        // Report to CallKit that the call is over, if the terminate action was initiated by other end of the call
        if self.isCallRunning {
            self.mProviderDelegate.stopCall()
        }
    }

    @objc func delete() {
        // To completely remove an Account
        if let account = mCore.defaultAccount {
            mCore.removeAccount(account: account)

            // To remove all accounts use
            mCore.clearAccounts()

            // Same for auth info
            mCore.clearAllAuthInfo()
        }
    }

    @objc func sendEvent(eventName: String, body: NSDictionary? = nil) {
        self.sendEvent(withName: eventName, body: body)
    }

    @objc(initialise:withRejecter:)
    func initialise(resolve: RCTPromiseResolveBlock, reject: RCTPromiseRejectBlock) {
        do {
            LoggingService.Instance.logLevel = LogLevel.Warning

            try? mCore = Factory.Instance.createCore(
                configPath: "", factoryConfigPath: "", systemContext: nil)
            mProviderDelegate = CallKitProviderDelegate(context: self)
            mCore.callkitEnabled = true
            mCore.pushNotificationEnabled = true

            try? mCore.setProvisioninguri(newValue: "https://api.tokomni.cc/provision/linphone.xml")
            try? mCore.start()

            // Create a Core listener to listen for the callback we need
            // In this case, we want to know about the account registration status
            mRegistrationDelegate = CoreDelegateStub(
                onCallStateChanged: {
                    (
                        core: Core,
                        call: Call,
                        state: Call.State?,
                        message: String
                    ) in
                    switch state {
                    case .IncomingReceived:
                        // Immediately hang up when we receive a call. There's nothing inherently wrong with this
                        // but we don't need it right now, so better to leave it deactivated.
                        // If app is in foreground, it's likely that we will receive the SIP invite before the Push notification
                        if !self.isCallIncoming {
                            self.mCall = call
                            self.isCallIncoming = true
                            self.mProviderDelegate.incomingCall()
                        }
                        self.sendEvent(eventName: "IncomingReceived")

                    case .OutgoingInit:
                        // First state an outgoing call will go through
                        if !self.isCallIncoming {
                            self.mCall = call
                            self.isCallIncoming = true
                        }
                        self.sendEvent(eventName: "ConnectionRequested")
                    case .OutgoingProgress:
                        // First state an outgoing call will go through
                        self.sendEvent(eventName: "CallRequested")
                    case .OutgoingRinging:
                        // Once remote accepts, ringing will commence (180 response)
                        self.sendEvent(eventName: "CallRinging")
                    case .Connected:
                        self.isCallIncoming = false
                        self.isCallRunning = true

                        self.sendEvent(eventName: "CallConnected")
                    case .StreamsRunning:
                        // This state indicates the call is active.
                        // You may reach this state multiple times, for example after a pause/resume
                        // or after the ICE negotiation completes
                        // Wait for the call to be connected before allowing a call update
                        self.sendEvent(eventName: "CallStreamsRunning")
                    case .Paused:
                        self.sendEvent(eventName: "CallPaused")
                    case .PausedByRemote:
                        self.sendEvent(eventName: "CallPausedByRemote")
                    case .Updating:
                        // When we request a call update, for example when toggling video
                        self.sendEvent(eventName: "CallUpdating")
                    case .UpdatedByRemote:
                        self.sendEvent(eventName: "CallUpdatedByRemote")
                    case .Released:
                        self.sendEvent(eventName: "CallReleased")
                        self.stopCall()
                    case .Error:
                        self.sendEvent(eventName: "CallError")
                        self.stopCall()
                    case .End:
                        self.sendEvent(eventName: "CallEnd")
                        self.stopCall()
                    case .PushIncomingReceived:
                        self.mCall = call
                        self.isCallIncoming = true
                        self.mProviderDelegate.incomingCall()
                        self.sendEvent(eventName: "CallPushIncomingReceived")
                    default:
                        NSLog("")
                    }
                },
                onAudioDevicesListUpdated: { (core: Core) in
                    self.sendEvent(eventName: "AudioDevicesChanged")
                },
                onAccountRegistrationStateChanged: {
                    (
                        core: Core,
                        account: Account,
                        state: RegistrationState,
                        message: String
                    ) in
                    let coreMap: NSDictionary = [
                        "accountCreatorUrl": core.accountCreatorUrl,
                        "adaptiveRateAlgorithm": core.adaptiveRateAlgorithm,
                        "httpProxyHost": core.httpProxyHost,
                        "identity": core.identity,
                        "stunServer": core.stunServer,
                        "mediaDevice": core.mediaDevice,
                        "primaryContact": core.primaryContact,
                        "remoteRingbackTone": core.remoteRingbackTone,
                        "provisioningUri": core.provisioningUri,
                        "rootCa": core.rootCa,
                        "tlsCert": core.tlsCert,
                        "tlsCertPath": core.tlsCertPath,
                        "tlsKey": core.tlsKey,
                        "tlsKeyPath": core.tlsKeyPath,
                    ]

                    let accountMap: NSDictionary = [
                        "contactAddressDomain": account.contactAddress?.domain as Any,
                        "contactAddressUsername": account.contactAddress?.username as Any,
                        "contactAddressDisplayName": account.contactAddress?.displayName as Any,
                        "contactAddressPassword": account.contactAddress?.password as Any,
                    ]

                    let body: NSDictionary = [
                        "core": coreMap, "account": accountMap, "state": String(describing: state),
                        "message": message,
                    ]
                    self.sendEvent(eventName: "AccountRegistrationStateChanged", body: body)

                })
            mCore.addDelegate(delegate: mRegistrationDelegate)
            resolve(true)
        }
    }

    @objc(login:withPassword:withDomain:withTransport:withResolver:withRejecter:)
    func login(
        username: String, password: String, domain: String, transport: Int,
        resolve: RCTPromiseResolveBlock, reject: RCTPromiseRejectBlock
    ) {
        do {
            var _transport = TransportType.Tcp
            if transport == 0 { _transport = TransportType.Udp }
            if transport == 2 { _transport = TransportType.Tls }
            if transport == 3 { _transport = TransportType.Dtls }

            // To configure a SIP account, we need an Account object and an AuthInfo object
            // The first one is how to connect to the proxy server, the second one stores the credentials

            // The auth info can be created from the Factory as it's only a data class
            // userID is set to null as it's the same as the username in our case
            // ha1 is set to null as we are using the clear text password. Upon first register, the hash will be computed automatically.
            // The realm will be determined automatically from the first register, as well as the algorithm
            let authInfo = try Factory.Instance.createAuthInfo(
                username: username, userid: "", passwd: password, ha1: "", realm: "", domain: domain
            )

            // Account object replaces deprecated ProxyConfig object
            // Account object is configured through an AccountParams object that we can obtain from the Core
            let accountParams = try mCore.createAccountParams()

            // A SIP account is identified by an identity address that we can construct from the username and domain
            let identity = try Factory.Instance.createAddress(
                addr: String("sip:" + username + "@" + domain))
            try! accountParams.setIdentityaddress(newValue: identity)

            // We also need to configure where the proxy server is located
            let address = try Factory.Instance.createAddress(addr: String("sip:" + domain))

            // We use the Address object to easily set the transport protocol
            try address.setTransport(newValue: _transport)
            try accountParams.setServeraddress(newValue: address)

            // And we ensure the account will start the registration process
            accountParams.registerEnabled = true
            accountParams.realm = "*"
            accountParams.pushNotificationAllowed = true
            accountParams.pushNotificationConfig?.provider = "apns.dev"

            mCore.setUserAgent(
                name: "tokomni",
                version: "V2.0.0"
            )

            // Now that our AccountParams is configured, we can create the Account object
            let account = try mCore.createAccount(params: accountParams)

            // Now let's add our objects to the Core
            mCore.addAuthInfo(info: authInfo)
            try mCore.addAccount(account: account)

            // Also set the newly added account as default
            mCore.defaultAccount = account

            resolve(nil)

        } catch {
            NSLog(error.localizedDescription)
            reject("Login error", "Could not log in", error)
        }
    }

    @objc(bluetoothAudio:withRejecter:)
    func bluetoothAudio(resolve: RCTPromiseResolveBlock, reject: RCTPromiseRejectBlock) {
        if let mic = self.bluetoothMic {
            mCore.inputAudioDevice = mic
        }

        if let speaker = self.bluetoothSpeaker {
            mCore.outputAudioDevice = speaker
        }

        resolve(true)
    }

    @objc
    override func supportedEvents() -> [String]! {
        return [
            "ConnectionRequested", "CallRequested", "CallRinging", "CallConnected",
            "CallStreamsRunning", "CallPaused", "CallPausedByRemote", "CallUpdating",
            "CallUpdatedByRemote", "CallReleased", "CallError", "AudioDevicesChanged",
            "CallEnd", "CallPushIncomingReceived", "AccountRegistrationStateChanged",
            "IncomingReceived",
        ]
    }

    @objc(unregister:withRejecter:)
    func unregister(resolve: RCTPromiseResolveBlock, reject: RCTPromiseRejectBlock) {
        // Here we will disable the registration of our Account
        if let account = mCore.defaultAccount {

            let params = account.params
            // Returned params object is const, so to make changes we first need to clone it
            let clonedParams = params?.clone()

            // Now let's make our changes
            clonedParams?.registerEnabled = false

            // And apply them
            account.params = clonedParams
            mCore.removeAccount(account: account)
            mCore.clearAllAuthInfo()
        }
    }

    @objc(hangUp:withRejecter:)
    func hangUp(resolve: RCTPromiseResolveBlock, reject: RCTPromiseRejectBlock) {
        NSLog("Trying to hang up")
        do {
            if mCore.callsNb == 0 { return }

            // If the call state isn't paused, we can get it using core.currentCall
            // If the call state isn't paused, we can get it using core.currentCall
            self.mCall = (mCore.currentCall != nil) ? mCore.currentCall : mCore.calls[0]

            // Terminating a call is quite simple
            if let call = self.mCall {
                try call.terminate()
            } else {
                reject("No call", "No call to terminate", nil)
            }
        } catch {
            NSLog(error.localizedDescription)
            reject("Call termination failed", "Call termination failed", error)

        }
    }

    @objc(decline:withRejecter:)
    func decline(resolve: RCTPromiseResolveBlock, reject: RCTPromiseRejectBlock) {
        NSLog("Trying to decline call")
        do {
            guard let call = mCore.currentCall else {
                reject("No call", "No call to decline", nil)
                return
            }
            try call.decline(reason: Reason.Busy)
            self.mProviderDelegate.stopCall()
            resolve(nil)
        } catch {
            NSLog("Decline error: \(error.localizedDescription)")
            reject("Call decline failed", "Call decline failed", error)
        }
    }

    @objc(accept:withRejecter:)
    func accept(resolve: RCTPromiseResolveBlock, reject: RCTPromiseRejectBlock) {
        NSLog("Trying to accept call")
        do {
            guard let call = mCore.currentCall else {
                reject("No call", "No call to accept", nil)
                return
            }

            // Configure audio session before accepting call
            mCore.configureAudioSession()

            try call.accept()
            self.mProviderDelegate.acceptCall()
            resolve(nil)
        } catch {
            NSLog("Accept error: \(error.localizedDescription)")
            reject("Call accept failed", "Call accept failed", error)
        }
    }

    @objc(loudAudio:withRejecter:)
    func loudAudio(resolve: RCTPromiseResolveBlock, reject: RCTPromiseRejectBlock) {
        if let mic = loudMic {
            mCore.inputAudioDevice = mic
        } else if let mic = self.microphone {
            mCore.inputAudioDevice = mic
        }

        if let speaker = loudSpeaker {
            mCore.outputAudioDevice = speaker
        }

        resolve(true)
    }

    @objc(micEnabled:withRejecter:)
    func micEnabled(resolve: RCTPromiseResolveBlock, reject: RCTPromiseRejectBlock) {
        resolve(mCore.micEnabled)
    }

    @objc(outgoingCall:withResolver:withRejecter:)
    func outgoingCall(
        recipient: String, resolve: RCTPromiseResolveBlock, reject: RCTPromiseRejectBlock
    ) {
        do {
            // As for everything we need to get the SIP URI of the remote and convert it to an Address
            let remoteAddress = try Factory.Instance.createAddress(addr: recipient)

            // We also need a CallParams object
            // Create call params expects a Call object for incoming calls, but for outgoing we must use null safely
            let params = try mCore.createCallParams(call: nil)

            // We can now configure it
            // Here we ask for no encryption but we could ask for ZRTP/SRTP/DTLS
            params.mediaEncryption = MediaEncryption.None
            // If we wanted to start the call with video directly
            //params.videoEnabled = true
            let callId = UUID()
            params.addCustomHeader(headerName: "Call-ID", headerValue: callId.uuidString)

            // Finally we start the call
            let _ = mCore.inviteAddressWithParams(addr: remoteAddress, params: params)

            mProviderDelegate.outgoingCall(uuid: callId, handle: recipient)
            // Call process can be followed in onCallStateChanged callback from core listener
            resolve(nil)
        } catch {
            NSLog(error.localizedDescription)
            reject("Outgoing call failure", "Something has gone wrong", error)
        }
    }

    @objc(phoneAudio:withRejecter:)
    func phoneAudio(resolve: RCTPromiseResolveBlock, reject: RCTPromiseRejectBlock) {
        if let mic = microphone {
            mCore.inputAudioDevice = mic
        }

        if let speaker = earpiece {
            mCore.outputAudioDevice = speaker
        }

        resolve(true)
    }

    @objc(scanAudioDevices:withRejecter:)
    func scanAudioDevices(resolve: RCTPromiseResolveBlock, reject: RCTPromiseRejectBlock) {
        microphone = nil
        earpiece = nil
        loudSpeaker = nil
        loudMic = nil
        bluetoothSpeaker = nil
        bluetoothMic = nil

        for audioDevice in mCore.audioDevices {
            switch audioDevice.type {
            case .Microphone:
                microphone = audioDevice
            case .Earpiece:
                earpiece = audioDevice
            case .Speaker:
                if audioDevice.hasCapability(capability: AudioDeviceCapabilities.CapabilityPlay) {
                    loudSpeaker = audioDevice
                } else {
                    loudMic = audioDevice
                }
            case .Bluetooth:
                if audioDevice.hasCapability(capability: AudioDeviceCapabilities.CapabilityPlay) {
                    bluetoothSpeaker = audioDevice
                } else {
                    bluetoothMic = audioDevice
                }
            default:
                NSLog("Audio device not recognised.")
            }
        }

        let options: NSDictionary = [
            "phone": earpiece != nil && microphone != nil,
            "bluetooth": bluetoothMic != nil || bluetoothSpeaker != nil,
            "loudspeaker": loudSpeaker != nil,
        ]

        var current = "phone"
        if mCore.outputAudioDevice?.type == .Bluetooth || mCore.inputAudioDevice?.type == .Bluetooth
        {
            current = "bluetooth"
        } else if mCore.outputAudioDevice?.type == .Speaker {
            current = "loudspeaker"
        }

        let result: NSDictionary = [
            "current": current,
            "options": options,
        ]
        resolve(result)
    }

    @objc(getAudioDevices:withRejecter:)
    func getAudioDevices(
        _ resolver: @escaping RCTPromiseResolveBlock,
        reject rejecter: @escaping RCTPromiseRejectBlock
    ) {

        var values: [[String: String]] = []

        for device in mCore.audioDevices {
            let capabilities = {
                switch device.capabilities {
                case .CapabilityPlay:
                    return "CapabilityPlay"
                case .CapabilityRecord:
                    return "CapabilityRecord"
                default:
                    return "CapabilityAll"
                }
            }()

            let mappedDevice: [String: String] = [
                "name": device.deviceName,
                "driverName": device.driverName,
                "id": device.id,
                "type": String(
                    describing: device.type
                ),
                "capabilities": capabilities,
            ]

            values.append(
                mappedDevice
            )
        }

        let returned: [String: Any] = [
            "devices": values,
            "currentOutput": mCore.currentCall?.outputAudioDevice?.id ?? "",
            "currentInput": mCore.currentCall?.inputAudioDevice?.id ?? "",
            "muted": !mCore.micEnabled,
        ]
        resolver(
            returned
        )
    }

    @objc(changeAudioDevice:withResolver:withRejector:)
    func changeAudioDevice(
        _ id: String,
        resolve resolver: @escaping RCTPromiseResolveBlock,
        reject rejecter: @escaping RCTPromiseRejectBlock
    ) {
        guard let currentCall = mCore.currentCall else {
            rejecter("no-call", "No current call to set audio device", nil)
            return
        }

        guard let newDevice = mCore.audioDevices.first(where: { $0.id == id }) else {
            rejecter("no-device", "No device with id \(id) found", nil)
            return
        }

        if newDevice.id == currentCall.outputAudioDevice?.id {
            resolver(["message": "Device already selected", "id": id])
            return
        }

        self.configureAudioSession()

        currentCall.outputAudioDevice = newDevice

        if newDevice.capabilities.contains(.CapabilityAll) {
            currentCall.inputAudioDevice = newDevice
        }

        self.sendEvent(
            withName: "callstate",
            body: [
                "message": newDevice.id,
                "state": "audiodevicechange",
            ]
        )

        resolver(["message": "Device set", "id": id])
    }

    @objc(sendDtmf:withResolver:withRejecter:)
    func sendDtmf(dtmf: String, resolve: RCTPromiseResolveBlock, reject: RCTPromiseRejectBlock) {
        do {
            try mCore.currentCall?.sendDtmf(dtmf: dtmf.utf8CString[0])
            resolve(true)
        } catch {
            reject("DTMF not recognised", "DTMF not recognised", error)
        }
    }

    @objc(toggleMute:withRejecter:)
    func toggleMute(resolve: RCTPromiseResolveBlock, reject: RCTPromiseRejectBlock) {
        mCore.micEnabled = !mCore.micEnabled
        resolve(mCore.micEnabled)
    }

    func configureAudioSession() {
        mCore.configureAudioSession()
    }
    func activateAudioSession(actived: Bool) {
        mCore.activateAudioSession(actived: actived)
    }

}
