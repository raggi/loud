require 'ffi-portaudio'
include FFI::PortAudio
require 'open3'

class VLC

  PATH = "/Applications/VLC.app/Contents/MacOS/VLC"
  ARGS = "--play-and-exit --fullscreen --video-on-top"
  EXIT = %r%end of playlist, exiting% #

  def initialize video = "http://www.youtube.com/watch?v=fg0X-WvMjug"
    @video = video
  end

  def start
    @thread = Thread.new { run_vlc }
  end

  def finished?
    @thread.join(0.01)
    !@thread.alive?
  end

  private
  def run_vlc
    Open3.popen3("exec #{PATH} #{ARGS} --open #{@video}") do |i, o, e, t|
      until e.eof?
        readables, writables = IO.select([o,e])
        lines = readables.map { |r| r.readline }.join("\n")

        puts lines if $DEBUG

        if EXIT =~ lines
          Process.kill "KILL", t.pid
          t.join
        end
      end
    end
  end
end

class VideoOnLoud < Stream

  def initialize
    @vlc = nil
  end

  def process(input, output, frameCount, timeInfo, statusFlags, userData)
    ints = input.read_array_of_uint8(frameCount)
    louds = ints.select { |v| v > 250 }.inject(0, :+)

    return :paContinue unless louds > 0

    vlc

    puts "LOUD #{louds}"

    :paContinue
  end

  def vlc
    if @vlc.nil? || @vlc.finished?
      @vlc = VLC.new.tap { |vlc| vlc.start }
    end
  end
end

trap(:INT) { exit }

API.Pa_Initialize

input = API::PaStreamParameters.new
input[:device] = API.Pa_GetDefaultInputDevice
input[:channelCount] = 1
input[:sampleFormat] = API::UInt8
input[:suggestedLatency] = 0
input[:hostApiSpecificStreamInfo] = nil

stream = VideoOnLoud.new
stream.open(input, nil, 44100, 1024)
stream.start

at_exit { 
  stream.close
  API.Pa_Terminate
}

sleep
