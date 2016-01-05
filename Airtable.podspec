Pod::Spec.new do |s|
  s.name             = "Airtable"
  s.version          = "1.0.2"
  s.summary          = "Connector for Airtable"
  s.description      = <<-DESC
  Defines your model as:
  public struct Document: AirtableData, Cache {
  	public static var expireAfter: NSTimeInterval { return 1800 }
  	public static var table: String { return "Documents" }
  	public var json: JSON!
  	public init() {}

  	public let topics = Relationship<Topic>("Topic")
  	public let organizations = Relationship<Organization>("Authoring Organization")
  	public let experts = Relationship<Expert>("Authoring Expert")
  	public let sourceURL = Field<String>("Source URL")
  	public let pages = Field<Int>("Pages")
  	public let title = Field<String>("Document Title")
  	public let notes = Field<String>("Internal Notes")
  	public let description = Field<String>("Description")
  }
  
  and do Get, List... directly, automatic cached.
                       DESC
  s.homepage         = "http://github.com/b051/Airtable"
  s.license          = 'MIT'
  s.author           = { "Rex Sheng" => "shengning@gmail.com" }
  s.source           = { :git => "https://github.com/b051/Airtable.git", :tag => s.version.to_s }
  s.requires_arc     = true
  s.platform         = :ios, "8.0"
  
  s.source_files = "*.swift"
  s.dependency 'Greycats', '~> 2.0'
  s.dependency 'Alamofire', '~> 3.0'
end
