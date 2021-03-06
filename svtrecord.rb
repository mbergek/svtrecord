#!/usr/bin/env ruby
#
#  svtrecord.rb
#
#  This program records shows from Swedish Television. It uses PhantomJS to
#  simulate a web browser accessing the site and clicking on a video. It then
#  downloads information about the stream and provides download commands for
#  the various bitrates.
#
#  The script depends on PhantomJS as well as some Ruby gems. The program
#  ffmpeg is required to download the stream to a local file.
#
#  Copyright 2015, Martin Bergek
#
#  License: MIT
#
#  Install:
#  --------
#  $ brew install phantomjs
#  $ brew install ffmpeg
#  $ gem install phantomjs
#

require 'phantomjs'
require 'tempfile'
require 'net/http'
require 'uri'
require 'pp'
require 'optparse'

description = <<EOS

This program takes a URL to a show on svtplay.se and extracts the stream addresses
so that the show can be saved locally. It depends on a few applications which
must be installed:

	phantomjs
	ffmpeg

The program will list all available streams, along with the video size and an
approximate file size.

If a bitrate is provided the script will automatically download the stream with
the lowest bitrate that is higher than the specified bitrate. If no output file
name is provided the program will use a filename based on the metadata of the
stream.

EOS

class Integer
	def to_bitrate
		#return "%.2fMbps" % (self / 1000000.0) if self >= 1000000
		return "%.0fkbps" % (self / 1000.0) if self >= 1000
		return "%dbps" % self
	end
end

# Define custom converter
Bitrate = Struct.new(:string, :numeric)
def convert_bitrate string
	string.gsub('k', '000').gsub('M', '000000').to_i
end

options = {}
optparse = OptionParser.new do |opts|

	opts.accept(Bitrate) do |str|
		convert_bitrate str
	end

	opts.banner = "Usage: svtrecord.rb [-b bitrate] [-o filename] [-u url]\n\n"

	opts.on( '-b', '--bitrate [bitrate]', Bitrate, 'The target bitrate for the saved file' ) do |bitrate|
		options[:bitrate] = bitrate
	end
	opts.on( '-h', '--help', 'Shows this help' ) do
		puts opts
		puts description
		exit
	end
	opts.on( '-o', '--output [filename]', String, 'The filename for the output file' ) do |filename|
		options[:filename] = filename
	end
	opts.on( '-u', '--url [url]', String, 'The URL for the TV show to record' ) do |url|
		options[:url] = url
	end
end

optparse.parse!
unless options[:url]
	puts optparse
	puts description
	exit
end


# PhantomJS code to load the dynamic information about the show
js = <<JS
	var system = require('system');
	var page = require('webpage').create();

	// Make the client look like an iPad
	page.settings.userAgent = 'Mozilla/5.0 (iPad; CPU OS 9_2_1 like Mac OS X) AppleWebKit/601.1.46 (KHTML, like Gecko) Mobile/13D11';

	function click(el) {
		// Helper function to click on a DOM element
		var ev = document.createEvent("MouseEvent");
		ev.initMouseEvent("click", true, true, window, null, 0, 0, 0, 0, false, false, false, false, 0, null);
		el.dispatchEvent(ev);
	}

	page.onConsoleMessage = function(msg) {
		// console.log(msg);
	}

	page.onError = function (msg, trace) {
		// console.log(msg);
		// trace.forEach(function(item) { console.log('  ', item.file, ':', item.line); });
	};

	page.onLoadFinished = function(status) {
		page.evaluate(
			function() {
				// Click on the video to update the DOM
				document.querySelector('.play_titlepage__latest-video').click();
				document.querySelector('.svt_splash__video-icon--play').click();
				document.querySelector('button.svp_splash__btn-play').click();
			}
		);
		window.setTimeout(function() {
			// Retrieve information about the video
			var url2 = page.evaluate(function() { return document.querySelector('video.svp_video').getAttribute('src'); });
			var length = page.evaluate(function() { return document.querySelector('video.svp_video').getAttribute('data-video-length') })
			var title = page.evaluate(function() { return document.title });
			var alt = page.evaluate(function() { return document.querySelector('a.svtplayer img').getAttribute('alt') })
			var name = page.evaluate(function() { return document.querySelector("meta[property='og:title']").content; })
			var description = page.evaluate(function() { return document.querySelector("meta[property='og:description']").content; })
			var filename = page.evaluate(function() { return document.querySelector("meta[property='og:url']").content.split('/').pop(); })

			console.log("url:" + url2);
			console.log("length:" + length);
			console.log("title:" + title);
			console.log("alt:" + filename);
			console.log("name:" + name);
			console.log("description:" + description);
			console.log("filename:" + filename);
			phantom.exit();
		}, 1000);
	};
	page.open(system.args[1], function(status) {});
JS

# Use PhantomJS to read the web page and get information about the m3u8 file
file = Tempfile.new('phantomjs')
file.write js
file.close

info = Hash[Phantomjs.run(file.path, options[:url]).lines.map { |l| (k,v) = l.chomp.split(':', 2); [k.to_sym, v] }]
file.unlink

puts "Meta  : #{info}"

# Read the M3U content, following redirects as required
base_url = info[:url]
response = Net::HTTP.get_response(URI(base_url))
while response.kind_of?(Net::HTTPRedirection)
	base_url = response['location']
	warn "Redirected to #{base_url}"
	response = Net::HTTP.get_response(URI(base_url))
end
m3u8 = response.body

media = Array.new
streams = Array.new

m3u8.split(/\n#/).each do |v|
	case v.split(/:/).first
	when "EXT-X-MEDIA"
		#puts "Media: #{v}"
		h = Hash[v.split(/:/, 2).last.split(/,(?=(?:[^"]|"[^"]*")*$)/).map { |l| 
			(k,v) = l.split('=', 2); [k.downcase.tr('-', '_').to_sym, v.tr('"', '')] }]
		h[:absolute_url] = URI::join(base_url, h[:uri]).to_s
		puts "Media : #{h}"
		media << h
	when "EXT-X-STREAM-INF"
		#puts "Stream: #{v}"
		lines = v.split(/\n/)
		h = Hash[lines.first.split(/:/, 2).last.split(/,(?=(?:[^"]|"[^"]*")*$)/).map { |l| 
			(k,v) = l.split('=', 2); [k.downcase.tr('-', '_').to_sym, v.tr('"', '')] }]
		h[:uri] = lines.last
		h[:absolute_url] = URI::join(base_url, h[:uri]).to_s
		puts "Stream: #{h}"
		streams << h
	else
		#puts "Ignored: #{v}"
	end
end

streams.sort_by! { |s| s[:average_bandwidth].to_i }

# Display information and the command to save the stream
puts
puts info[:alt]
puts "------------------------------------------------"
puts "Title  : #{info[:title]}"
puts "Length : #{info[:length]} seconds"
puts
puts "Bitrates:"
puts "---------"

filename = options[:filename] || info[:alt].downcase.tr('åäöàèé?!', 'aaoaee__').gsub(/[- ]/, '_').gsub(/_+/, '_')
autostream = nil

audio = media.find { |m| m[:type] == "AUDIO" && m[:autoselect] == "YES" }
subs = media.find { |m| m[:type] == "SUBTITLES" && m[:autoselect] == "YES" }

streams.each do |s|
	printf "%-12s %-12s %s MB\n", s[:bandwidth].to_i.to_bitrate , s[:resolution], s[:bandwidth].to_i * info[:length].to_i / 8 / 1000000
	cmd = "ffmpeg -loglevel quiet -stats -i '#{s[:absolute_url]}' #{ "-i '" + audio[:absolute_url] + "'" if audio } #{ "-i '" + subs[:absolute_url] + "'" if subs } -c copy -bsf:a aac_adtstoasc #{filename}_#{s[:bandwidth].to_i.to_bitrate}.#{ subs ? "mkv" : "mp4" }"
	puts cmd
	puts
	if autostream.nil? && options[:bitrate] && s[:bandwidth].to_i > options[:bitrate]
		autostream = cmd
	end
end

if autostream
	puts
	puts "Saving stream to #{filename}"
	puts
	exec(autostream)
end
