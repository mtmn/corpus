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
