#
# To learn more about a Podspec see http://guides.cocoapods.org/syntax/podspec.html.
# Run `pod lib lint ever_up_to_date.podspec` to validate before publishing.
#
Pod::Spec.new do |s|
  s.name             = 'ever_up_to_date'
  s.version          = '0.0.1'
  s.summary          = 'Headless Flutter app updates with verified downloads.'
  s.description      = <<-DESC
Headless Flutter app updates with verified downloads.
                       DESC
  s.homepage         = 'https://github.com/linchi07/ever_up_to_date'
  s.license          = { :file => '../LICENSE' }
  s.author           = 'EverUp contributors'

  s.source           = { :path => '.' }
  s.source_files = 'ever_up_to_date/Sources/ever_up_to_date/**/*'

  # If your plugin requires a privacy manifest, for example if it collects user
  # data, update the PrivacyInfo.xcprivacy file to describe your plugin's
  # privacy impact, and then uncomment this line. For more information,
  # see https://developer.apple.com/documentation/bundleresources/privacy_manifest_files
  # s.resource_bundles = {'ever_up_to_date_privacy' => ['ever_up_to_date/Sources/ever_up_to_date/PrivacyInfo.xcprivacy']}

  s.dependency 'FlutterMacOS'

  s.platform = :osx, '10.11'
  s.pod_target_xcconfig = { 'DEFINES_MODULE' => 'YES' }
  s.swift_version = '5.0'
end
