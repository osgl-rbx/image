local ImageFormat = require(script.Parent.Parent.ImageFormat)

export type DynamicImage<T> = {
    width: number,
    height: number,
    buffer: buffer,
    header: T,

    Encode: (self: DynamicImage<T>, format: ImageFormat.ImageFormat) -> buffer,

    ReadPixel: (x: number, y: number) -> number,
    ReadPixelRGBA: (x: number, y: number) -> (number, number, number, number)
}

return nil