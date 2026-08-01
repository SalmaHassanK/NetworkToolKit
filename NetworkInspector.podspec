Pod::Spec.new do |s|

  s.name         = "NetworkInspector"
  s.version      = "1.0.0"
  s.summary      = "Network inspection and export tools for M-Pesa network flows"
  s.authors      = "salma.kamaleldin@vodafone.com"
  s.homepage     = "www.wit-software.com"
  s.description  = "Provides the NetworkInspector module as a standalone reusable pod."
  s.platform     = :ios, "11.0"
  s.swift_version = "5.0"

  s.source              = {
    :git => 'https://github.vodafone.com/vfgroup-mpa-superapp/NetworkToolKit.git',
    :tag => s.version.to_s
  }
  s.source_files        = "NetworkInspector/NetworkInspector/**/*.{h,m,mm,swift}"
  s.public_header_files = "NetworkInspector/NetworkInspector/**/*.h"
  s.module_name         = "NetworkInspector"

  s.dependency "ReactiveSwift", "7.1.1"

end
