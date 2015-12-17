//
//  Airtable.swift
//  Airtable
//
//  Created by Rex Sheng on 11/28/15.
//  Copyright (c) 2015 rexsheng.com. All rights reserved.
//

import Greycats
import Alamofire

public protocol AirtableData: Equatable {
	static var table: String { get }
	var json: JSON! { get set }
	var id: String? { get }
	var createdTime: NSDate { get }
	init()
	static func List(view: String?, limit: Int?, offset: String?) -> Airtable
	static func Get(id: String) -> Airtable
	static func Create(fields: [String: AnyObject]) -> Airtable
}
public func ==<T: AirtableData>(lhs: T, rhs: T) -> Bool {
	return lhs.id == rhs.id
}

extension AirtableData {
	static var keyPath: String { return "records" }
	func setupFields() {
		let fields = json["fields"]
		let mirror = Mirror(reflecting: self)
		for (_, value) in mirror.children {
			if let value = value as? AnyField {
				value.connect(fields)
			}
		}
	}

	init(json: JSON, cache: Bool = true) {
		self.init()
		self.json = json
		if let this = self as? Cache where cache {
			this.save()
		}
		setupFields()
	}

	public var id: String? {
		return json["id"].string
	}

	public var createdTime: NSDate {
		let formatter = NSDateFormatter()
		formatter.dateFormat = "yyyy-MM-dd'T'HH:mm:ss.SSSZZZZ"
		return formatter.dateFromString(json["createdTime"].string!)!
	}

	public static func List(view: String? = nil, limit: Int? = nil, offset: String? = nil) -> Airtable {
		var param: [String: AnyObject] = [:]
		if let limit = limit {
			param["limit"] = limit
		}
		if let offset = offset {
			param["offset"] = offset
		}
		if let view = view {
			param["view"] = view
		}
		return Airtable.Get(table, param)
	}

	public static func List(view: String? = nil, limit: Int? = nil, offset: String? = nil, closure: ([Self], ErrorType?) -> ()) {
		let key = "\(self).list"
		if let this = self as? Cache.Type, let list = loadJSON(key, expireAfter: this.expireAfter)?.array where list.count > 0 {
			let objects = list.map { this.load($0.string!) as! Self }
			closure(objects, nil)
			return
		}

		var param: [String: AnyObject] = [:]
		param["limit"] = limit
		param["offset"] = offset
		param["view"] = view
		return Airtable.Get(table, param).response { (objects: [Self], error) in
			if let _ = self as? Cache.Type where error == nil {
				let keys = objects.map { $0.id! }
				saveJSON(JSON(keys), toPath: key)
			}
			closure(objects, error)
		}
	}

	public static func Get(id: String) -> Airtable {
		return Airtable.Get("\(table)/\(id)", nil)
	}

	public static func Get(id: String, closure: (Self?, ErrorType?) -> ()) {
		if let this = self as? Cache.Type, let object = this.load(id) as? Self {
			closure(object, nil)
			return
		}
		return Get(id).response(closure)
	}

	public static func Create(fields: [String: AnyObject]) -> Airtable {
		return Airtable.Post(table, ["fields": fields])
	}
}

public protocol Cache {
	static var expireAfter: NSTimeInterval { get }
	static func load(key: String) -> Any?
	func save()
}

let cacheHome = NSSearchPathForDirectoriesInDomains(.CachesDirectory, .UserDomainMask, true).first

func loadJSON(key: String, expireAfter: NSTimeInterval) -> JSON? {
	if let filePath = cacheHome?.stringByAppendingString("/\(key)") {
		if let attr = try? NSFileManager.defaultManager().attributesOfItemAtPath(filePath),
			lastModified = attr[NSFileModificationDate] as? NSDate {
				if lastModified.timeIntervalSinceNow < -expireAfter {
					return nil
				}
		}
		if let data = NSData(contentsOfFile: filePath),
			let object = try? NSJSONSerialization.JSONObjectWithData(data, options: []) {
				return JSON(object)
		}
	}
	return nil
}

func saveJSON(json: JSON, toPath: String) {
	if let filePath = cacheHome?.stringByAppendingString("/\(toPath)"),
		data = try? NSJSONSerialization.dataWithJSONObject(json.json, options: []) {
			data.writeToFile(filePath, atomically: false)
	}
}

extension AirtableData where Self: Cache {

	public static func load(key: String) -> Any? {
		if let json = loadJSON(key, expireAfter: expireAfter) {
			return Self(json: json, cache: false)
		}
		return nil
	}

	public func save() {
		if let id = id {
			saveJSON(json, toPath: id)
		}
	}
}

extension UIImageView {
	public func setImageURL(imageURL: String?) {
		if let imageURL = imageURL {
			Alamofire.request(.GET, imageURL).validate().response {[weak self] (_, _, data: AnyObject?, _) in
				if let data = data as? NSData {
					self?.image = UIImage(data: data)
				}
			}
		} else {
			image = nil
		}
	}
}

public protocol AnyField {
	init(_ key: String)
	func connect(json: JSON)
}

public class Relationship<T: AirtableData>: AnyField {
	private var raw: [String]?
	private let key: String
	public required init(_ key: String) {
		self.key = key
	}

	public func connect(json: JSON) {
		raw = json[key].array?.map { $0.string! }
	}

	public var count: Int { return raw?.count ?? 0 }

	public func hasKey(key: String) -> Bool {
		return raw?.contains(key) ?? false
	}

	public func get(closure: ([T], ErrorType?) -> ()) {
		guard let raw = raw else { closure([], nil); return }
		var results: [String: T] = [:]
		var anyError: ErrorType?
		let group = dispatch_group_create()
		for id in raw {
			dispatch_group_enter(group)
			T.Get(id) { (t, error) in
				if let error = error {
					anyError = error
				}
				if let t = t {
					results[id] = t
				}
				dispatch_group_leave(group)
			}
		}

		dispatch_group_notify(group, dispatch_get_main_queue()) {
			if let error = anyError {
				closure([], error)
			} else {
				var ts: [T] = []
				for id in raw {
					ts.append(results[id]!)
				}
				closure(ts, nil)
			}
		}
	}
}

public class Field<T>: AnyField {
	private let key: String
	private var json: JSON!
	public required init(_ key: String) {
		self.key = key
	}

	public func connect(json: JSON) {
		self.json = json[key]
	}

	public func get() -> T? {
		if T.self == Int.self {
			return json.int as? T
		} else if T.self == String.self {
			return json.string as? T
		} else {
			return nil
		}
	}
}

public class Attachment: AnyField {
	private let key: String
	private var url: String?
	public private(set) var thumbnailSize: CGSize?
	public required init(_ key: String) {
		self.key = key
	}

	public func connect(json: JSON) {
		if let thumbnail = json[key].array?.last?["thumbnails"]["large"] {
			thumbnailSize = CGSize(width: thumbnail["width"].double!, height: thumbnail["height"].double!)
			url = thumbnail["url"].string
		}
	}

	public func get() -> String? {
		return url
	}
}

public enum AirtableError: ErrorType {
	case ValidationError(String)
	case UncategorizedError(message: String, code: Int)
}

public enum Airtable: URLRequestConvertible {
	private static var hostPrefix: String!
	private static var authenticatingHeaders: [String: String]!

	case Get(String, [String: AnyObject]?)
	case Post(String, [String: AnyObject]?)
	case Put(String, [String: AnyObject]?)
	case Delete(String, [String: AnyObject]?)

	public var URLRequest: NSMutableURLRequest {
		let parameters: [String: AnyObject]?
		var method: Alamofire.Method = .POST
		let _path: String
		switch self {
		case .Get(let path, let _parameters):
			_path = path
			method = .GET
			parameters = _parameters
		case .Put(let path, let _parameters):
			_path = path
			method = .PUT
			parameters = _parameters
		case .Post(let path, let _parameters):
			_path = path
			parameters = _parameters
		case .Delete(let path, let _parameters):
			_path = path
			method = .DELETE
			parameters = _parameters
		}
		let encoding: Alamofire.ParameterEncoding
		switch method {
		case .POST, .PUT:
			encoding = .JSON
		default:
			encoding = .URL
		}

		let URL = NSURL(string: Airtable.hostPrefix)!
		let URLRequest = NSMutableURLRequest(URL: URL.URLByAppendingPathComponent(_path))
		URLRequest.HTTPMethod = method.rawValue
		for (k, v) in Airtable.authenticatingHeaders {
			URLRequest.setValue(v, forHTTPHeaderField: k)
		}
		return encoding.encode(URLRequest, parameters: parameters).0
	}

	public static func setup(appID: String, apiKey: String) {
		hostPrefix = "https://api.airtable.com/v0/\(appID)"
		authenticatingHeaders = ["Authorization": "Bearer \(apiKey)"]
	}

	public func response<T: AirtableData>(closure: (T?, ErrorType?) -> ()) {
		request(self).response { json, error in
			if let json = json {
				closure(T(json: json), error)
			} else {
				closure(nil, error)
			}
		}
	}

	public func response<T: AirtableData>(closure: ([T], ErrorType?) -> ()) {
		request(self).response { json, error in
			closure(json?["records"].array?.map { T(json: $0) } ?? [], error)
		}
	}
}

extension Alamofire.Request {
	private func translateError(response: Response<AnyObject, NSError>, code: Int, reason: String?, message: String) -> ErrorType {
		if code == 400 {
			switch reason {
			case .Some("validation_error"):
				return AirtableError.ValidationError(NSLocalizedString(message, comment: message))
			default:
				break
			}
		}
		return AirtableError.UncategorizedError(message: NSLocalizedString(message, comment: message), code: code)
	}

	private func response(closure: (JSON?, ErrorType?) -> ()) {
		responseJSON { response in
			if let json = response.result.value {
				guard let object = json as? [String: AnyObject] else {
					closure(nil, nil)
					return
				}
				guard let reason = object["error"] as? String, message = object["message"] as? String else {
					closure(JSON(object), nil)
					return
				}
				print("Application Error on request: \(self.debugDescription) \(object)")
				let code = object["status"] as? Int ?? 0
				let error = self.translateError(response, code: code, reason: reason, message: message)
				closure(nil, error)
			} else {
				print("Server Error on request: \(self.debugDescription) \(response.result.error) \(response.data)")
				if let error = response.result.error {
					let error = self.translateError(response, code: error.code, reason: error.localizedFailureReason, message: error.localizedDescription)
					closure(nil, error)
				} else {
					closure(nil, nil)
				}
			}
		}
	}
}