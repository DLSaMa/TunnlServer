/*
	Copyright (C) 2016 Apple Inc. All Rights Reserved.
	See LICENSE.txt for this sample’s licensing information
	
	Abstract:
	该文件包含Connection类。 Connection类是一个抽象基类，它处理SimpleTunnel隧道协议中的单个网络数据流。
*/


import Foundation

/// ///可以关闭流以获取​​更多数据的方向。
public enum TunnelConnectionCloseDirection: Int, CustomStringConvertible {
	case none = 1
	case read = 2
	case write = 3
	case all = 4

	public var description: String {
		switch self {
			case .none: return "none"
			case .read: return "reads"
			case .write: return "writes"
			case .all: return "reads and writes"
		}
	}
}

/// The results of opening a connection.
public enum TunnelConnectionOpenResult: Int {
	case success = 0
	case invalidParam
	case noSuchHost
	case refused
	case timeout
	case internalError
}

/// SimpleTunnel协议中网络数据的逻辑连接（或流）
open class Connection: NSObject {

	// MARK: Properties

	/// The connection identifier.
    public let identifier: Int

	/// 包含连接的隧道。
	open var tunnel: Tunnel?

	/// 可能时需要写入连接的数据列表。
	let savedData = SavedData()

	/// 闭合连接的方向。
	var currentCloseDirection = TunnelConnectionCloseDirection.none

	/// 指示此连接是否正在专门使用隧道。
	let isExclusiveTunnel: Bool

	/// 指示是否无法读取连接。
	open var isClosedForRead: Bool {
		return currentCloseDirection != .none && currentCloseDirection != .write
	}

	/// 指示是否无法写入连接。
	open var isClosedForWrite: Bool {
		return currentCloseDirection != .none && currentCloseDirection != .read
	}

	/// 指示连接是否完全关闭。
	open var isClosedCompletely: Bool {
		return currentCloseDirection == .all
	}

	// MARK: Initializers

	public init(connectionIdentifier: Int, parentTunnel: Tunnel) {
		tunnel = parentTunnel
		identifier = connectionIdentifier
		isExclusiveTunnel = false
		super.init()
		if let t = tunnel {
			// Add this connection to the tunnel's set of connections.
			t.addConnection(self)
		}

	}

	public init(connectionIdentifier: Int) {
		isExclusiveTunnel = true
		identifier = connectionIdentifier
	}

	// MARK: Interface

	/// Set a new tunnel for the connection.
	func setNewTunnel(_ newTunnel: Tunnel) {
		tunnel = newTunnel
		if let t = tunnel {
			t.addConnection(self)
		}
	}

	/// Close the connection.
	open func closeConnection(_ direction: TunnelConnectionCloseDirection) {
		if direction != .none && direction != currentCloseDirection {
			currentCloseDirection = .all
		}
		else {
			currentCloseDirection = direction
		}

		guard let currentTunnel = tunnel , currentCloseDirection == .all else { return }

		if isExclusiveTunnel {
			currentTunnel.closeTunnel()
		}
		else {
			currentTunnel.dropConnection(self)
			tunnel = nil
		}
	}

	/// 中止连接
	open func abort(_ error: Int = 0) {
		savedData.clear()
	}

	/// 在连接上发送数据。
	open func sendData(_ data: Data) {
	}

	/// 发送数据以及连接上的目标主机和端口。
	open func sendDataWithEndPoint(_ data: Data, host: String, port: Int) {
	}

	/// 向连接的远端发送指示，表明呼叫者将在一段时间内不再从该连接中读取任何数据。
	open func sendPackets(_ packets: [Data], protocols: [NSNumber]) {
	}

	/// 向连接的远端发送指示，表明呼叫者将在一段时间内不再从该连接中读取任何数据。
	open func suspend() {
	}

	/// 向连接的远端发送指示，表明呼叫者将开始从连接中读取更多数据。
	open func resume() {
	}

	///处理SimpleTunnel服务器发送的“打开完成”消息
	open func handleOpenCompleted(_ resultCode: TunnelConnectionOpenResult, properties: [NSObject: AnyObject]) {
	}
}
