#!/usr/bin/env ruby
# Adds the Safari Web Extension app-extension target to 2Password.xcodeproj and
# embeds it in the app. Idempotent: removes any prior "SafariExtension" target
# and its embed phase first, so it can be re-run safely.
require 'xcodeproj'

ROOT = File.expand_path('..', __dir__)
PROJECT = File.join(ROOT, '2Password.xcodeproj')
EXT_NAME = 'SafariExtension'
EXT_BUNDLE_ID = 'com.michael.twopassword.SafariExtension'

project = Xcodeproj::Project.open(PROJECT)
app = project.targets.find { |t| t.name == '2Password' } or abort 'app target not found'

# --- Clean slate (idempotent re-runs) ---
project.targets.select { |t| t.name == EXT_NAME }.each(&:remove_from_project)
app.dependencies.select { |d| d.target.nil? || d.target&.name == EXT_NAME }.each(&:remove_from_project)
app.build_phases.select { |p| p.display_name == 'Embed Foundation Extensions' }.each do |phase|
  phase.remove_from_project
  app.build_phases.delete(phase)
end
project.main_group.children.select { |g| g.respond_to?(:display_name) && g.display_name == EXT_NAME }.each(&:remove_from_project)

# --- Create the app-extension target ---
ext = project.new_target(:app_extension, EXT_NAME, :osx, '15.0', nil, :swift)

settings = {
  'PRODUCT_BUNDLE_IDENTIFIER'    => EXT_BUNDLE_ID,
  'PRODUCT_NAME'                 => '$(TARGET_NAME)',
  'DEVELOPMENT_TEAM'             => 'L5774582ZK',
  'CODE_SIGN_STYLE'              => 'Automatic',
  'CODE_SIGN_ENTITLEMENTS'       => 'SafariExtension/SafariExtension.entitlements',
  'INFOPLIST_FILE'               => 'SafariExtension/Info.plist',
  'GENERATE_INFOPLIST_FILE'      => 'YES',
  'MACOSX_DEPLOYMENT_TARGET'     => '15.0',
  'SWIFT_VERSION'                => '6.0',
  'SWIFT_EMIT_LOC_STRINGS'       => 'YES',
  'SKIP_INSTALL'                 => 'YES',
  'ENABLE_HARDENED_RUNTIME'      => 'YES',
  'CURRENT_PROJECT_VERSION'      => '1',
  'MARKETING_VERSION'            => '0.1.0',
  'LD_RUNPATH_SEARCH_PATHS'      => ['$(inherited)', '@executable_path/../../../../Frameworks'],
}
ext.build_configurations.each { |c| settings.each { |k, v| c.build_settings[k] = v } }

# --- Source + resource files ---
group = project.main_group.new_group(EXT_NAME, EXT_NAME)
group.new_reference('Info.plist')
group.new_reference('SafariExtension.entitlements')

%w[SafariWebExtensionHandler.swift AppGroupRelay.swift].each do |f|
  ext.source_build_phase.add_file_reference(group.new_reference(f))
end

res_group = group.new_group('Resources', 'Resources')
Dir.children(File.join(ROOT, EXT_NAME, 'Resources')).sort.each do |f|
  ext.resources_build_phase.add_file_reference(res_group.new_reference(f))
end

# --- Embed the .appex in the app (Contents/PlugIns) + build dependency ---
app.add_dependency(ext)
embed = app.new_copy_files_build_phase('Embed Foundation Extensions')
embed.symbol_dst_subfolder_spec = :plug_ins
bf = embed.add_file_reference(ext.product_reference)
bf.settings = { 'ATTRIBUTES' => ['RemoveHeadersOnCopy'] }

project.save
puts "Added target '#{EXT_NAME}' (#{EXT_BUNDLE_ID}) and embedded it in '#{app.name}'."
puts "App targets now: #{project.targets.map(&:name).join(', ')}"
