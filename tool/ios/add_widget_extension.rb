#!/usr/bin/env ruby
# frozen_string_literal: true

# Adds the "PersonalStorageWidgets" WidgetKit extension (lock-screen widgets + iOS 18 controls) to
# ios/Runner.xcodeproj. The Swift sources live in ios/PersonalStorageWidgets/ and are NOT part of
# the project until you run this script, so a plain `flutter run` on iOS is never affected.
#
#   gem install xcodeproj          # once (CocoaPods already depends on it)
#   ruby tool/ios/add_widget_extension.rb
#   open ios/Runner.xcworkspace    # pick your Team for BOTH targets under Signing & Capabilities
#
# Idempotent: running it again does nothing. See docs/NATIVE_INTEGRATIONS.md.

require 'xcodeproj'

ROOT        = File.expand_path('../..', __dir__)
PROJECT     = File.join(ROOT, 'ios', 'Runner.xcodeproj')
EXT_NAME    = 'PersonalStorageWidgets'
EXT_DIR     = File.join(ROOT, 'ios', EXT_NAME)
DEPLOYMENT  = '16.0' # lock-screen (accessory) widgets need iOS 16

abort "Missing #{PROJECT}. Run `flutter create --platforms=ios .` first." unless File.exist?(PROJECT)
abort "Missing #{EXT_DIR}." unless Dir.exist?(EXT_DIR)

project = Xcodeproj::Project.open(PROJECT)
runner  = project.targets.find { |t| t.name == 'Runner' } or abort 'Runner target not found'

if project.targets.any? { |t| t.name == EXT_NAME }
  puts "#{EXT_NAME} is already part of the project - nothing to do."
  exit 0
end

runner_settings = runner.build_configurations.first.build_settings
bundle_id       = runner_settings['PRODUCT_BUNDLE_IDENTIFIER'] or abort 'Runner has no PRODUCT_BUNDLE_IDENTIFIER'

# 1. The extension target ---------------------------------------------------------------------
ext = project.new_target(:app_extension, EXT_NAME, :ios, DEPLOYMENT)

group = project.main_group.find_subpath(EXT_NAME, true)
group.set_source_tree('<group>')
group.set_path(EXT_NAME)

swift_refs = Dir[File.join(EXT_DIR, '*.swift')].sort.map { |f| group.new_file(File.basename(f)) }
group.new_file('Info.plist')
ext.add_file_references(swift_refs)
%w[WidgetKit SwiftUI].each { |fw| ext.add_system_framework(fw) }

ext.build_configurations.each do |config|
  s = config.build_settings
  s['PRODUCT_BUNDLE_IDENTIFIER']    = "#{bundle_id}.widgets"
  s['PRODUCT_NAME']                 = '$(TARGET_NAME)'
  s['INFOPLIST_FILE']               = "#{EXT_NAME}/Info.plist"
  s['GENERATE_INFOPLIST_FILE']      = 'NO'
  s['SWIFT_VERSION']                = '5.0'
  s['TARGETED_DEVICE_FAMILY']       = '1,2'
  s['IPHONEOS_DEPLOYMENT_TARGET']   = DEPLOYMENT
  s['SKIP_INSTALL']                 = 'YES'
  s['CODE_SIGN_STYLE']              = 'Automatic'
  s['MARKETING_VERSION']            = '$(FLUTTER_BUILD_NAME)'
  s['CURRENT_PROJECT_VERSION']      = '$(FLUTTER_BUILD_NUMBER)'
  s['LD_RUNPATH_SEARCH_PATHS']      = ['$(inherited)', '@executable_path/Frameworks', '@executable_path/../../Frameworks']
  team = runner_settings['DEVELOPMENT_TEAM']
  s['DEVELOPMENT_TEAM'] = team if team
end

# 2. Embed it into the app ----------------------------------------------------------------------
embed = runner.new_copy_files_build_phase('Embed Foundation Extensions')
embed.symbol_dst_subfolder_spec = :plug_ins
build_file = embed.add_file_reference(ext.product_reference, true)
build_file.settings = { 'ATTRIBUTES' => %w[RemoveHeadersOnCopy] }
runner.add_dependency(ext)

# Flutter's "Thin Binary" script phase must run *after* the embed phase, otherwise Xcode reports
# "Cycle inside Runner; building could produce unreliable results".
thin = runner.build_phases.index { |p| p.respond_to?(:name) && p.name.to_s.include?('Thin Binary') }
if thin
  runner.build_phases.delete(embed)
  runner.build_phases.insert(thin, embed)
end

project.save
puts "Added #{EXT_NAME} (bundle id #{bundle_id}.widgets, iOS #{DEPLOYMENT}+)."
puts 'Next: open ios/Runner.xcworkspace and select your development team for both targets.'
