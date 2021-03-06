/*
	Copyright (C) 2016 Apple Inc. All Rights Reserved.
	See LICENSE.txt for this sample’s licensing information
	
	Abstract:
该文件包含FilterUtilities类。 FilterUtilities对象包含SimpleTunnel UI和SimpleTunnel内容过滤器提供程序都使用的函数和数据。
*/

import Foundation
import NetworkExtension

/// 内容过滤器操作。
public enum FilterRuleAction : Int, CustomStringConvertible {
	case block = 1
	case allow = 2
	case needMoreRulesAndBlock = 3
	case needMoreRulesAndAllow = 4
	case needMoreRulesFromDataAndBlock = 5
	case needMoreRulesFromDataAndAllow = 6
	case examineData = 7
	case redirectToSafeURL = 8
	case remediate = 9

	public var description: String {
		switch self {
		case .block: return "Block"
		case .examineData: return "Examine Data"
		case .needMoreRulesAndAllow: return "Ask for more rules, then allow"
		case .needMoreRulesAndBlock: return "Ask for more rules, then block"
		case .needMoreRulesFromDataAndAllow: return "Ask for more rules, examine data, then allow"
		case .needMoreRulesFromDataAndBlock: return "Ask for more rules, examine data, then block"
		case .redirectToSafeURL: return "Redirect"
		case .remediate: return "Remediate"
		case .allow: return "Allow"
		}
	}
}

/// 包含用于内容筛选的实用程序属性和功能的类。
open class FilterUtilities {

	// MARK: Properties

	/// 默认情况下，对SimpleTunnel用户的引用。
    public static let defaults = UserDefaults(suiteName: "group.com.example.apple-samplecode.SimpleTunnel")

	// MARK: Initializers

	/// 从SimpleTunnel用户默认值获取流的规则参数。
	open class func getRule(_ flow: NEFilterFlow) -> (FilterRuleAction, String, [String: AnyObject]) {
		let hostname = FilterUtilities.getFlowHostname(flow)

		guard !hostname.isEmpty else { return (.allow, hostname, [:]) }

		guard let hostNameRule = (defaults?.object(forKey: "rules") as AnyObject).object(forKey: hostname) as? [String: AnyObject] else {
			simpleTunnelLog("\(hostname) is set for NO RULES")
			return (.allow, hostname, [:])
		}

		guard let ruleTypeInt = hostNameRule["kRule"] as? Int,
			let ruleType = FilterRuleAction(rawValue: ruleTypeInt)
			else { return (.allow, hostname, [:]) }

		return (ruleType, hostname, hostNameRule)
	}

	/// 从浏览器流获取主机名。
	open class func getFlowHostname(_ flow: NEFilterFlow) -> String {
		guard let browserFlow : NEFilterBrowserFlow = flow as? NEFilterBrowserFlow,
			let url = browserFlow.url,
			let hostname = url.host
			, flow is NEFilterBrowserFlow
			else { return "" }
		return hostname
	}

	/// 从规则服务器下载一组新规则。
	open class func fetchRulesFromServer(_ serverAddress: String?) {
		simpleTunnelLog("fetch rules called")

		guard serverAddress != nil else { return }
		simpleTunnelLog("Fetching rules from \(serverAddress)")

		guard let infoURL = URL(string: "http://\(serverAddress!)/rules/") else { return }
		simpleTunnelLog("Rules url is \(infoURL)")

		let content: String
		do {
			content = try String(contentsOf: infoURL, encoding: String.Encoding.utf8)
		}
		catch {
			simpleTunnelLog("Failed to fetch the rules from \(infoURL)")
			return
		}

		let contentArray = content.components(separatedBy: "<br/>")
		simpleTunnelLog("Content array is \(contentArray)")
		var urlRules = [String: [String: AnyObject]]()

		for rule in contentArray {
			if rule.isEmpty {
				continue
			}
			let ruleArray = rule.components(separatedBy: " ")

			guard !ruleArray.isEmpty else { continue }

			var redirectKey = "SafeYes"
			var remediateKey = "Remediate1"
			var remediateButtonKey = "RemediateButton1"
			var actionString = "9"

			let urlString = ruleArray[0]
			let ruleArrayCount = ruleArray.count

			if ruleArrayCount > 1 {
				actionString = ruleArray[1]
			}
			if ruleArrayCount > 2 {
				redirectKey = ruleArray[2]
			}
			if ruleArrayCount > 3 {
				remediateKey = ruleArray[3]
			}
			if ruleArrayCount > 4 {
				remediateButtonKey = ruleArray[4]
			}


			urlRules[urlString] = [
				"kRule" : actionString as AnyObject,
				"kRedirectKey" : redirectKey as AnyObject,
				"kRemediateKey" : remediateKey as AnyObject,
				"kRemediateButtonKey" : remediateButtonKey as AnyObject,
			]
		}
		defaults?.setValue(urlRules, forKey:"rules")
	}
}
