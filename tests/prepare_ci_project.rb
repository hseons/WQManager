#!/usr/bin/env ruby
# Generate an isolated conventional project for hosted Xcode 26 runners.
# The checked-in Xcode 27.2 project and signing configuration stay untouched.
require 'json'
require 'fileutils'
require 'xcodeproj'

root = File.expand_path('..', __dir__)
destination = ARGV.fetch(0)
abort 'Destination already exists' if File.exist?(destination)
FileUtils.mkdir_p(destination)
%w[WQManager WQManagerShare].each do |name|
  FileUtils.cp_r(File.join(root, 'WQManager', name), destination)
end
source = File.read(File.join(root, 'WQManager/WQManager.xcodeproj/project.xcproj'))
settings = JSON.parse(source.gsub(/,\s*(?=[}\]])/, ''))
project = Xcodeproj::Project.new(File.join(destination, 'WQManager.xcodeproj'))
project.root_object.development_region = settings['localizations']['development']
project.root_object.known_regions = %w[Base en zh-Hans]

def configure(configurations, settings)
  configurations.each do |configuration|
    settings.each do |key, value|
      match = key.match(/\A(.+)\[config=(.+)\]\z/)
      next if match && match[2] != configuration.name
      configuration.build_settings[match ? match[1] : key] = value
    end
  end
end

configure(project.build_configurations, settings['build-settings'])
targets = {}
shared_source = nil
settings['targets'].each do |definition|
  name = definition.fetch('name')
  type = definition['product-type'] == 'application' ? :application : :app_extension
  target = project.new_target(type, name, :ios, '26.0')
  configure(target.build_configurations, definition['build-settings'])
  group = project.main_group.new_group(name, name)
  Dir.glob(File.join(destination, name, '*.m')).sort.each do |path|
    reference = group.new_file(File.basename(path))
    target.source_build_phase.add_file_reference(reference)
    shared_source = reference if File.basename(path) == 'WQMSharedInbox.m'
  end
  if type == :application
    Dir.glob(File.join(destination, name, '*.xcassets')).sort.each do |path|
      target.resources_build_phase.add_file_reference(group.new_file(File.basename(path)))
    end
    Dir.glob(File.join(destination, name, 'Resources/*')).sort.each do |path|
      target.resources_build_phase.add_file_reference(group.new_file('Resources/' + File.basename(path)))
    end
    %w[Main.storyboard LaunchScreen.storyboard Localizable.strings].each do |resource|
      variant = group.new_variant_group(resource)
      Dir.glob(File.join(destination, name, '*.lproj', resource)).sort.each do |path|
        language = File.basename(File.dirname(path), '.lproj')
        reference = variant.new_file(language + '.lproj/' + resource)
        reference.name = language
      end
      target.resources_build_phase.add_file_reference(variant)
    end
  else
    target.source_build_phase.add_file_reference(shared_source)
  end
  targets[name] = target
end
main = targets.fetch('WQManager')
extension = targets.fetch('WQManagerShare')
main.add_dependency(extension)
embed = main.new_copy_files_build_phase('Embed App Extensions')
embed.dst_subfolder_spec = '13'
embed.add_file_reference(extension.product_reference).settings = { 'ATTRIBUTES' => ['RemoveHeadersOnCopy'] }
project.save
scheme = Xcodeproj::XCScheme.new
scheme.add_build_target(main)
scheme.set_launch_target(main)
scheme.save_as(project.path, 'WQManager', true)
puts project.path
