# Adds the WidgetKit extension (ios/GameWidgets) to the Xcode project.
# Run once: ruby tool/add_ios_widget.rb (needs `gem install xcodeproj`).
require 'xcodeproj'

project = Xcodeproj::Project.open('ios/Runner.xcodeproj')
name = 'GameWidgetsExtension'
if project.targets.any? { |t| t.name == name }
  puts 'already there'
  exit
end

runner = project.targets.find { |t| t.name == 'Runner' }
ext = project.new_target(:app_extension, name, :ios, '17.0', nil, :swift)

group = project.main_group.new_group('GameWidgets', 'GameWidgets')
sources = %w[GameWidgetsBundle.swift DiceWidget.swift GameNightWidget.swift]
ext.add_file_references(sources.map { |f| group.new_reference(f) })
group.new_reference('Info.plist')
group.new_reference('GameWidgets.entitlements')

# Flutter also builds a "Profile" configuration.
release = ext.build_configurations.find { |c| c.name == 'Release' }
unless ext.build_configurations.any? { |c| c.name == 'Profile' }
  profile = project.new(Xcodeproj::Project::Object::XCBuildConfiguration)
  profile.name = 'Profile'
  profile.build_settings = release.build_settings.dup
  ext.build_configuration_list.build_configurations << profile
end

ext.build_configurations.each do |c|
  s = c.build_settings
  s['PRODUCT_BUNDLE_IDENTIFIER'] = 'de.sommer2019.mobileGames.GameWidgets'
  s['PRODUCT_NAME'] = '$(TARGET_NAME)'
  s['INFOPLIST_FILE'] = 'GameWidgets/Info.plist'
  s['GENERATE_INFOPLIST_FILE'] = 'NO'
  s['CODE_SIGN_ENTITLEMENTS'] = 'GameWidgets/GameWidgets.entitlements'
  s['SWIFT_VERSION'] = '5.0'
  s['IPHONEOS_DEPLOYMENT_TARGET'] = '17.0'
  s['TARGETED_DEVICE_FAMILY'] = '1,2'
  s['MARKETING_VERSION'] = '1.0'
  s['CURRENT_PROJECT_VERSION'] = '1'
  s['SKIP_INSTALL'] = 'YES'
  s['APPLICATION_EXTENSION_API_ONLY'] = 'YES'
  s['LD_RUNPATH_SEARCH_PATHS'] =
    ['$(inherited)', '@executable_path/Frameworks', '@executable_path/../../Frameworks']
end

runner.add_dependency(ext)
embed = runner.new_copy_files_build_phase('Embed Foundation Extensions')
embed.symbol_dst_subfolder_spec = :plug_ins
file = embed.add_file_reference(ext.product_reference, true)
file.settings = { 'ATTRIBUTES' => ['RemoveHeadersOnCopy'] }

# Embedding must happen before Flutter's "Thin Binary" script, otherwise
# Xcode reports a dependency cycle.
phases = runner.build_phases
thin = phases.find { |p| p.respond_to?(:name) && p.name == 'Thin Binary' }
if thin
  phases.delete(embed)
  phases.insert(phases.index(thin), embed)
end

project.main_group['Runner'].new_reference('Runner.entitlements')
runner.build_configurations.each do |c|
  c.build_settings['CODE_SIGN_ENTITLEMENTS'] = 'Runner/Runner.entitlements'
end

project.save
puts 'added'
