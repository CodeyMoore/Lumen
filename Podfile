platform :ios, '12.0'
project 'Lumen.xcodeproj'

target 'Lumen' do
  # VLC playback engine (plays MKV and nearly every codec; supports iOS 12).
  pod 'MobileVLCKit', '~> 3.6'
end

post_install do |installer|
  installer.pods_project.targets.each do |target|
    target.build_configurations.each do |config|
      config.build_settings['IPHONEOS_DEPLOYMENT_TARGET'] = '12.0'
    end
  end
end
