# SVT Record

The project contains tools that can assist in downloading shows from Swedish television (svtplay.se).

## Installation

The script depends on PhantomJS as well as the Ruby gem for PhantomJS. To be able to download shows ffmpeg is also required:

    $ brew install phantomjs
    $ brew install ffmpeg
    $ gem install phantomjs

## Usage

svtrecord.rb [-b bitrate] [-o filename] [-u url]

    -b, --bitrate [bitrate]          The target bitrate for the saved file
    -h, --help                       Shows this help
    -o, --output [filename]          The filename for the output file
    -u, --url [url]                  The URL for the TV show to record

This program takes a URL to a show on SVTPlay.se and extracts the stream addresses so that the show can be saved locally. The program will list all available streams, along with the video size and an approximate file size.

The bitrate is specified in bits per second. The suffixes 'k' or 'M' can be used as substitution for 1 000 or 1 000 000 respectively.

If a bitrate is provided the script will automatically download the stream with the lowest bitrate that is higher than the specified bitrate. If no output file name is provided the program will use a filename based on the metadata of the stream. If the source includes a subtitle stream it will be included in the output which will be saved with the extension .mkv. Otherwise the output will have an .mp4 extension.

## Legal

Please note that this program is intended for personal use only.

## Contributing

1. Fork it ( https://github.com/mbergek/svtrecord/fork )
2. Create your feature branch (`git checkout -b my-new-feature`)
3. Commit your changes (`git commit -am 'Add some feature'`)
4. Push to the branch (`git push origin my-new-feature`)
5. Create a new Pull Request
