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

options = {}
optparse = OptionParser.new do |opts|
    opts.banner = "Usage: svtrecord.rb [-b bitrate] [-o filename] [-u url]\n\n"

    opts.on( '-b', '--bitrate [bitrate]', Integer, 'The target bitrate for the saved file' ) do |bitrate|
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
    var page = require('webpage').create();
    page.onError = function(msg, trace) {};
    page.onLoadFinished = function(status) {
        page.evaluate(
            function() {
							$(".svtplayerCBContainer").click();
							$(".svtlib-svtplayer_overlay__button").click();
						}
        );
        window.setTimeout(function() {
            var url2 = page.evaluate(function() { return document.querySelector('video.svtplayerVideoNoIE').getAttribute('src'); });
            var length = page.evaluate(function() { return document.querySelector('a.svtplayer').getAttribute('data-length') })
            var title = page.evaluate(function() { return document.querySelector('a.svtplayer').getAttribute('data-title') })
            var alt = page.evaluate(function() { return document.querySelector('a.svtplayer img').getAttribute('alt') })

            console.log("url:" + url2);
            console.log("length:" + length);
            console.log("title:" + title);
            console.log("alt:" + alt);
            phantom.exit();
        }, 1000);
    };
    page.open(phantom.args[0], function(status) {});
JS

# Use PhantomJS to read the web page and get information about the m3u8 file
file = Tempfile.new('phantomjs')
file.write js
file.close
info = Hash[Phantomjs.run(file.path, options[:url]).lines.map { |l| (k,v) = l.chomp.split(':', 2); [k.to_sym, v] }]
file.unlink

# Get information about the streams
m3u8 = Net::HTTP.get(URI.parse(info[:url]))
streams = Array.new
m3u8.split(/\n/)[1..-1].each_slice(2) do |s, u|
    parts = s.scan(/.*BANDWIDTH=(\d*),RESOLUTION=([0-9x]*).*/)[0]
    streams << { :url => u, :bitrate => parts[0].to_i, :resolution => parts[1] }
end
streams.sort_by! { |s| s[:bitrate] }

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
streams.each do |s|
    if autostream.nil? && options[:bitrate] && s[:bitrate] > options[:bitrate]
        autostream = s[:url]
    end
    printf "%-12s %-12s %s MB\n", s[:bitrate] , s[:resolution], s[:bitrate].to_i * info[:length].to_i / 8 / 1000000
    puts "ffmpeg -i '#{s[:url]}' -c copy -bsf:a aac_adtstoasc #{filename}.mp4"
    puts
end

if autostream
    puts "Saving stream to #{filename}.mp4"
    exec("ffmpeg -i '#{autostream}' -c copy -bsf:a aac_adtstoasc #{filename}.mp4")
end
