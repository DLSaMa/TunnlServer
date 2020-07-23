/*
 Copyright (C) 2016 Apple Inc. All Rights Reserved.
 See LICENSE.txt for this sample’s licensing information
 
 Abstract:
 This file contains the ClientTunnelConnection class. The ClientTunnelConnection class handles the encapsulation and decapsulation of IP packets in the client side of the SimpleTunnel tunneling protocol.
 
 该文件包含ClientTunnelConnection类。 ClientTunnelConnection类在SimpleTunnel隧道协议的客户端中处理IP数据包的封装和解封装。
 */

import Foundation
import SimpleTunnelServices
import NetworkExtension

// MARK: Protocols

/// The delegate protocol for ClientTunnelConnection.
protocol ClientTunnelConnectionDelegate {
    /// Handle the connection being opened.
    func tunnelConnectionDidOpen(_ connection: ClientTunnelConnection, configuration: [NSObject: AnyObject])
    /// Handle the connection being closed.
    func tunnelConnectionDidClose(_ connection: ClientTunnelConnection, error: NSError?)
}

/// 一个用于使用SimpleTunnel协议隧道IP数据包的对象。
class ClientTunnelConnection: Connection {
    
    // MARK: Properties
    
    /// The connection delegate.
    let delegate: ClientTunnelConnectionDelegate
    
    /// IP数据包的流。
    let packetFlow: NEPacketTunnelFlow
    
    // MARK: Initializers
    
    init(tunnel: ClientTunnel, clientPacketFlow: NEPacketTunnelFlow, connectionDelegate: ClientTunnelConnectionDelegate) {
        delegate = connectionDelegate
        packetFlow = clientPacketFlow
        let newConnectionIdentifier = arc4random()
        super.init(connectionIdentifier: Int(newConnectionIdentifier), parentTunnel: tunnel)
    }
    
    // MARK: Interface
    
    /// 通过向隧道服务器发送“连接打开”消息来打开连接。
    func open() {
        guard let clientTunnel = tunnel as? ClientTunnel else { return }
        
        let properties = createMessagePropertiesForConnection(identifier, commandType: .open, extraProperties:[
            TunnelMessageKey.TunnelType.rawValue: TunnelLayer.ip.rawValue as AnyObject
        ])
        
        clientTunnel.sendMessage(properties) { error in
            if let error = error {
                self.delegate.tunnelConnectionDidClose(self, error: error as NSError)
            }
        }
    }
    
    /// 处理来自数据包流的数据包。
    func handlePackets(_ packets: [Data], protocols: [NSNumber]) {
        guard let clientTunnel = tunnel as? ClientTunnel else { return }
        
        let properties = createMessagePropertiesForConnection(identifier, commandType: .packets, extraProperties:[
            TunnelMessageKey.Packets.rawValue: packets as AnyObject,
            TunnelMessageKey.Protocols.rawValue: protocols as AnyObject
        ])
        
        clientTunnel.sendMessage(properties) { error in
            if let sendError = error {
                self.delegate.tunnelConnectionDidClose(self, error: sendError as NSError?)
                return
            }
            
            // 阅读更多数据包。
            self.packetFlow.readPackets { inPackets, inProtocols in
                self.handlePackets(inPackets, protocols: inProtocols)
            }
        }
    }
    
    /// 进行初始的readPacketsWithCompletionHandler调用。
    func startHandlingPackets() {
        packetFlow.readPackets { inPackets, inProtocols in
            self.handlePackets(inPackets, protocols: inProtocols)
        }
    }
    
    // MARK: Connection
    
    /// 处理建立连接的事件。
    override func handleOpenCompleted(_ resultCode: TunnelConnectionOpenResult, properties: [NSObject: AnyObject]) {
        guard resultCode == .success else {
            delegate.tunnelConnectionDidClose(self, error: SimpleTunnelError.badConnection as NSError)
            return
        }
        
        // 将隧道网络设置传递给代理。
        if let configuration = properties[TunnelMessageKey.Configuration.rawValue as NSString] as? [NSObject: AnyObject] {
            delegate.tunnelConnectionDidOpen(self, configuration: configuration)
        }
        else {
            delegate.tunnelConnectionDidOpen(self, configuration: [:])
        }
    }
    
    /// 将数据包发送到虚拟接口以注入到IP堆栈中。
    override func sendPackets(_ packets: [Data], protocols: [NSNumber]) {
        packetFlow.writePackets(packets, withProtocols: protocols)
    }
}
