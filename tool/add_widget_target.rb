# Aggiunge al progetto iOS il target del widget "In riproduzione".
#
# Una volta sola, ma rilanciabile: se il target c'e' gia' non tocca niente.
# Con la libreria xcodeproj di CocoaPods e non a mano: il progetto e' un
# grafo di identificativi, e un collegamento dimenticato non da' errori
# finche' Xcode non si rifiuta di aprirlo.
#
# Nessun team di sviluppo: la firma la fa AltStore con l'Apple ID
# personale, e un team scritto qui tornerebbe a chiedere quello aziendale.
#
# Uso: GEM_HOME=<cocoapods>/libexec ruby tool/add_widget_target.rb
require 'xcodeproj'

root = File.expand_path('..', __dir__)
project = Xcodeproj::Project.open(File.join(root, 'ios/Runner.xcodeproj'))
runner = project.targets.find { |t| t.name == 'Runner' }
if project.targets.any? { |t| t.name == 'CrocutaWidget' }
  puts 'target CrocutaWidget gia\' presente'
  exit 0
end

widget = project.new_target(:app_extension, 'CrocutaWidget', :ios, '17.0')
widget.product_name = 'CrocutaWidget'

group = project.main_group.new_group('CrocutaWidget', 'CrocutaWidget')
widget_swift = group.new_file('CrocutaWidget.swift')
group.new_file('Info.plist')
group.new_file('CrocutaWidget.entitlements')
widget.add_file_references([widget_swift])

# Il codice condiviso va in entrambi: i dati del brano e i comandi.
shared = project.main_group.new_group('Shared', 'Shared')
shared_swift = shared.new_file('CrocutaShared.swift')
widget.add_file_references([shared_swift])
runner.add_file_references([shared_swift])

runner_group = project.main_group.children.find { |g| g.respond_to?(:path) && g.path == 'Runner' }
runner_group.new_file('Runner.entitlements')

%w[WidgetKit SwiftUI AppIntents].each do |fw|
  ref = project.frameworks_group.new_file("System/Library/Frameworks/#{fw}.framework", :sdk_root)
  widget.frameworks_build_phase.add_file_reference(ref)
end

# Flutter costruisce anche in "Profile": il widget deve avere la stessa
# configurazione dell'app, o Xcode ne sceglie un'altra per lui.
unless widget.build_configurations.any? { |c| c.name == 'Profile' }
  release = widget.build_configurations.find { |c| c.name == 'Release' }
  profile = widget.add_build_configuration('Profile', :release)
  profile.build_settings.update(release.build_settings)
end

# La configurazione generata da Flutter, dove stanno versione e build:
# senza, nel widget restavano vuote e iOS rifiutava l'installazione
# ("bundleVersion must be set ... for an app extension").
generated = project.files.find { |f| f.path == 'Flutter/Generated.xcconfig' }

widget.build_configurations.each do |c|
  c.base_configuration_reference = generated if generated
  s = c.build_settings
  s['PRODUCT_NAME'] = '$(TARGET_NAME)'
  s['PRODUCT_BUNDLE_IDENTIFIER'] = 'dev.riccardo.demuslike.CrocutaWidget'
  s['INFOPLIST_FILE'] = 'CrocutaWidget/Info.plist'
  s['CODE_SIGN_ENTITLEMENTS'] = 'CrocutaWidget/CrocutaWidget.entitlements'
  s['IPHONEOS_DEPLOYMENT_TARGET'] = '17.0'
  s['SWIFT_VERSION'] = '5.0'
  s['TARGETED_DEVICE_FAMILY'] = '1,2'
  s['SKIP_INSTALL'] = 'YES'
  s['LD_RUNPATH_SEARCH_PATHS'] = ['$(inherited)', '@executable_path/Frameworks',
                                  '@executable_path/../../Frameworks']
  s['CODE_SIGN_STYLE'] = 'Automatic'
  s['GENERATE_INFOPLIST_FILE'] = 'NO'
  s['CURRENT_PROJECT_VERSION'] = '$(FLUTTER_BUILD_NUMBER)'
  s['MARKETING_VERSION'] = '$(FLUTTER_BUILD_NAME)'
  s.delete('DEVELOPMENT_TEAM')
end

runner.build_configurations.each do |c|
  c.build_settings['CODE_SIGN_ENTITLEMENTS'] = 'Runner/Runner.entitlements'
end

# Il widget si costruisce prima dell'app e ci finisce dentro, in PlugIns.
runner.add_dependency(widget)
embed = runner.copy_files_build_phases.find { |p| p.name == 'Embed Foundation Extensions' } ||
        runner.new_copy_files_build_phase('Embed Foundation Extensions')
embed.dst_subfolder_spec = '13' # PlugIns
bf = embed.add_file_reference(widget.product_reference, true)
bf.settings = { 'ATTRIBUTES' => ['RemoveHeadersOnCopy'] }
# Prima dello script "Thin Binary" di Flutter, che lavora sull'app finita.
runner.build_phases.delete(embed)
idx = runner.build_phases.index { |p| p.respond_to?(:name) && p.name.to_s.include?('Thin Binary') } ||
      runner.build_phases.length
runner.build_phases.insert(idx, embed)

project.save
puts 'target CrocutaWidget aggiunto'
