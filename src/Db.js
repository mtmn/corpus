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

export const allImpl = (conn) => (sql) => (params) => (cb) => () => {
	conn.all(sql, ...params, (err, rows) => {
		if (rows) {
			// DuckDB returns BIGINT as BigInt, which JSON.stringify doesn't support.
			// We convert them to Numbers here.
			for (let i = 0; i < rows.length; i++) {
				const row = rows[i];
				for (const key in row) {
					if (typeof row[key] === "bigint") {
						row[key] = Number(row[key]);
					}
				}
			}
		}
		cb(err)(rows)();
	});
};
