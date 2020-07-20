//
//  Discoverable.swift
//  Assistive Technology Project
//
//  Created by Ben Mechen on 03/02/2020.
//  Copyright © 2020 Team 30. All rights reserved.
//

#if canImport(UIKit)

import Foundation
import Network
import os.log
import UIKit

/// Connection protocol with set messages to interact with the corresponding server
public enum DiscoverableProtocol: String {
    /// Disconnect & shut down server
    case disconnect = "dscv_disconnect"
    /// Send greeting to server, with device name appended in the format: ":device_name"
    case discover = "dscv_discover"
    /// Handshake response received from server
    case handshake = "dscv_shake"
    /// Acknowledgment message
    case acknowledge = "dscv_ack"
}

/// Protocol for Discoverable caller to conform to in order to received updates about the connection state and strength
public protocol DiscoverableDelegate {
    /// Updates the current state of the connection
    /// - Parameter state: New state
    func connectionState(state: Discoverable.State)
    /// Updates the connection strength
    /// - Parameter strength: Strength percentage
    func connectionStrength(strength: Float)
}

/**
 Automatically discover, connect and communicate with a server comforming to the **Assistive Technology Communication Protocol** (`dscv`)
 This is based on UDP, however implements some TCP-like features to improve the connection resilience & feedback:
    * When a packet is sent to the server, the server must reply with an acknowledgement response.
    * If this acknowledgement is not received within the specified threshold (2 seconds), the strength is marked as 0. This will bring the average strength of the last 5 values down. Once the average strength is below the specified threshold (5%), the service will assume the connection has failed and will close the connetion.
    * All protocol messages relating to connecting to the server (Bonjour discovery, `discover` packets) expect a response back from the server - if the service is not discovered or a response is not received, the system will try again for a maximum of 5 seconds (Bonjour) or 5 sends (`discover`).
        * If either time out, the connection will be marked as `failed`
    * When the connection is closed, either on the client (iOS) side or server (PC) side, each will send one last dying message to the other (`disconnect`). This will shut down the other member, closing both open connections and allowing each to accept a new connection, so that they are not stuck being bound to a dead connection.
 
 Caller must conform to the DiscoverableDelegate protocol to receive status updates
 
 To use the service, either call the `connect(to host: String, on port: UInt16)` function to open a UDP connection with the server on the specified IP and port, or use the `discover(type: String)` function to automatically discover the server using Bonjour and connect to it, using the resolved host and default port 1024.
 To automatically discover the server, it must be
 advertising on the local mDNS network with the same name and type as supplied to the `discover(type: String)` function. If the service cannot find the server's advertisement within 5 seconds, the service will abort the search and return a `failed` state.
 */
public class Discoverable: NSObject {
    /// Delegate class implementing `DiscoverableDelegate` protocol. Used to send connction status updates to.
    var delegate: DiscoverableDelegate?
    /// Singleton instance to access the service from any screen
    static var shared = Discoverable()
    /// The current connection state
    var state: Discoverable.State = .disconnected
    /// Raw connection, used for sending and receiving the UDP connection component of the connection
    private var connection: NWConnection?
    /// Bonjour service browser, used for discovering the server advertising locally on the Bonjour protocol
    private var browser = NetServiceBrowser()
    /// Service given by the browser, used to resolve the server's IP address
    private var service: NetService?
    /// Custom connection queue, used to asynchronously send and received UDP packets without operating on the main thread and stopping any UI updates
    private var queue = DispatchQueue(label: "DiscoverableQueue")
    /// Number of UDP packets sent to the server
    private var sent: Float = 0.0
    /// Number of UDP packets received from the server
    private var received: Float = 0.0
    /// List of the last `n` calculated strength percentages
    private var strengthBuffer: [Float] = []
    /// The clock representing the last sent packet, awaiting a response from the server in order to kill the timer
    private var lastSentClock: Timer?
    /// Clocks currently waiting for their packets to receive a response from the server. Once a response is received, the clock is killed and removed from the list.
    private var previousClocks: [Timer] = []
    /// The number of `DiscoverableProtocol.discover` messages sent to the server. Stop trying to communicate with the server when threshold is reached
    private var discoverTimeout: Int = 0
    /// Local discovered variable, mirrored by the `NetServiceBrowserDelegateExtension`
    private var _discovered = false
    // Temporarily store port while searching for services
    private var resolverPort: UInt16?
    
    /// The state of the connection handled by the service instance
    public enum State: Equatable {
        /// Connection currently open, sending and receiving data
        case connected
        /// Connection in progress, no sending, only receiving data
        case connecting
        /// Connection disconnected, can start new connection
        case disconnected
        /// Error connecting to server, throws DiscoverableError
        case failed(DiscoverableError)
    }
    
    /// Hide initialiser from other classes so they have to used shared instance
//    fileprivate override init() {
//        super.init()
//    }

    /// Remove any timeout clocks to save memory and avoid trying to close a dead connection
    deinit {
        killClocks()
    }
    
    /// Open a Network connection and greet the server
    ///
    /// Errors passed to delegate
    /// - Parameters:
    ///   - host: IP address to connect to
    ///   - port: Port on which to bind connection
    public func connect(to host: String, on port: UInt16) {
        let host = NWEndpoint.Host(host)
        guard let port = NWEndpoint.Port(rawValue: port) else {
            return
        }
        
        self.strengthBuffer.removeAll()
        
        self.connection = NWConnection(host: host, port: port, using: .udp)
        
        self.connection?.stateUpdateHandler = { (newState) in
            switch (newState) {
            case .ready:
                guard let connection = self.connection else {
                    return
                }

                self.listen(on: connection)
                self.discoverTimeout = 0
                
                let device = UIDevice.current.name
                
                self.send(DiscoverableProtocol.discover.rawValue + ":" + device)
            case .failed(let error), .waiting(let error):
                self.handle(NWError: error)
            default:
                break
            }
        }
        
        connection?.start(queue: queue)
        
        print(" > Connection started on \(self.connection?.endpoint.debugDescription ?? "-")")
    }
    
    /// Send a message to the server on the open connection
    ///
    /// When sending a discovery message, wait 2 seconds before either trying to discover again or close the connection when the connection strength is less than threshold
    /// Errors passed to delegate
    /// - Warning: Will only send data if the connection is in the connected or connecting state
    /// - Parameter value: String to send to the server
    public func send(_ value: String) {
        guard self.state == .connected || self.state == .connecting else { return }
        guard let data = value.data(using: .utf8) else { return }
        
        self.connection?.send(content: data, completion: .contentProcessed( { error in
            if let error = error {
                self.handle(NWError: error)
                return
            }
            
            if self.state == .connected || self.state == .connecting {
                if let previousClock = self.lastSentClock {
                    self.previousClocks.append(previousClock)
                }
                
                DispatchQueue.main.async {
                    self.lastSentClock = Timer.scheduledTimer(withTimeInterval: 2.0, repeats: false) { timer in
                        // No response received after 5 seconds, update connection status
                        if self.calculateStrength(rate: 0.0) < 5 {
                            if self.state == .connecting {
                                guard self.discoverTimeout < 5 else {
                                    self.close(false, state: .failed(.connectShakeNoResponse))
                                    return
                                }
                                
                                let device = UIDevice.current.name

                                self.send(DiscoverableProtocol.discover.rawValue + ":" + device)
                                self.discoverTimeout += 1
                            } else {
                                self.close(false)
                            }
                        }
                    }
                }
            }
            
            self.sent += 1
            print(" > Sent: \(data as NSData) string: \(value)")
        }))
    }
    
    /// Close the connection
    ///
    /// Removes all timers waiting for server response
    /// - Warning: Will only close the connection if in the connected or connecting states
    /// - Parameters:
    ///   - killServer: Send shutdown command to the server to stop the application (default true)
    ///   - state: State to set the connection to once killed (default disconnected state)
    public func close(_ killServer: Bool = true, state: Discoverable.State = .disconnected) {
        guard self.state == .connected || self.state == .connecting else {
            // Connection closed already
            return
        }
//
        if killServer {
            self.send(DiscoverableProtocol.disconnect.rawValue)
        }
        self.killClocks()
        self.set(state: state)
        self.connection?.cancel()
    }
    
    /// Force service to tell delegate connection strength
    public func fetchConnectionStrength() {
        self.delegate?.connectionStrength(strength: self.strengthBuffer.average ?? 0)
    }
    
    /// Listen on open connection for incomming messages
    ///
    /// Interpret incomming messages according to DiscoverableProtocol
    /// Remove timeout
    /// Update strength
    /// Errors passed to delegate
    /// - Parameter connection: Open NWConnection to listen on
    private func listen(on connection: NWConnection) {
        connection.receiveMessage { (data, context, isComplete, error) in
            if (isComplete) {
                if let error = error {
                    self.handle(NWError: error)
                    return
                }
                
                if let data = data, let message = String(data: data, encoding: .utf8) {
                    self.received += 1
                    
                    self.killClocks()
                    
                    if message.contains(DiscoverableProtocol.handshake.rawValue) {
                        self.set(state: .connected)
                    }
                    
                    if message.contains(DiscoverableProtocol.disconnect.rawValue) {
                        self.close()
                    }
                    
                    let percent: Float = (self.received / self.sent) * 100
                    
                    print(" > Received: \(data as NSData) string: \(message) -- \(self.calculateStrength(rate: percent))% successfull transmission")
                }

                self.listen(on: connection)
            }
        }
    }
    
    /// Calculate success rate of sent packets based on acknowledgement packets received from server
    ///
    /// Average of the last 5 strength values
    /// Update the delegate with the connection strength
    /// - Parameter percent: Current success percentage calculated from the number of sent and received packets
    private func calculateStrength(rate percent: Float) -> Float {
        guard self.state == .connected else {
            self.delegate?.connectionStrength(strength: 0)
            return 0
        }
        
        self.strengthBuffer.append(percent)
        
        self.strengthBuffer = Array(self.strengthBuffer.suffix(5))
        
        let average = self.strengthBuffer.average ?? 100.0
        self.delegate?.connectionStrength(strength: average)
        return average
    }
    
    /// Remove all timeout clocks currently awaiting a response
    private func killClocks() {
        for i in 0...self.previousClocks.count {
            // Concurrency fix
            guard i < self.previousClocks.count else { return }
            self.previousClocks[i].invalidate()
            self.previousClocks.remove(at: i)
        }
    }
    
    /// Update current state and inform delegate
    /// - Parameter state: New state
    private func set(state: Discoverable.State) {
        self.state = state
        self.delegate?.connectionState(state: state)
    }
    
    /// Handle errors in the NWError format and set the service state
    /// - Parameter error: Error received from NWConnection
    private func handle(NWError error: NWError) {
        switch error {
        case .posix(let code):
            switch code {
            case .EADDRINUSE, .EADDRNOTAVAIL:
                self.state = .failed(.connectAddressUnavailable)
                self.set(state: .failed(.connectAddressUnavailable))
            case .EACCES, .EPERM:
                self.set(state: .failed(.connectPermissionDenied))
            case .EBUSY:
                self.set(state: .failed(.connectDeviceBusy))
            case .ECANCELED:
                self.set(state: .failed(.connectCanceled))
            case .ECONNREFUSED:
                self.set(state: .failed(.connectRefused))
            case .EHOSTDOWN, .EHOSTUNREACH:
                self.set(state: .failed(.connectHostDown))
            case .EISCONN:
                self.set(state: .failed(.connectAlreadyConnected))
            case .ENOTCONN:
                self.set(state: .disconnected)
            case .ETIMEDOUT:
                self.set(state: .failed(.connectTimeout))
            case .ENETDOWN, .ENETUNREACH, .ENETRESET:
                self.set(state: .failed(.connectNetworkDown))
            default:
                os_log(.error, "POSIX connection error: %@", code.rawValue)
                self.set(state: .failed(.connectOther))
            }
        default:
            self.set(state: .failed(.connectOther))
        }
    }
}

// MARK: NetService extension
extension Discoverable: NetServiceBrowserDelegate, NetServiceBrowserDelegateExtension, NetServiceDelegate {
    var discovered: Bool {
        get {
            return self._discovered
        }
        set {
            self._discovered = newValue
        }
    }
    
    /// Begin looking for the server advertising with the Bonjour protocol
    ///
    /// Set state to connecting
    /// Start browsing for services, abort the search if no service discovered after 5 seconds
    /// - Parameter type: Type of service to discover
    public func discover(type: String, on port: UInt16?) {
        self.set(state: .connecting)
        service = nil
        _discovered = false
        browser.delegate = self
        self.resolverPort = port
        browser.stop()
        browser.searchForServices(ofType: type, inDomain: "", withTimeout: 5.0)
    }
    
    // MARK: Service Discovery
    /// Browser stopped searching for service
    ///
    /// Modified to add success parameter to set state to failed if the search timed out
    /// - Parameters:
    ///   - browser: Browser instance
    ///   - success: Did the browser discover the service in time
    public func netServiceBrowserDidStopSearch(_ browser: NetServiceBrowser, success: Bool) {
        if !success {
            self.set(state: .failed(.discoverTimeout))
        }
    }
    
    /// Browser found a matching service
    ///
    /// Set discovered parameter for NetServiceBrowser for success parameter in `netServiceBrowserDidStopSearch()`
    /// Resolve server's IP
    /// - Parameters:
    ///   - browser: Browser instance
    ///   - service: Service found
    ///   - moreComing: Were more services discovered
    public func netServiceBrowser(_ browser: NetServiceBrowser, didFind service: NetService, moreComing: Bool) {
        self._discovered = true
        
        guard self.service == nil else {
            return
        }
        
        self.discovered = true
        
        self.set(state: .connecting)
        
        print("Discovered the service")
        print("- name:", service.name)
        print("- type", service.type)
        print("- domain:", service.domain)

        browser.stop()
        
        self.service = service
        self.service?.delegate = self
        self.service?.resolve(withTimeout: 5)
    }
    
    // MARK: Resolve IP Service
    /// Handle NetService errors, set connection state according to given error
    /// - Parameters:
    ///   - sender: Resolve service
    ///   - errorDict: Errors from NetService
    func netService(_ sender: NetService, didNotResolve errorDict: [String : NSNumber]) {
        for key in errorDict.keys {
            switch errorDict[key] {
            case -72002:
                self.set(state: .failed(.discoverResolveServiceNotFound))
            case -72003:
                self.set(state: .failed(.discoverResolveBusy))
            case -72004, -72006:
                self.set(state: .failed(.discoverIncorrectConfiguration))
            case -72005:
                self.set(state: .failed(.discoverResolveCanceled))
            case -72007:
                self.set(state: .failed(.discoverResolveTimeout))
            default:
                self.set(state: .failed(.discoverResolveUnknown))
            }
        }
    }
    
    /// Resolve service got an IP address of the discovered server and connect to the server at that address
    /// - Parameter sender: Resolve service
    public func netServiceDidResolveAddress(_ sender: NetService) {
        if let serviceIp = resolveIPv4(addresses: sender.addresses!) {
            self.connect(to: serviceIp, on: resolverPort ?? 1024)
        } else {
            self.set(state: .failed(.discoverResolveFailed))
        }
    }
    
    /// Get server IP address from list of address data
    /// - Parameter addresses: List of address data
    /// - Returns: Server IP address if found
    private func resolveIPv4(addresses: [Data]) -> String? {
        var result: String?

        for address in addresses {
            let data = address as NSData
            var storage = sockaddr_storage()
            data.getBytes(&storage, length: MemoryLayout<sockaddr_storage>.size)

            if Int32(storage.ss_family) == AF_INET {
                let addr4 = withUnsafePointer(to: &storage) {
                    $0.withMemoryRebound(to: sockaddr_in.self, capacity: 1) {
                        $0.pointee
                    }
                }

                if let ip = String(cString: inet_ntoa(addr4.sin_addr), encoding: .ascii) {
                    result = ip
                    break
                }
            }
        }

        return result
    }
}

#endif
