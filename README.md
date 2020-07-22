> The Apple's Network Extension Demo *(revision1.3 2016-10-04)* is not fully-swift3 yet. This demo update its rest swift3 uncompatible code to swift3 fully-compatible, as well as some bug fixes. Feel free to check it out.

# SimpleTunnel：使用NetworkExtension框架的自定义网络

SimpleTunnel项目包含网络扩展框架提供的四个扩展点的工作示例：

1. 分组隧道提供商
   数据包隧道提供程序扩展点用于表示定制网络隧道协议的客户端，该协议以IP数据包的形式封装网络数据。 SimpleTunnel项目中的PacketTunnel目标产生一个示例Packet Tunnel Provider扩展。

   应用代理提供商
   App Proxy Provider扩展点用于实现自定义网络代理协议的客户端，该协议以应用程序网络数据流的形式封装网络数据。支持基于TCP或基于流的数据流以及基于UDP或基于数据报的数据流。 SimpleTunnel项目中的AppProxy目标产生一个示例App Proxy Provider扩展。

   筛选器数据提供者和筛选器控制提供者
   这两个过滤器提供程序扩展点用于实现动态的设备上网络内容过滤器。 Filter Data Provider扩展负责检查网络数据并做出通过/阻止决定。 Filter Data Provider扩展沙箱可防止扩展通过网络进行通信或写入磁盘，以防止网络数据泄漏。 Filter Control Provider扩展可以使用网络进行通信并写入磁盘。它负责代表“过滤器数据提供者”扩展名更新过滤规则。

   SimpleTunnel项目中的FilterDataProvider目标产生一个示例Filter Data Provider扩展。 SimpleTunnel项目中的FilterControlProvider目标产生一个示例Filter Control Provider扩展。e

   所有示例扩展都打包到SimpleTunnel应用程序中。 SimpleTunnel应用程序包含演示如何配置和控制各种类型的网络扩展提供程序的代码。 SimpleTunnel项目中的SimpleTunnel目标将生成SimpleTunnel应用程序和所有示例扩展。

   SimpleTunnel项目包含自定义网络隧道协议的客户端和服务器端。数据包隧道提供程序和应用程序代理提供程序扩展实现了客户端。 tunnel_server目标产生一个实现服务器端的OS X命令行二进制文件。使用plist配置服务器。样本plist包含在tunnel_erver源代码中。要运行服务器，请使用以下命令：

   sudo tunnel_server

# 要求

### 运行

The NEProvider family of APIs require the following entitlement:

<key>com.apple.developer.networking.networkextension</key>
<array>
	<string>packet-tunnel-provider</string>
	<string>app-proxy-provider</string>
	<string>content-filter-provider</string>
</array>
</plist>

如果未使用此权利对代码进行签名，则SimpleTunnel.app和提供程序扩展将不会运行。

您可以通过发送电子邮件至networkextension@apple.com来请求此权利。

SimpleTunnel iOS产品需要iOS 9.0或更高版本。 SimpleTunnel OS X产品需要OS X 11.0或更高版本。

### Build

SimpleTunnel需要Xcode 8.0或更高版本。 SimpleTunnel iOS目标需要iOS 9.0 SDK或更高版本。 SimpleTunnel OS X目标需要OS X 11.0 SDK或更高版本。

Copyright (C) 2016 Apple Inc. All rights reserved.
