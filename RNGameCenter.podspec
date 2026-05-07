require 'json'
package = JSON.parse(File.read('package.json'))

Pod::Spec.new do |s|
  s.name         = 'react-native-game-center'
  s.version      = package['version']
  s.summary      = package['description']
  s.description  = package['description']
  s.homepage     = package['homepage']
  s.license      = package['license']
  s.author       = package['author']
  s.source       = { :git => 'https://github.com/vu-dang/react-native-game-center.git' }
  s.platform     = :ios, '13.0'
  s.source_files = 'RNGameCenter/ios/*.{h,m}'
  s.public_header_files = 'RNGameCenter/ios/*.h'
  s.requires_arc  = true
  s.dependency 'React-Core'
end