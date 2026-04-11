import { S3Client, PutObjectCommand, HeadObjectCommand } from "@aws-sdk/client-s3";

const getClient = () => new S3Client({
  region: process.env.S3_REGION || "us-east-1",
  endpoint: process.env.AWS_ENDPOINT_URL,
  forcePathStyle: process.env.AWS_S3_ADDRESSING_STYLE === "path",
  credentials: {
    accessKeyId: process.env.AWS_ACCESS_KEY_ID,
    secretAccessKey: process.env.AWS_SECRET_ACCESS_KEY
  }
});

export const uploadToS3Impl = (key) => (body) => (contentType) => (cb) => () => {
  const client = getClient();
  const command = new PutObjectCommand({
    Bucket: process.env.S3_BUCKET,
    Key: key,
    Body: body,
    ContentType: contentType
  });

  console.log(`S3: Uploading ${key} to bucket ${process.env.S3_BUCKET} at ${process.env.AWS_ENDPOINT_URL}`);

  client.send(command)
    .then(() => {
      console.log(`S3: Successfully uploaded ${key}`);
      cb(null)();
    })
    .catch((err) => {
      console.error(`S3: Upload failed for ${key}`, err);
      cb(err)();
    });
};

export const existsInS3Impl = (key) => (cb) => () => {
  const client = getClient();
  const command = new HeadObjectCommand({
    Bucket: process.env.S3_BUCKET,
    Key: key
  });

  client.send(command)
    .then(() => cb(true)())
    .catch((err) => {
      if (err.name === "NotFound" || err.$metadata?.httpStatusCode === 404) {
        cb(false)();
      } else {
        console.error(`S3: exists check failed for ${key}`, err);
        cb(false)();
      }
    });
};

export const getS3UrlImpl = (key) => {
  const endpoint = process.env.AWS_ENDPOINT_URL;
  const bucket = process.env.S3_BUCKET;
  if (process.env.AWS_S3_ADDRESSING_STYLE === "path") {
    return `${endpoint}/${bucket}/${key}`;
  } else {
    return `${endpoint.replace("://", `://${bucket}.`)}/${key}`;
  }
};
