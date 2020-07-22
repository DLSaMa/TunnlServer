/*
	Copyright (C) 2016 Apple Inc. All Rights Reserved.
	See LICENSE.txt for this sample’s licensing information
	
	Abstract:
	This file contains some utility classes and functions used by various parts of the SimpleTunnel project.
*/

import Foundation
import Darwin

/// SimpleTunnel errors
public enum SimpleTunnelError: Error {
    case badConfiguration
    case badConnection
	case internalError
}

/// A queue of blobs of data
class SavedData {

	// MARK: Properties

	/// 列表中的每个项目都包含一个数据Blob，以及要写入的数据的数据Blob中的偏移量（以字节为单位）
	var chain = [(data: Data, offset: Int)]()

	/// A convenience property to determine if the list is empty.
	var isEmpty: Bool {
		return chain.isEmpty
	}

	// MARK: Interface

	/// 将数据blob和偏移量添加到列表的末尾。
	func append(_ data: Data, offset: Int) {
        chain.append((data: data, offset: offset))
	}

	/// 将列表中尽可能多的数据写入流
	func writeToStream(_ stream: OutputStream) -> Bool {
		var result = true
		var stopIndex: Int?

		for (chainIndex, record) in chain.enumerated() {
			let written = writeData(record.data, toStream: stream, startingAtOffset:record.offset)
			if written < 0 {
				result = false
				break
			}
			if written < (record.data.count - record.offset) {
				// 无法将所有剩余数据写入该Blob中，请更新偏移量。
				chain[chainIndex] = (record.data, record.offset + written)
				stopIndex = chainIndex
				break
			}
		}

		if let removeEnd = stopIndex {
			// 我们并未写入所有数据，请删除已写入的数据。
			if removeEnd > 0 {
				chain.removeSubrange(0..<removeEnd)
			}
		} else {
			// 所有数据均已写入。
			chain.removeAll(keepingCapacity: false)
		}

		return result
	}

	/// 从列表中删除所有数据。
	func clear() {
		chain.removeAll(keepingCapacity: false)
	}
}

/// 包含sockaddr_in6结构的对象。
class SocketAddress6 {

	// MARK: Properties

	/// The sockaddr_in6 structure.
	var sin6: sockaddr_in6

	///  IPv6地址作为字符串。
	var stringValue: String? {
    return withUnsafePointer(to: &sin6) { $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { saToString($0) } }
	}

	// MARK: Initializers

	init() {
		sin6 = sockaddr_in6()
		sin6.sin6_len = __uint8_t(MemoryLayout<sockaddr_in6>.size)
		sin6.sin6_family = sa_family_t(AF_INET6)
		sin6.sin6_port = in_port_t(0)
		sin6.sin6_addr = in6addr_any
		sin6.sin6_scope_id = __uint32_t(0)
		sin6.sin6_flowinfo = __uint32_t(0)
	}

	convenience init(otherAddress: SocketAddress6) {
		self.init()
		sin6 = otherAddress.sin6
	}

	/// Set the IPv6 address from a string.
	func setFromString(_ str: String) -> Bool {
		return str.withCString({ cs in inet_pton(AF_INET6, cs, &sin6.sin6_addr) }) == 1
	}

	/// Set the port.
	func setPort(_ port: Int) {
		sin6.sin6_port = in_port_t(UInt16(port).bigEndian)
	}
}

/// An object containing a sockaddr_in structure.
class SocketAddress {

	// MARK: Properties

	/// The sockaddr_in structure.
	var sin: sockaddr_in

	/// The IPv4 address in string form.
	var stringValue: String? {
    return withUnsafePointer(to: &sin) { $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { saToString($0) } }
	}

	// MARK: Initializers

	init() {
		sin = sockaddr_in(sin_len:__uint8_t(MemoryLayout<sockaddr_in>.size), sin_family:sa_family_t(AF_INET), sin_port:in_port_t(0), sin_addr:in_addr(s_addr: 0), sin_zero:(Int8(0), Int8(0), Int8(0), Int8(0), Int8(0), Int8(0), Int8(0), Int8(0)))
	}

	convenience init(otherAddress: SocketAddress) {
		self.init()
		sin = otherAddress.sin
	}

	/// Set the IPv4 address from a string.
	func setFromString(_ str: String) -> Bool {
		return str.withCString({ cs in inet_pton(AF_INET, cs, &sin.sin_addr) }) == 1
	}

	/// Set the port.
	func setPort(_ port: Int) {
		sin.sin_port = in_port_t(UInt16(port).bigEndian)
	}

	///将地址增加给定的数量。
	func increment(_ amount: UInt32) {
		let networkAddress = sin.sin_addr.s_addr.byteSwapped + amount
		sin.sin_addr.s_addr = networkAddress.byteSwapped
	}

	///获取此地址与另一个地址之间的差。
	func difference(_ otherAddress: SocketAddress) -> Int64 {
		return Int64(sin.sin_addr.s_addr.byteSwapped - otherAddress.sin.sin_addr.s_addr.byteSwapped)
	}
}

// MARK: Utility Functions

/// Convert a sockaddr structure to a string.
func saToString(_ sa: UnsafePointer<sockaddr>) -> String? {
	var hostBuffer = [CChar](repeating: 0, count: Int(NI_MAXHOST))
	var portBuffer = [CChar](repeating: 0, count: Int(NI_MAXSERV))

	guard getnameinfo(sa, socklen_t(sa.pointee.sa_len), &hostBuffer, socklen_t(hostBuffer.count), &portBuffer, socklen_t(portBuffer.count), NI_NUMERICHOST | NI_NUMERICSERV) == 0
		else { return nil }

	return String(cString: hostBuffer)
}

///从特定的偏移量开始将一滴数据写入流中。
func writeData(_ data: Data, toStream stream: OutputStream, startingAtOffset offset: Int) -> Int {
	var written = 0
	var currentOffset = offset
	while stream.hasSpaceAvailable && currentOffset < data.count {

		let writeResult = stream.write((data as NSData).bytes.bindMemory(to: UInt8.self, capacity: data.count) + currentOffset, maxLength: data.count - currentOffset)
		guard writeResult >= 0 else { return writeResult }

		written += writeResult
		currentOffset += writeResult
	}
	
	return written
}

///创建一个SimpleTunnel协议消息字典。
public func createMessagePropertiesForConnection(_ connectionIdentifier: Int, commandType: TunnelCommand, extraProperties: [String: AnyObject] = [:]) -> [String: AnyObject] {
	// Start out with the "extra properties" that the caller specified.
	var properties = extraProperties

	//从调用者指定的“额外属性”开始。
	properties[TunnelMessageKey.Identifier.rawValue] = connectionIdentifier as AnyObject?
	properties[TunnelMessageKey.Command.rawValue] = commandType.rawValue as AnyObject?
	
	return properties
}

/// Keys in the tunnel server configuration plist.
public enum SettingsKey: String {
	case IPv4 = "IPv4"
	case DNS = "DNS"
	case Proxies = "Proxies"
	case Pool = "Pool"
	case StartAddress = "StartAddress"
	case EndAddress = "EndAddress"
	case Servers = "Servers"
	case SearchDomains = "SearchDomains"
	case Address = "Address"
	case Netmask = "Netmask"
	case Routes = "Routes"
}

///从给定键列表的plist中获取值。

public func getValueFromPlist(_ plist: [NSObject: AnyObject], keyArray: [SettingsKey]) -> AnyObject? {
	var subPlist = plist
	for (index, key) in keyArray.enumerated() {
		if index == keyArray.count - 1 {
			return subPlist[key.rawValue as NSString]
		}
		else if let subSubPlist = subPlist[key.rawValue as NSString] as? [NSObject: AnyObject] {
			subPlist = subSubPlist
		}
		else {
			break
		}
	}

	return nil
}

/// 通过将给定范围的起点增加给定的数量来创建新的范围。
func rangeByMovingStartOfRange(_ range: Range<Int>, byCount: Int) -> CountableRange<Int> {
	return (range.lowerBound + byCount)..<range.upperBound
}

public func simpleTunnelLog(_ message: String) {
	NSLog(message)
}
