import duckdb from "duckdb";

export const connectImpl = (path) => (cb) => () => {
	const db = new duckdb.Database(path, (err) => {
		if (err) {
			cb(err)(null)();
		} else {
			try {
				const conn = db.connect();
				cb(null)(conn)();
			} catch (e) {
				cb(e)(null)();
			}
		}
	});
};

export const runImpl = (conn) => (sql) => (params) => (cb) => () => {
	conn.run(sql, ...params, (err) => {
		cb(err)();
	});
};

export const checkpointImpl = (conn) => (cb) => () => {
	conn.run("CHECKPOINT", (err) => {
		cb(err)();
	});
};

// DuckDB returns BIGINT as BigInt, which JSON.stringify doesn't support.
// Pure transformation: produce new row objects rather than mutating in place.
const convertBigInts = (row) =>
	Object.fromEntries(
		Object.entries(row).map(([k, v]) => [k, typeof v === "bigint" ? Number(v) : v]),
	);

export const allImpl = (conn) => (sql) => (params) => (cb) => () => {
	conn.all(sql, ...params, (err, rows) => {
		cb(err)(rows ? rows.map(convertBigInts) : rows)();
	});
};
