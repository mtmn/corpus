import { DuckDBInstance } from "@duckdb/node-api";
import { createHash } from "crypto";

export const sha256 = (str) => {
	return createHash("sha256").update(str).digest("hex");
};

export const connectImpl = (path, cb) => () => {
	DuckDBInstance.create(path)
		.then((instance) => instance.connect())
		.then((conn) => cb(null)(conn)())
		.catch((e) => cb(e)(null)());
};

export const runImpl = (conn, sql, params, cb) => () => {
	conn
		.run(sql, params)
		.then(() => cb(null)())
		.catch((e) => cb(e)());
};

export const checkpointImpl = (conn, cb) => () => {
	conn
		.run("CHECKPOINT")
		.then(() => cb(null)())
		.catch((e) => cb(e)());
};

// DuckDB returns BIGINT as BigInt, which JSON.stringify doesn't support.
// Pure transformation: produce new row objects rather than mutating in place.
const convertBigInts = (row) =>
	Object.fromEntries(
		Object.entries(row).map(([k, v]) => [
			k,
			typeof v === "bigint" ? Number(v) : v,
		]),
	);

export const allImpl = (conn, sql, params, cb) => () => {
	conn
		.run(sql, params)
		.then((result) => result.getRowObjectsJS())
		.then((rows) => {
			cb(null)(rows.map(convertBigInts))();
		})
		.catch((e) => cb(e)(null)());
};
