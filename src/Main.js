import { config } from 'dotenv';

export const dotenvConfig = () => {
  config();
};

export const getQueryParam = (name) => (url) => () => {
  return url.searchParams.get(name);
};

export const split = (sep) => (str) => {
  return str.split(sep);
};

export const writeBuffer = (stream) => (buffer) => () => {
  stream.write(Buffer.from(buffer));
};

export const sanitizeKey = (str) => {
  return str.replace(/[^a-z0-9.-]/gi, '_').replace(/_{2,}/g, '_');
};
