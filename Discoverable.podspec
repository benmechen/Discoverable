#
# Be sure to run `pod lib lint Discoverable.podspec' to ensure this is a
# valid spec before submitting.
#
# Any lines starting with a # are optional, but their use is encouraged
# To learn more about a Podspec see https://guides.cocoapods.org/syntax/podspec.html
#

Pod::Spec.new do |s|
  s.name             = 'Discoverable'
  s.version          = '0.1.0'
  s.summary          = 'Automatically discover and connect to other devices on the network'

# This description is used to generate tags and improve search results.
#   * Think: What does it do? Why did you write it? What is the focus?
#   * Try to keep it short, snappy and to the point.
#   * Write the description between the DESC delimiters below.
#   * Finally, don't worry about the indent, CocoaPods strips it!

  s.description      = <<-DESC
Discoverable is a Swift package that allows an iOS device to automatically discover and connect to any compatible devices on the network, without the need for IP addresses.
                       DESC

  s.homepage         = 'https://github.com/benmechen/Discoverable'
  # s.screenshots     = 'www.example.com/screenshots_1', 'www.example.com/screenshots_2'
  s.license          = { :type => 'MIT', :file => 'LICENSE' }
  s.author           = { 'benmechen' => 'psybm7@nottingham.ac.uk' }
  s.source           = { :git => 'https://github.com/benmechen/Discoverable.git', :tag => s.version.to_s }
  # s.social_media_url = 'https://twitter.com/<TWITTER_USERNAME>'

  s.ios.deployment_target = '12.0'

  s.source_files = 'Discoverable/Classes/**/*'
  
  # s.resource_bundles = {
  #   'Discoverable' => ['Discoverable/Assets/*.png']
  # }

  # s.public_header_files = 'Pod/Classes/**/*.h'
  # s.frameworks = 'UIKit', 'MapKit'
  # s.dependency 'AFNetworking', '~> 2.3'
end
