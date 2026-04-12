import { config } from 'dotenv';

export const dotenvConfig = () => {
  config();
};

export const writeBuffer = (stream) => (buffer) => () => {
  stream.write(Buffer.from(buffer));
};

export const sanitizeKey = (str) => {
  return str.replace(/[^a-z0-9.-]/gi, '_').replace(/_{2,}/g, '_');
};
