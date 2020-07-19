//
//  NetServiceBrowser+Timeout.swift
//  Assistive Technology
//
//  Created by Ben Mechen on 08/02/2020.
//  Copyright © 2020 Team 30. All rights reserved.
//

import Foundation
import Network


extension NetServiceBrowser {
    /// Starts a search for services of a particular type within a specific domain. The search must discover a service within the given timeout
    ///
    /// Custom wrapper for the NetServiceBrowser method `searchForServices(ofType type: String, inDomain domain: String)` with an added ability to set the maximum amount of time to search for the service.
    ///
    /// This method returns immediately, sending a `netServiceBrowserWillSearch(_:)` message to the delegate if the network was ready to initiate the search.The delegate receives subsequent `netServiceBrowser(_:didFind:moreComing:)` messages for each service discovered.
    /// The serviceType argument must contain both the service type and transport layer information. To ensure that the mDNS responder searches for services, rather than hosts, make sure to prefix both the service name and transport layer name with an underscore character (“_”). For example, to search for an HTTP service on TCP, you would use the type string “_http._tcp.“. Note that the period character at the end is required.
    /// The domainName argument can be an explicit domain name, the generic local domain @"local." (note trailing period, which indicates an absolute name), or the empty string (@""), which indicates the default registration domains. Usually, you pass in an empty string. Note that it is acceptable to use an empty string for the domainName argument when publishing or browsing a service, but do not rely on this for resolution.
    /// - Parameters:
    ///   - type: Type of the service to search for.
    ///   - domain: Domain name in which to perform the search.
    ///   - delay: Time in seconds before timing out
    public func searchForServices(ofType type: String, inDomain domain: String, withTimeout delay: Double) {
        self.searchForServices(ofType: type, inDomain: domain)
        
        DispatchQueue.main.asyncAfter(deadline: DispatchTime.now() + delay, execute: {
            if let delegate = self.delegate as? NetServiceBrowserDelegateExtension, delegate.discovered != true {
                self.stop(false)
            }
        })
    }
    
    /// Halts a currently running search or resolution.
    ///
    /// Custom wrapper for NetServiceBrowser method `stop()`, with added ability to inform delegate if the search was successful
    /// This method sends a `netServiceBrowserDidStopSearch(_:)` message to the delegate and causes the browser to discard any pending search results.
    /// - Parameter success: Did the browser discover a service?
    public func stop(_ success: Bool = false) {
        self.stop()
        if let delegate = self.delegate as? NetServiceBrowserDelegateExtension {
            delegate.netServiceBrowserDidStopSearch?(self, success: success)
        }
    }
}

/// The interface a net service browser uses to inform a delegate about the state of service discovery.
/// Extension of the `NetServiceBrowserDelegate`, adding custom `netServiceBrowserDidStopSearch(_ browser: NetServiceBrowser, success: Bool)` function and `discovered` variable
@objc protocol NetServiceBrowserDelegateExtension: NetServiceBrowserDelegate {
    @objc optional func netServiceBrowserDidStopSearch(_ browser: NetServiceBrowser, success: Bool)
    var discovered: Bool { get set }
}
