=begin
Copyright (c) 2015, maldicion069 (Cristian Rodríguez) <ccrisrober@gmail.con>
//
Permission to use, copy, modify, and/or distribute this software for any
purpose with or without fee is hereby granted, provided that the above
copyright notice and this permission notice appear in all copies.
//
THE SOFTWARE IS PROVIDED "AS IS" AND THE AUTHOR DISCLAIMS ALL WARRANTIES
WITH REGARD TO THIS SOFTWARE INCLUDING ALL IMPLIED WARRANTIES OF
MERCHANTABILITY AND FITNESS. IN NO EVENT SHALL THE AUTHOR BE LIABLE FOR
ANY SPECIAL, DIRECT, INDIRECT, OR CONSEQUENTIAL DAMAGES OR ANY DAMAGES
WHATSOEVER RESULTING FROM LOSS OF USE, DATA OR PROFITS, WHETHER IN AN
ACTION OF CONTRACT, NEGLIGENCE OR OTHER TORTIOUS ACTION, ARISING OUT OF
OR IN CONNECTION WITH THE USE OR PERFORMANCE OF THIS SOFTWARE.
=end

require_relative "concurrent_hash"

$RealObjects = ConcurrentHash.new

class Map
	def initialize(id, mapFields, width, height, keyObjects)
		@id = id
    @map_fields = mapFields
    @width = width
    @height = height
    @key_objects = keyObjects
	end

	#attr_accessor :id, :map_fields, :width, :height, :key_objects

	attr_reader :id, :map_fields, :width, :height, :key_objects

	def to_json(options = {})
		{"Id" => @id, "MapFields" => @map_fields, "Width" => @width, "Height" =>
        @height, "KeyObjects" => @key_objects}.to_json
	end # to_json

	def remove_key(idx)
	  idx = idx.to_s
	  puts @key_objects[idx]
	  if @key_objects[idx]
  		@key_objects[idx] = nil
  		return true	# return?
		end
		return false
	end

	def add_key(idx, px, py)
		puts idx
		$RealObjects[idx].posX = px
		$RealObjects[idx].posY = py
		@key_objects[idx] = $RealObjects[idx]
		@key_objects[idx]	# return?
	end
end
