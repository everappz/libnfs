#!/usr/bin/env ruby

require 'xcodeproj'

project_path = File.join(File.dirname(__FILE__), 'LibnfsTest.xcodeproj')
project = Xcodeproj::Project.new(project_path)

# macOS command line tool target
mac_target = project.new_target(:command_line_tool, 'LibnfsTest', :osx, '10.15')

group = project.main_group.new_group('LibnfsTest', 'LibnfsTest')
main_file = group.new_file('main.m')
mac_target.source_build_phase.add_file_reference(main_file)

mac_target.build_configurations.each do |config|
  config.build_settings['CLANG_ENABLE_OBJC_ARC'] = 'YES'
end

# iOS app target
ios_target = project.new_target(:application, 'LibnfsTestiOS', :ios, '13.0')

ios_group = project.main_group.new_group('LibnfsTestiOS', 'LibnfsTestiOS')
ios_main_file = ios_group.new_file('main.m')
ios_target.source_build_phase.add_file_reference(ios_main_file)

ios_target.build_configurations.each do |config|
  config.build_settings['CLANG_ENABLE_OBJC_ARC'] = 'YES'
  config.build_settings['PRODUCT_BUNDLE_IDENTIFIER'] = 'com.test.LibnfsTestiOS'
  config.build_settings['GENERATE_INFOPLIST_FILE'] = 'YES'
end

project.save
puts "Created #{project_path}"
