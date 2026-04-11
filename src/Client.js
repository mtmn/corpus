export const extractParam = (key) => (search) => {
  const params = new URLSearchParams(search);
  return params.get(key);
};

export const formatRFC3339 = (instant) => {
  return new Date(instant).toISOString();
};
