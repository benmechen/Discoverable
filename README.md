# Discoverable

[![Version](https://img.shields.io/cocoapods/v/Discoverable.svg?style=flat)](https://cocoapods.org/pods/Discoverable)
[![License](https://img.shields.io/cocoapods/l/Discoverable.svg?style=flat)](https://cocoapods.org/pods/Discoverable)
[![Platform](https://img.shields.io/cocoapods/p/Discoverable.svg?style=flat)](https://cocoapods.org/pods/Discoverable)

*Discoverable* is a Swift package that allows an iOS device to automatically discover and connect to any compatible devices on the network, **without the need for IP addresses**.

Under the surface, Discoverable uses Foundation's Bonjour framework to find the service advertised on the netwok, and the Network framework to communicate over UDP+ using your custom defined networking protocol messages.

Connections are a 3 stage process:
1. Using Bonjour/Zeroconf, find the service advertised on the network.
2. Once a service is discovered, resolve the IP address of the machine advertising and open a UDP+ connection.
3. Once a handshake has been completed, the connection will stay open until closed by either party, or the connection strength (see below) drops below 5%. 

### UDP+

The framework uses UDP packets to send messages between parties, however, the DiscoverableProtocol builds a number of TCP features on top of this:
* To start a connection, a handshake is required between the two parties to ensure both are able to accept a new connection
* All messages from the client require the server to reply with an acknowledgement message within a given timeframe
* Connection strength is a percentage value, calculated from the number of packets acknowledged by the server. It takes the average over the last `n` most recent responses to get an up-to-date strength value
* If either party ends the connection or closes for any reason, they will send a last dying message to close the connection. This means no client will be left with a dangling connection.

### DiscoveryProtocol

This Swift protocol contains the basic commands needed to operate the network:

```
enum DiscoverableProtocol: String {
    /// Disconnect & shut down server
    case disconnect = "dscv_disconnect"
    /// Send greeting to server, with device name appended in the format: ":device_name"
    case discover = "dscv_discover"
    /// Handshake response received from server
    case handshake = "dscv_shake"
    /// Acknowledgment message
    case acknowledge = "dscv_ack"
}
```

Any other messages can be added by extending the DiscoverableProtocol, or just passing any string value into `send()`.

## Example

To run the example project, clone the repo, and run `pod install` from the Example directory first.

A detailed walkthough is posted [here](https://dev.to/benmechen/automatically-discover-and-connect-to-devices-on-a-network)

## Requirements

The framework uses Apple's Network framework, which is available on iOS 12+.

## Installation

Discoverable is available through [CocoaPods](https://cocoapods.org). To install
it, simply add the following line to your Podfile:

```ruby
pod 'Discoverable'
```

## API

The ConnectionService class can be used in two ways:
* Singleton `shared` instance
* Create a new `ConnectionService` instance

### Discovery

#### `discover(type: String, on: UInt16?)`

Begin looking for a Bonjour service on the local network of the given type. This function times out after 5 seconds if no services are discovered.
This function will automatically look for a service, resolve the IP of the discovered device, and then call the `connect` function below with the discovered IP and the given port, or 1024 if no port is given.

### Connection

#### `connect(to host: String, on port: UInt16)`

If you already know the IP address of the device you wish to connect to, you can skip the auto-discovery and connect directly using this function - it is the same function used internally by the `discover` function.

On connection start, a function will be called to open a listener on incomming connections and the state will be set to `connecting`. This function will listen out for the handshake response from the server - once one is received, the connection state is updated to `connected`.

#### `send()`

Send a string value to the other device, if connected. This is where the connection strength is calculated - for each message sent, an acknowledgement should be sent back within 2 seconds. If the stength is below 5%, the connection is considered closed, and the state is set to `disconected`. 

#### `close(_ killServer = true, state = .disconnected)`

Close the connection. By default, this will send a disconnect message to the server to shut it down too. If needed, the final connection state can be set too, however it is unlikely that this needs to be changed.

### Delegate

If you wish to subscribe to connection state and strength updates, set the ConnectionService's delegate property to an object extending `ConnectionServiceDelegate`. This delegate object must implement the following functions to receive updates:
* `connectionState(state: ConnectionService.State)` - The current state of the connection
* `connectionStrength(strength: Float)` - The current strength of the connection, as a percentage

## Author

benmechen, psybm7@nottingham.ac.uk

## License

Discoverable is available under the MIT license. See the LICENSE file for more info.
