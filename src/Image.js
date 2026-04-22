import sharp from 'sharp';

export const convertToAvifImpl = (buffer) => () =>
  new Promise((resolve, reject) =>
    sharp(buffer)
      .avif()
      .toBuffer((err, data) => {
        if (err) return reject(err);
        resolve(data.buffer.slice(data.byteOffset, data.byteOffset + data.byteLength));
      })
  );
