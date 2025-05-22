import { NativeModules, Platform } from 'react-native';
import { NativeEventEmitter } from 'react-native';
import React from 'react';

const LINKING_ERROR =
  `The package 'react-native-leenphone' doesn't seem to be linked. Make sure: \n\n` +
  Platform.select({ ios: "- You have run 'pod install'\n", default: '' }) +
  '- You rebuilt the app after installing the package\n' +
  '- You are not using Expo managed workflow\n';

const Sip = NativeModules.Sip
  ? NativeModules.Sip
  : new Proxy(
      {},
      {
        get() {
          throw new Error(LINKING_ERROR);
        },
      }
    );

export enum TransportType {
  Udp = 0,
  Tcp = 1,
  Tls = 2,
  Dtls = 3,
}

interface Callbacks {
  // First state an outgoing call will go through
  onConnectionRequested?: () => void;

  // First state an outgoing call will go through
  onCallRequested?: () => void;

  // Once remote accepts, ringing will commence (180 response)
  onCallRinging?: () => void;
  onCallConnected?: () => void;

  // This state indicates the call is active.
  // You may reach this state multiple times, for example after a pause/resume
  // or after the ICE negotiation completes
  // Wait for the call to be connected before allowing a call update
  onCallStreamsRunning?: () => void;
  onCallPaused?: () => void;
  onCallPausedByRemote?: () => void;

  // When we request a call update, for example when toggling video
  onCallUpdating?: () => void;
  onCallUpdatedByRemote?: () => void;
  onCallReleased?: () => void;
  onCallError?: () => void;
  onCallEnd?: () => void;
  onCallPushIncomingReceived?: () => void;
  onAccountRegistrationStateChanged?: (param: any) => void;
  onIncomingReceived?:() => void;
  onAudioDevicesChanged?: (param: any) => void;
}

export async function initialise(): Promise<void> {
  return Sip.initialise();
}

export async function unregister(): Promise<void> {
  return Sip.unregister();
}

export function login(
  username: string,
  password: string,
  domain: string,
  transport: TransportType
): Promise<void> {
  return Sip.login(username, password, domain, transport);
}

export function useCall(callbacks: Callbacks = {}): void {
  React.useEffect(() => {
    // console.log('Initialising phone')
    const eventEmitter = new NativeEventEmitter(Sip);

    const eventListeners = Object.entries(callbacks).map(
      ([event, callback]) => {
        return eventEmitter.addListener(event.slice(2), callback);
      }
    );
    return () => eventListeners.forEach((listener) => listener.remove());
  }, []);
}

export async function call(remoteUri: string): Promise<void> {
  return Sip.outgoingCall(remoteUri);
}

export async function accept(): Promise<void> {
  return Sip.accept();
}

export async function decline(): Promise<void> {
  return Sip.decline();
}

export async function hangup(): Promise<void> {
  return Sip.hangUp();
}

export async function sendDtmf(dtmf: string): Promise<void> {
  return Sip.sendDtmf(dtmf);
}

export type AudioDevice = 'bluetooth' | 'phone' | 'loudspeaker';

export interface AudioDevices {
  options: { [device in AudioDevice]: boolean };
  current: AudioDevice;
}

export type AudioDeviceType =
  | 'Unknown'
  | 'Microphone'
  | 'Earpiece'
  | 'Speaker'
  | 'Bluetooth'
  | 'BluetoothA2DP'
  | 'Telephony'
  | 'AuxLine'
  | 'GenericUsb'
  | 'Headset'
  | 'Headphones'
  | 'HearingAid';

export type CustomAudioDevice = {
  id: string;
  name: string;
  driverName: string;
  capabilities: AudioDeviceCapabilities;
  type: AudioDeviceType;
};

export type AudioDeviceCapabilities =
  | 'CapabilityRecord'
  | 'CapabilityPlay'
  | 'CapabilityAll';

export type GetAudioDevices = {
  devices: AudioDevice[];
  currentOutput: string;
  currentInput: string;
  muted: boolean;
};

export function useAudioDevices(
  callback: (device: AudioDevices) => void
): void {
  const scanAudioDevices = React.useCallback(
    () => Sip.scanAudioDevices().then(callback),
    [callback]
  );

  React.useEffect(() => {
    const eventEmitter = new NativeEventEmitter(Sip);

    const deviceListener = eventEmitter.addListener(
      'AudioDevicesChanged',
      scanAudioDevices
    );
    return () => deviceListener.remove();
  }, []);

  React.useEffect(() => {
    scanAudioDevices();
  }, []);
}

export async function setAudioDevice(device: AudioDevice) {
  if (device === 'bluetooth') return Sip.bluetoothAudio();
  if (device === 'loudspeaker') return Sip.loudAudio();
  if (device === 'phone') return Sip.phoneAudio();
}

export async function getMicStatus(): Promise<boolean> {
  return Sip.micEnabled();
}

export async function toggleMute(): Promise<boolean> {
  return Sip.toggleMute();
}

export async function getAudioDevices(): Promise<GetAudioDevices> {
  return Sip.getAudioDevices();
}

export type ChangeAudioDevice = {
  message: string;
  id: string
}

export async function changeAudioDevice(deviceId: string): Promise<ChangeAudioDevice> {
  return Sip.changeAudioDevice(deviceId);
}