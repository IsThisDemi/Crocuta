# Aggiunge al progetto macOS il target del widget "In riproduzione".
#
# Gemello di tool/add_widget_target.rb per l'iPhone, rilanciabile: se il
# target c'e' gia' non tocca niente. Nessun team di sviluppo: l'app del Mac
# e' firmata ad-hoc da tool/build_macos.sh.
#
# Uso: GEM_HOME=<cocoapods>/libexec ruby tool/add_mac_widget_target.rb
require 'xcodeproj'

root = File.expand_path('..', __dir__)
project = Xcodeproj::Project.open(File.join(root, 'macos/Runner.xcodeproj'))
runner = project.targets.find { |t| t.name == 'Runner' }
if project.targets.any? { |t| t.name == 'CrocutaWidget' }
  puts 'target CrocutaWidget gia\' presente'
  exit 0
end

widget = project.new_target(:app_extension, 'CrocutaWidget', :osx, '14.0')
widget.product_name = 'CrocutaWidget'

unless widget.build_configurations.any? { |c| c.name == 'Profile' }
  release = widget.build_configurations.find { |c| c.name == 'Release' }
  profile = widget.add_build_configuration('Profile', :release)
  profile.build_settings.update(release.build_settings)
end

group = project.main_group.new_group('CrocutaWidget', 'CrocutaWidget')
widget_swift = group.new_file('CrocutaWidget.swift')
group.new_file('Info.plist')
group.new_file('CrocutaWidget.entitlements')
widget.add_file_references([widget_swift])

shared = project.main_group.new_group('Shared', 'Shared')
shared_swift = shared.new_file('CrocutaShared.swift')
widget.add_file_references([shared_swift])
runner.add_file_references([shared_swift])

%w[WidgetKit SwiftUI AppIntents].each do |fw|
  ref = project.frameworks_group.new_file("System/Library/Frameworks/#{fw}.framework", :sdk_root)
  widget.frameworks_build_phase.add_file_reference(ref)
end

widget.build_configurations.each do |c|
  s = c.build_settings
  s['PRODUCT_NAME'] = '$(TARGET_NAME)'
  s['PRODUCT_BUNDLE_IDENTIFIER'] = 'com.personal.demusLike.CrocutaWidget'
  s['INFOPLIST_FILE'] = 'CrocutaWidget/Info.plist'
  s['CODE_SIGN_ENTITLEMENTS'] = 'CrocutaWidget/CrocutaWidget.entitlements'
  s['MACOSX_DEPLOYMENT_TARGET'] = '14.0'
  s['SWIFT_VERSION'] = '5.0'
  s['SKIP_INSTALL'] = 'YES'
  s['CODE_SIGN_IDENTITY'] = '-'
  s['CODE_SIGN_STYLE'] = 'Manual'
  s['ENABLE_HARDENED_RUNTIME'] = 'NO'
  s['GENERATE_INFOPLIST_FILE'] = 'NO'
  s['LD_RUNPATH_SEARCH_PATHS'] = ['$(inherited)', '@executable_path/../Frameworks',
                                  '@executable_path/../../../../Frameworks']
  s.delete('DEVELOPMENT_TEAM')
end

runner.add_dependency(widget)
embed = runner.new_copy_files_build_phase('Embed Foundation Extensions')
embed.dst_subfolder_spec = '13' # PlugIns
bf = embed.add_file_reference(widget.product_reference, true)
bf.settings = { 'ATTRIBUTES' => ['RemoveHeadersOnCopy'] }

project.save
puts 'target CrocutaWidget aggiunto'
