/*
	Copyright (C) 2016 Apple Inc. All Rights Reserved.
	See LICENSE.txt for this sample’s licensing information
	
	Abstract:
	该文件包含ClientTunnel类。 ClientTunnel类实现SimpleTunnel隧道协议的客户端。
*/

import Foundation
import NetworkExtension

/// Make NEVPNStatus convertible to a string
extension NWTCPConnectionState: CustomStringConvertible {
	public var description: String {
		switch self {
			case .cancelled: return "Cancelled"
			case .connected: return "Connected"
			case .connecting: return "Connecting"
			case .disconnected: return "Disconnected"
			case .invalid: return "Invalid"
			case .waiting: return "Waiting"
		}
	}
}

///SimpleTunnel协议的客户端实现。
open class ClientTunnel: Tunnel {

	// MARK: Properties

	/// The tunnel connection.
	open var connection: NWTCPConnection?

	///隧道上发生的最后一个错误。
	open var lastError: NSError?

	/// 先前收到的不完整消息数据。
	var previousData: NSMutableData?

	/// 隧道服务器的地址。
	open var remoteHost: String?

	// MARK: Interface

	/// 启动与隧道服务器的TCP连接。
	open func startTunnel(_ provider: NETunnelProvider) -> SimpleTunnelError? {

        
        
		guard let serverAddress = provider.protocolConfiguration.serverAddress else {
			return .badConfiguration
		}
        
		let endpoint: NWEndpoint

        //判断 传进来的服务器地址是否合法
		if let colonRange = serverAddress.rangeOfCharacter(from: CharacterSet(charactersIn: ":"), options: [], range: nil) {
			// 该服务器在配置中指定为<主机>：<端口>。
            let hostname = serverAddress.substring(with: serverAddress.startIndex..<colonRange.lowerBound)
			let portString = serverAddress.substring(with: serverAddress.index(after: colonRange.lowerBound)..<serverAddress.endIndex)

			guard !hostname.isEmpty && !portString.isEmpty else {
				return .badConfiguration
			}

			endpoint = NWHostEndpoint(hostname:hostname, port:portString)
		}
		else {
			// 该服务器在配置中指定为Bonjour服务名称。
			endpoint = NWBonjourServiceEndpoint(name: serverAddress, type:Tunnel.serviceType, domain:Tunnel.serviceDomain)
		}

		// 启动与服务器的连接。
		connection = provider.createTCPConnection(to: endpoint, enableTLS:false, tlsParameters:nil, delegate:nil)

		// 连接状态更改时注册通知。
		connection!.addObserver(self, forKeyPath: "state", options: .initial, context: &connection)

		return nil
	}

	/// Close the tunnel.
	open func closeTunnelWithError(_ error: NSError?) {
		lastError = error
		closeTunnel()
	}

	///从隧道连接中读取SimpleTunnel数据包。
	func readNextPacket() {
		guard let targetConnection = connection else {
			closeTunnelWithError(SimpleTunnelError.badConnection as NSError)
			return
		}

		// 首先，读取数据包的总长度。
        /*
         调用targetConnection.readMinimumLength做一个TCP连接的监听, 监听服务器的数据. 调用这个方法可以设置一次性读取多少数据, 这里我们设置成MemoryLayout<UInt32>.size, 也就是4个字节. 之所以这么操作, 是因为这个项目自己写了个协议.
         */
		targetConnection.readMinimumLength(MemoryLayout<UInt32>.size, maximumLength: MemoryLayout<UInt32>.size) { data, error in
			if let readError = error {
				simpleTunnelLog("Got an error on the tunnel connection: \(readError)")
				self.closeTunnelWithError(readError as NSError?)
				return
			}

			let lengthData = data

			guard lengthData!.count == MemoryLayout<UInt32>.size else {
				simpleTunnelLog("Length data length (\(lengthData!.count)) != sizeof(UInt32) (\(MemoryLayout<UInt32>.size)")
				self.closeTunnelWithError(SimpleTunnelError.internalError as NSError)
				return
			}

			var totalLength: UInt32 = 0
			(lengthData as! NSData).getBytes(&totalLength, length: MemoryLayout<UInt32>.size)

			if totalLength > UInt32(Tunnel.maximumMessageSize) {
				simpleTunnelLog("Got a length that is too big: \(totalLength)")
				self.closeTunnelWithError(SimpleTunnelError.internalError as NSError)
				return
			}

			totalLength -= UInt32(MemoryLayout<UInt32>.size)

			// 其次，读取数据包有效载荷。
			targetConnection.readMinimumLength(Int(totalLength), maximumLength: Int(totalLength)) { data, error in
				if let payloadReadError = error {
					simpleTunnelLog("Got an error on the tunnel connection: \(payloadReadError)")
					self.closeTunnelWithError(payloadReadError as NSError?)
					return
				}

				let payloadData = data

				guard payloadData!.count == Int(totalLength) else {
					simpleTunnelLog("Payload data length (\(payloadData!.count)) != payload length (\(totalLength)")
					self.closeTunnelWithError(SimpleTunnelError.internalError as NSError)
					return
				}

				_ = self.handlePacket(payloadData!)

				self.readNextPacket()
			}
		}
	}

	/// 向隧道服务器发送消息。
	open func sendMessage(_ messageProperties: [String: AnyObject], completionHandler: @escaping (Error?) -> Void) {
		guard let messageData = serializeMessage(messageProperties) else {
			completionHandler(SimpleTunnelError.internalError as NSError)
			return
		}

		connection?.write(messageData, completionHandler: completionHandler)
	}

	// MARK: NSObject  观察者实现方式

	/// 处理更改为隧道连接状态。
	open override func observeValue(forKeyPath keyPath: String?, of object: Any?, change: [NSKeyValueChangeKey: Any]?, context: UnsafeMutableRawPointer?) {
		guard keyPath == "state" && context?.assumingMemoryBound(to: Optional<NWTCPConnection>.self).pointee == connection else {
			super.observeValue(forKeyPath: keyPath, of: object, change: change, context: context)
			return
		}

		simpleTunnelLog("Tunnel connection state changed to \(connection!.state)")
// 连接成功
		switch connection!.state {
			case .connected:
				if let remoteAddress = self.connection!.remoteAddress as? NWHostEndpoint {
					remoteHost = remoteAddress.hostname
				}
				// 开始从隧道连接中读取消息。
				readNextPacket()
				// 让代表知道隧道是开放的
				delegate?.tunnelDidOpen(self)
// 断开连接
			case .disconnected:
				closeTunnelWithError(connection!.error as NSError?)
// 取消连接
			case .cancelled:
				connection!.removeObserver(self, forKeyPath:"state", context:&connection)
				connection = nil
				delegate?.tunnelDidClose(self)

			default:
				break
		}
	}

	// MARK: Tunnel

	/// Close the tunnel.
	override open func closeTunnel() {
		super.closeTunnel()
		// Close the tunnel connection.
		if let TCPConnection = connection {
			TCPConnection.cancel()
		}

	}

	/// 将数据写入隧道连接。
	override func writeDataToTunnel(_ data: Data, startingAtOffset: Int) -> Int {
		connection?.write(data) { error in
			if error != nil {
				self.closeTunnelWithError(error as NSError?)
			}
		}
		return data.count
	}

///处理从隧道服务器收到的消息。
	override func handleMessage(_ commandType: TunnelCommand, properties: [String: AnyObject], connection: Connection?) -> Bool {
		var success = true

		switch commandType {
			case .openResult:
				// A logical connection was opened successfully.
				guard let targetConnection = connection,
					let resultCodeNumber = properties[TunnelMessageKey.ResultCode.rawValue] as? Int,
					let resultCode = TunnelConnectionOpenResult(rawValue: resultCodeNumber)
					else
				{
					success = false
					break
				}

				targetConnection.handleOpenCompleted(resultCode, properties:properties as [NSObject : AnyObject])

			case .fetchConfiguration:
				guard let configuration = properties[TunnelMessageKey.Configuration.rawValue] as? [String: AnyObject]
					else { break }

				delegate?.tunnelDidSendConfiguration(self, configuration: configuration)
			
			default:
				simpleTunnelLog("Tunnel received an invalid command")
				success = false
		}
		return success
	}

	/// 在隧道连接上发送FetchConfiguration消息。
	open func sendFetchConfiguation() {
		let properties = createMessagePropertiesForConnection(0, commandType: .fetchConfiguration)
		if !sendMessage(properties) {
			simpleTunnelLog("Failed to send a fetch configuration message")
		}
	}
}
