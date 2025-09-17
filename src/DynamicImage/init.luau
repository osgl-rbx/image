local Reader = require(script.Parent.ImageReader.Reader)
local ImageFormat = require(script.Parent.ImageFormat)
local ImageError = require(script.Parent.ImageError)
local Result = require(script.Parent.Result)
local types = require(script.types)

export type DynamicImage<T> = types.DynamicImage<T>

local DynamicImage = {}

function DynamicImage.Encode<T>(self: DynamicImage<T>, format: ImageFormat.ImageFormat): ImageError.ImageResult<buffer>
	local codecs = Reader.GetCodecs()
	local codec = codecs[format]
	if not codec then
		return Result.err(ImageError.Encoding)
	end

	if not codec.canEncode then
		return Result.err(ImageError.Unsupported)
	end

	return Result.ok(codec.encode(self.width, self.height, self.buffer))
end

function DynamicImage.ReadPixel<T>(self: DynamicImage<T>, x: number, y: number): number
	return buffer.readu32(self.buffer, (y * self.width + x) * 4)
end

function DynamicImage.ReadPixelRGBA<T>(self: DynamicImage<T>, x: number, y: number)
	local index = (y * self.width + x) * 4
	return buffer.readu8(self.buffer, index),
		buffer.readu8(self.buffer, index + 1),
		buffer.readu8(self.buffer, index + 2),
		buffer.readu8(self.buffer, index + 3)
end

return {
	new = function<T>(width: number, height: number, buffer: buffer, header: T): DynamicImage<T>
		if type(buffer) == "table" then
			buffer = buffer[1]
		end

		local self = table.clone(DynamicImage)
		self.width = width
		self.height = height
		self.buffer = buffer
		self.header = header

		return self
	end,
}
