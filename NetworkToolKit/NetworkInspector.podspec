Pod::Spec.new do |s|

  s.name         = "NetworkInspector"
  s.version      = "1.0.2"
  s.summary      = "Network inspection and export tools for iOS"
  s.authors      = "salma.hassan.kamaleldin@gmail.com"
  s.homepage     = "https://github.com/SalmaHassanK/NetworkToolKit.git"
  s.description  = "Provides the NetworkInspector module as a standalone reusable pod."
  s.platform     = :ios, "13.0"
  s.swift_version = "5.0"

  s.license = {
    :type => "MIT",
    :file => "NetworkToolKit/LICENSE"
  }

  s.source              = {
    :git => 'https://github.com/SalmaHassanK/NetworkToolKit.git',
    :tag => s.version.to_s
  }
  s.source_files = "NetworkToolKit/NetworkInspector/NetworkInspector/**/*.{h,m,mm,swift}"
  s.module_name         = "NetworkInspector"

end
