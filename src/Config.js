import { readFileSync } from "fs";

export const loadConfigImpl = (path) => (onLeft) => (onRight) => () => {
	try {
		const json = readFileSync(path, { encoding: "utf8" });
		onRight(JSON.parse(json))();
	} catch (e) {
		onLeft(e.message || String(e))();
	}
};
