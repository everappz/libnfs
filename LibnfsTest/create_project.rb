#!/usr/bin/env ruby

require 'xcodeproj'

project_path = File.join(File.dirname(__FILE__), 'LibnfsTest.xcodeproj')
project = Xcodeproj::Project.new(project_path)

target = project.new_target(:command_line_tool, 'LibnfsTest', :osx, '10.15')

group = project.main_group.new_group('LibnfsTest', 'LibnfsTest')
main_file = group.new_file('main.m')
target.source_build_phase.add_file_reference(main_file)

target.build_configurations.each do |config|
  config.build_settings['CLANG_ENABLE_OBJC_ARC'] = 'YES'
end

project.save
puts "Created #{project_path}"
