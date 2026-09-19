Pod::Spec.new do |s|

  s.name         = "NetworkInspector"
  s.version      = "1.0.1"
  s.summary      = "Network inspection and export tools for iOS"
  s.authors      = "salma.hassan.kamaleldin@gmail.com"
  s.homepage     = "https://github.com/SalmaHassanK/NetworkToolKit.git"
  s.description  = "Provides the NetworkInspector module as a standalone reusable pod."
  s.platform     = :ios, "13.0"
  s.swift_version = "5.0"

  s.license = {
    :type => "MIT",
    :file => "LICENSE"
  }

  s.source              = {
    :git => 'https://github.com/SalmaHassanK/NetworkToolKit.git',
    :tag => s.version.to_s
  }
  s.source_files        = "NetworkInspector/NetworkInspector/**/*.{h,m,mm,swift}"
  s.public_header_files = "NetworkInspector/NetworkInspector/**/*.h"
  s.module_name         = "NetworkInspector"

end
