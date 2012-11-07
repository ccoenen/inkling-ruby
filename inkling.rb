#! /bin/env ruby
# implementation of WPI File format used in Wacom Inkling
# Special Thanks to http://useful-tools.de/WPI-File-Downloads/WPI_FileFormat.pdf
# who did all the heavy lifting in documenting the binary file format.
#
# Ruby-Script by Claudius Coenen <coenen@meso.net>
#
# Copyright (C) 2012 Claudius Coenen
# This program is free software: you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation, version 3 of the License.
# 
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.
# 
# You should have received a copy of the GNU General Public License
# along with this program.  If not, see <http://www.gnu.org/licenses/>.

require 'rubygems'
require 'logger'
require 'rasem'

# Log levels:
# -2 (Infile-positions)
# -1 (All blocks including "unknown")
# DEBUG (All blocks except "unknown")
# INFO (Start and end info)
# WARN (unexpected things)
logger = Logger.new(STDOUT)
logger.sev_threshold = Logger::INFO

# Known Blocks in WPI format begin with these byte values (refer to the PDF linked above)
BLK_STROKE = 241
BLK_PEN_XY = 97
BLK_PEN_PRESSURE = 100
BLK_PEN_TILT = 101
BLK_UNKNOWN = 197
BLK_UNKNOWN_2 = 194
BLK_UNKNOWN_3 = 199
EXPECTED_BLOCKS = [BLK_STROKE, BLK_PEN_XY, BLK_PEN_PRESSURE, BLK_PEN_TILT, BLK_UNKNOWN, BLK_UNKNOWN_2, BLK_UNKNOWN_3]

# preparing svg output
svg = Rasem::SVGImage.new('210mm','297mm')
line_style = {:fill => 'none', :stroke => 'black'}

# preparing input
infile = ARGV[0];
logger.info "opening #{infile}"
File.open(infile, 'rb') do |f|
  # start position. I don't know what the first 2059 bytes are.
  f.pos = 2059
  block_descriptor = 0

  # coords collects x/y corrdinates to draw them into one polyline
  coords = []
  while !block_descriptor.nil? do
    logger.add -2, "Next block presumed at: #{f.pos.to_s(16)}"
    block_descriptor = f.getbyte
    if EXPECTED_BLOCKS.include? block_descriptor
      length = f.getbyte - 2 # first byte: descriptor, second byte: length
      case block_descriptor
        when BLK_STROKE
          bytes = f.getbyte
          type = if (bytes == 0)
            svg.polyline(*coords, line_style)
            "end"
          elsif (bytes == 1)
            coords = []
            "start"
          else
            coords = []
            "layer"
          end
          logger.debug "Stroke (#{block_descriptor}): type: #{type}, coords: #{coords.inspect}"
        when BLK_PEN_XY
          # unpack('s>') converts the bytes to a signed integer big-endian
          x = (f.read(2).unpack('s>')[0].to_f + 5) / 32 + 320
          # vertical resolution is half of horizontal, so we need to scale it.
          y = (f.read(2).unpack('s>')[0].to_f * 2 + 5) / 32

          coords.push x
          coords.push y
          logger.debug "XY (#{block_descriptor}): x: #{x}, y: #{y}"
        when BLK_PEN_PRESSURE
          # TODO pen pressure is not yet used
          bytes = f.read 2
          pressure = f.read(2).unpack('s>')[0]
          logger.debug "Pressure (#{block_descriptor}): #{pressure}"
        when BLK_PEN_TILT
          # TODO pen tilt is not yet used
          tilt_x = f.getbyte
          tilt_y = f.getbyte
          f.read 2 # rest of that block is unused
          logger.debug "Tilt (#{block_descriptor}): x: #{tilt_x} | y: #{tilt_y}"
        else
          # skipping over unknown blocks
          bytes = f.read length
          logger.add -1, "Unknown (#{block_descriptor}): #{length} bytes: #{bytes.inspect}"
      end
    elsif (block_descriptor.nil?)
      logger.info "EOF reached cleanly"
    else
      logger.warn "unexpected block descriptor: #{block_descriptor} at position #{f.pos} (dec) / #{f.pos.to_s(16)} (hex)"
      logger.warn block_descriptor.inspect
      exit 1
    end
  end
end

svg.close
outfile = infile + '.svg'
logger.info "writing to #{outfile}"
File.open(outfile, "w") do |f|
  f << svg.output
end
