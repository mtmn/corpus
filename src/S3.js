import {
	S3Client,
	PutObjectCommand,
	HeadObjectCommand,
	GetObjectCommand,
} from "@aws-sdk/client-s3";
import { getSignedUrl } from "@aws-sdk/s3-request-presigner";

const makeClient = (cfg) =>
	new S3Client({
		region: cfg.region || "us-east-1",
		endpoint: cfg.endpointUrl ?? undefined,
		forcePathStyle: cfg.addressingStyle === "path",
		credentials:
			cfg.accessKeyId && cfg.secretAccessKey
				? {
						accessKeyId: cfg.accessKeyId,
						secretAccessKey: cfg.secretAccessKey,
					}
				: undefined,
	});

export const uploadToS3Impl = (cfg, key, body, contentType, cb) => () => {
	const client = makeClient(cfg);
	const command = new PutObjectCommand({
		Bucket: cfg.bucket,
		Key: key,
		Body: body,
		ContentType: contentType,
	});

	client
		.send(command)
		.then(() => cb(null)())
		.catch((err) => cb(err)());
};

export const existsInS3Impl = (cfg, key, cb) => () => {
	const client = makeClient(cfg);
	const command = new HeadObjectCommand({
		Bucket: cfg.bucket,
		Key: key,
	});

	client
		.send(command)
		.then(() => cb(null)(true)())
		.catch((err) => {
			if (err.name === "NotFound" || err.$metadata?.httpStatusCode === 404) {
				cb(null)(false)();
			} else {
				cb(err)(false)();
			}
		});
};

export const getPresignedUrlImpl = (cfg, key, cb) => () => {
	const client = makeClient(cfg);
	const command = new GetObjectCommand({
		Bucket: cfg.bucket,
		Key: key,
	});

	getSignedUrl(client, command, { expiresIn: 86400 })
		.then((url) => cb(null)(url)())
		.catch((err) => cb(err)("")());
};

export const getS3UrlImpl = (cfg, key) => {
	const endpoint = cfg.endpointUrl || "";
	const bucket = cfg.bucket || "";
	if (cfg.addressingStyle === "path") {
		return `${endpoint}/${bucket}/${key}`;
	} else {
		return `${endpoint.replace("://", `://${bucket}.`)}/${key}`;
	}
};
