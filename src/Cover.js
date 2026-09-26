const activeCacheFills = new Set();
const maxConcurrentCacheFills = 4;

export const tryStartCacheFillImpl = (key) => () => {
	if (activeCacheFills.has(key)) return false;
	if (activeCacheFills.size >= maxConcurrentCacheFills) return false;
	activeCacheFills.add(key);
	return true;
};

export const finishCacheFillImpl = (key) => () => {
	activeCacheFills.delete(key);
};

// Negative cache for cover lookups: remembers that no source had a cover for
// this key, so repeat page views do not re-hit the upstream APIs. Entries
// expire after one hour so a cover added upstream later is picked up.
const coverMisses = new Map();
const coverMissTtlMs = 3600000;

export const checkCoverMissImpl = (key) => () => {
	const expiry = coverMisses.get(key);
	if (expiry === undefined) return false;
	if (Date.now() > expiry) {
		coverMisses.delete(key);
		return false;
	}
	return true;
};

export const recordCoverMissImpl = (key) => () => {
	if (coverMisses.size > 10000) coverMisses.clear();
	coverMisses.set(key, Date.now() + coverMissTtlMs);
};
