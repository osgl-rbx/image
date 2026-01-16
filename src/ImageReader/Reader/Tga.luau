local Reader = script.Parent
local ImageReader = Reader.Parent
local Cursor = require(ImageReader.Parent.Cursor)
local ImageError = require(ImageReader.Parent.ImageError)
local Result = require(ImageReader.Parent.Result)
local ImageReaderStructs = require(ImageReader.structs)
local DynamicImageTypes = require(ImageReader.Parent.DynamicImage.types)
local util = require(Reader.util)

type Result<T, E> = Result.Result<T, E>
type ImageResult<T> = ImageError.ImageResult<T>
type DynamicImage<T> = DynamicImageTypes.DynamicImage<T>
type Dimensions = ImageReaderStructs.Dimensions
type Cursor = Cursor.Cursor
export type TgaHeader = {
	idLength: number,
	colorMapType: number,
	imageType: number,
	colorMapFirstEntry: number,
	colorMapLength: number,
	colorMapEntrySize: number,
	xOrigin: number,
	yOrigin: number,
	dimensions: Dimensions,
	pixelDepth: number,
	imageDescriptor: number,
}

local Tga = {
	canEncode = false,
}

function Tga.getHeader(cursor: Cursor): ImageResult<TgaHeader>
	local s, r = pcall(function(...)
		cursor.position = 0

		local bytestream = cursor:ReadByteCollection(18)
		local headerCursor = Cursor.new(bytestream)

		local idLength = headerCursor:ReadByte()
		local colorMapType = headerCursor:ReadByte()
		local imageType = headerCursor:ReadByte()

		local colorMapFirstEntry = headerCursor:ReadU16()
		local colorMapLength = headerCursor:ReadU16()
		local colorMapEntrySize = headerCursor:ReadByte()

		local xOrigin = headerCursor:ReadU16()
		local yOrigin = headerCursor:ReadU16()

		local dimensions = Tga.getDimensions(headerCursor):Unwrap()

		local pixelDepth = headerCursor:ReadByte()
		local imageDescriptor = headerCursor:ReadByte()
		
		local validPixelDepths = { [24] = true, [32] = true }

		if not validPixelDepths[pixelDepth] then
			return Result.err(ImageError.Unsupported)
		end

		local width, height = dimensions.width, dimensions.height
		if width <= 0 or height <= 0 then
			return Result.err(ImageError.Unsupported)
		end

		return Result.ok({
			idLength = idLength,
			colorMapType = colorMapType,
			imageType = imageType,
			colorMapFirstEntry = colorMapFirstEntry,
			colorMapLength = colorMapLength,
			colorMapEntrySize = colorMapEntrySize,
			xOrigin = xOrigin,
			yOrigin = yOrigin,
			dimensions = dimensions,
			pixelDepth = pixelDepth,
			imageDescriptor = imageDescriptor,
		})
	end)

	if not s then
		return Result.err(ImageError.Decoding)
	end

	return r
end

function Tga.getDimensions(cursor: Cursor): ImageResult<Dimensions>
	cursor.position = 12

	local s, r = pcall(function(...)
		local width, height = cursor:ReadU16(), cursor:ReadU16()
		return Result.ok({ width = width, height = height })
	end)

	if not s then
		return Result.err(ImageError.Decoding)
	end

	return r
end

function Tga.isFile(cursor: Cursor)
	local s, r = pcall(function(...)
		return Result.ok(Tga.getHeader(cursor).isOk)
	end)

	if not s then
		return Result.err(ImageError.Decoding)
	end

	return r
end

local createRGBAColor = util.createRGBAColor

function Tga.decode(cursor: Cursor)
	local s, r = pcall(function(...)
		local header = Tga.getHeader(cursor):Unwrap()
		if header.idLength > 0 then
			cursor:SkipBytes(header.idLength)
		end

		local is32Bit = header.pixelDepth == 32
		local dimensions = header.dimensions
		local width, height = dimensions.width, dimensions.height
		local bfr = buffer.create(width * height * 4)
		if header.imageType == 2 or header.imageType == 3 then
			-- Uncompressed
			local is24Bit = header.pixelDepth == 24
			
			local yStart, yEnd, yDir = 0, height - 1, 1
			
			if header.imageDescriptor == 0 then -- Image is vertically flipped
				yStart, yEnd, yDir = yEnd, yStart, -1
			end
			
			for y = yStart, yEnd, yDir do
				for x = 0, width - 1 do
					if is24Bit then
						local b, g, r = cursor:ReadByte(), cursor:ReadByte(), cursor:ReadByte()
						buffer.writeu32(bfr, (y * width + x) * 4, createRGBAColor(r, g, b))
					elseif is32Bit then
						local alphaBits = bit32.band(header.imageDescriptor, 0x0F)
						local b, g, r, a = cursor:ReadByte(), cursor:ReadByte(), cursor:ReadByte(), cursor:ReadByte()
						
						if alphaBits == 0 then a = 255 end -- ignore alpha if alphaBits is blank
					
						buffer.writeu32(bfr, (y * width + x) * 4, createRGBAColor(r, g, b, a))
					end
				end
			end

			return Result.ok(width, height, bfr, header)
		elseif header.imageType == 10 or header.imageType == 11 then
			local totalPixels = width * height
			local currentPixel = 0

			while currentPixel < totalPixels do
				local rlePacket = cursor:ReadByte()
				local isRLE = bit32.band(rlePacket, 0x80) ~= 0
				local count = bit32.band(rlePacket, 0x7f) + 1

				if isRLE then
					local b, g, r = cursor:ReadByte(), cursor:ReadByte(), cursor:ReadByte()
					local a = is32Bit and cursor:ReadByte() or 255
					local rgba = createRGBAColor(r, g, b, a)

					for _ = 1, count do
						buffer.writeu32(bfr, currentPixel * 4, rgba)
						currentPixel += 1
					end
				else
					for _ = 1, count do
						local b, g, r = cursor:ReadByte(), cursor:ReadByte(), cursor:ReadByte()
						local a = is32Bit and cursor:ReadByte() or 255
						local rgba = createRGBAColor(r, g, b, a)
						buffer.writeu32(bfr, currentPixel * 4, rgba)
						currentPixel += 1
					end
				end
			end
			
			-- Vertically flip the buffer
			local bufferUnflipped = buffer.create(width * height * 4)
			
			for y = 0, height - 1 do
				local sourceIndex = y * width * 4
				local targetIndex = (height - 1 - y) * width * 4

				-- Copy a row of the image straight onto the main buffer
				buffer.copy(
					bufferUnflipped,
					targetIndex,
					bfr,
					sourceIndex,
					width * 4
				)
			end

			return Result.ok(width, height, bufferUnflipped, header)
		else
			return Result.err(ImageError.Unsupported)
		end
	end)

	if s then
		return r
	end

	return Result.err(ImageError.Decoding)
end

return Tga
