/*
	Copyright (C) 2016 Apple Inc. All Rights Reserved.
	See LICENSE.txt for this sample’s licensing information
	
	Abstract:
	该文件包含PacketTunnelProvider类。 PacketTunnelProvider类是NEPacketTunnelProvider的子类，并且是网络扩展框架和SimpleTunnel隧道协议之间的集成点。
*/

import NetworkExtension
import SimpleTunnelServices

/// A packet tunnel provider object.
class PacketTunnelProvider: NEPacketTunnelProvider, TunnelDelegate, ClientTunnelConnectionDelegate {

	// MARK: Properties

	///对隧道对象的引用。
	var tunnel: ClientTunnel?

	/// 数据包通过隧道的单一逻辑流。
	var tunnelConnection: ClientTunnelConnection?

	/// 隧道完全建立时要调用的完成处理程序。
	var pendingStartCompletion: ((Error?) -> Void)?

	/// 隧道完全断开连接时要调用的完成处理程序。
	var pendingStopCompletion: (() -> Void)?

	// MARK: NEPacketTunnelProvider

	/// 开始建立隧道的过程。建立
	override func startTunnel(options: [String : NSObject]?, completionHandler: @escaping (Error?) -> Void) {
		let newTunnel = ClientTunnel()
		newTunnel.delegate = self

		if let error = newTunnel.startTunnel(self) {
			completionHandler(error as NSError)
		}
		else {
			// 保存完成处理程序，以确保何时完全建立隧道。
			pendingStartCompletion = completionHandler
			tunnel = newTunnel
		}
	}

	/// 开始停止隧道的过程。
	override func stopTunnel(with reason: NEProviderStopReason, completionHandler: @escaping () -> Void) {
		// 清除所有挂起的启动完成处理程序。
		pendingStartCompletion = nil

		// 保存完成处理程序，以在隧道完全断开连接时使用。
		pendingStopCompletion = completionHandler
		tunnel?.closeTunnel()
	}

	/// 处理来自应用程序的IPC消息。
	override func handleAppMessage(_ messageData: Data, completionHandler: ((Data?) -> Void)?) {
		guard let messageString = NSString(data: messageData, encoding: String.Encoding.utf8.rawValue) else {
			completionHandler?(nil)
			return
		}

		simpleTunnelLog("Got a message from the app: \(messageString)")

		let responseData = "Hello app".data(using: String.Encoding.utf8)
		completionHandler?(responseData)
	}

	// MARK: TunnelDelegate

	/// 处理建立隧道连接的事件。
	func tunnelDidOpen(_ targetTunnel: Tunnel) {
		//打开通过隧道的数据包的逻辑流。
		let newConnection = ClientTunnelConnection(tunnel: tunnel!, clientPacketFlow: packetFlow, connectionDelegate: self)
		newConnection.open()
		tunnelConnection = newConnection
	}

	/// 处理隧道连接关闭的事件。
	func tunnelDidClose(_ targetTunnel: Tunnel) {
		if pendingStartCompletion != nil {
			//启动时关闭，使用适当的错误调用启动完成处理程序。
			pendingStartCompletion?(tunnel?.lastError)
			pendingStartCompletion = nil
		}
		else if pendingStopCompletion != nil {
			//由于调用stopTunnelWithReason而关闭，请调用停止完成处理程序。
            pendingStopCompletion?()
			pendingStopCompletion = nil
		}
		else {
			// 由于隧道连接错误而关闭，请取消隧道。
			cancelTunnelWithError(tunnel?.lastError)
		}
		tunnel = nil
	}

	/// 处理发送配置的服务器。
	func tunnelDidSendConfiguration(_ targetTunnel: Tunnel, configuration: [String : AnyObject]) {
	}

	// MARK: ClientTunnelConnectionDelegate

	/// 处理通过隧道建立的数据包逻辑流的事件。
	func tunnelConnectionDidOpen(_ connection: ClientTunnelConnection, configuration: [NSObject: AnyObject]) {

		// 创建虚拟接口设置。
		guard let settings = createTunnelSettingsFromConfiguration(configuration) else {
			pendingStartCompletion?(SimpleTunnelError.internalError as NSError)
			pendingStartCompletion = nil
			return
		}

		// 设置虚拟接口设置。
		setTunnelNetworkSettings(settings) { error in
			var startError: NSError?
			if let error = error {
				simpleTunnelLog("Failed to set the tunnel network settings: \(error)")
				startError = SimpleTunnelError.badConfiguration as NSError
			}
			else {
				//现在，我们可以开始向虚拟接口读写数据包了。
				self.tunnelConnection?.startHandlingPackets()
			}

			// 现在，隧道已完全建立，请调用启动完成处理程序。
			self.pendingStartCompletion?(startError)
			self.pendingStartCompletion = nil
		}
	}

	///处理数据包逻辑流被破坏的事件。
	func tunnelConnectionDidClose(_ connection: ClientTunnelConnection, error: NSError?) {
		tunnelConnection = nil
		tunnel?.closeTunnelWithError(error)
	}

	///创建要应用于虚拟接口的隧道网络设置。
	func createTunnelSettingsFromConfiguration(_ configuration: [NSObject: AnyObject]) -> NEPacketTunnelNetworkSettings? {
		guard let tunnelAddress = tunnel?.remoteHost,
			let address = getValueFromPlist(configuration, keyArray: [.IPv4, .Address]) as? String,
			let netmask = getValueFromPlist(configuration, keyArray: [.IPv4, .Netmask]) as? String
			else { return nil }

		let newSettings = NEPacketTunnelNetworkSettings(tunnelRemoteAddress: tunnelAddress)
		var fullTunnel = true

        newSettings.ipv4Settings = NEIPv4Settings(addresses: [address], subnetMasks: [netmask])

		if let routes = getValueFromPlist(configuration, keyArray: [.IPv4, .Routes]) as? [[String: AnyObject]] {
			var includedRoutes = [NEIPv4Route]()
			for route in routes {
				if let netAddress = route[SettingsKey.Address.rawValue] as? String,
					let netMask = route[SettingsKey.Netmask.rawValue] as? String
				{
					includedRoutes.append(NEIPv4Route(destinationAddress: netAddress, subnetMask: netMask))
				}
			}
            newSettings.ipv4Settings?.includedRoutes = includedRoutes
			fullTunnel = false
		}
		else {
			//未指定路由，请使用默认路由。
            newSettings.ipv4Settings?.includedRoutes = [NEIPv4Route.default()]
		}

		if let DNSDictionary = configuration[SettingsKey.DNS.rawValue as NSString] as? [String: AnyObject],
			let DNSServers = DNSDictionary[SettingsKey.Servers.rawValue] as? [String]
		{
			newSettings.dnsSettings = NEDNSSettings(servers: DNSServers)
			if let DNSSearchDomains = DNSDictionary[SettingsKey.SearchDomains.rawValue] as? [String] {
				newSettings.dnsSettings?.searchDomains = DNSSearchDomains
				if !fullTunnel {
					newSettings.dnsSettings?.matchDomains = DNSSearchDomains
				}
			}
		}

		newSettings.tunnelOverheadBytes = 150

		return newSettings
	}
}
