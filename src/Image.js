import sharp from 'sharp';

export const convertToAvifImpl = (buffer) => () => {
  return sharp(buffer)
    .avif()
    .toBuffer()
    .then(resultBuffer => {
      // Extract the underlying ArrayBuffer
      return resultBuffer.buffer.slice(
        resultBuffer.byteOffset,
        resultBuffer.byteOffset + resultBuffer.byteLength
      );
    });
};
