# Crocuta: i framework sono quelli compilati da noi (libmpv v0.6.0 con i
# filtri audio di ffmpeg; vedi tool/build_libmpv.sh), gia' in Frameworks/.
# Qui niente download: si preparano solo i collegamenti agli header di mpv.
all: Frameworks/.symlinks

Frameworks/.symlinks:
	rm -rf Frameworks/.symlinks
	mkdir -p Frameworks/.symlinks/mpv
	sh create_framework_symlinks.sh Frameworks/Mpv.xcframework Frameworks/.symlinks/mpv

.PHONY: clean
clean:
	rm -rf Frameworks/.symlinks
