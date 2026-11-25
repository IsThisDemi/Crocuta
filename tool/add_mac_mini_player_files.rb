# Aggiunge al target Runner del Mac i file Swift del mini player e delle
# scorciatoie globali.
#
# Rilanciabile: i file gia' nel progetto non si toccano. Vanno nel gruppo
# Runner accanto a NowPlayingController.swift, solo nel target Runner (il
# widget CrocutaWidget non li usa).
#
# Uso: GEM_HOME=<cocoapods>/libexec ruby tool/add_mac_mini_player_files.rb
require 'xcodeproj'

FILES = %w[MiniPlayerController.swift MiniPlayerView.swift GlobalHotKeys.swift].freeze

root = File.expand_path('..', __dir__)
project = Xcodeproj::Project.open(File.join(root, 'macos/Runner.xcodeproj'))
runner = project.targets.find { |t| t.name == 'Runner' }
anchor = project.files.find { |f| f.path == 'NowPlayingController.swift' }
abort 'NowPlayingController.swift non trovato nel progetto' unless anchor
group = anchor.parent

added = FILES.reject { |name| group.files.any? { |f| f.path == name } }.map do |name|
  abort "manca macos/Runner/#{name}" unless File.exist?(File.join(root, 'macos/Runner', name))
  ref = group.new_reference(name)
  runner.add_file_references([ref])
  name
end

if added.empty?
  puts 'file del mini player gia\' presenti'
else
  project.save
  puts "aggiunti al target Runner: #{added.join(', ')}"
end
