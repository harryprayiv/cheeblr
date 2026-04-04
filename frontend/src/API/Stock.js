// frontend/src/API/Stock.js
// Uses the same callback-style FFI pattern as RegisterService and other
// existing API modules in this codebase.

const apiRequest = (url, method, token, body) =>
  fetch(url, {
    method,
    headers: {
      'Authorization': 'Bearer ' + token,
      'Content-Type': 'application/json',
    },
    ...(body !== '' ? { body } : {}),
  }).then(async r => {
    if (!r.ok) {
      const text = await r.text();
      throw new Error(text);
    }
    return r.json();
  });

export const fetchCb = url => method => token => body => onSuccess => onError => () => {
  apiRequest(url, method, token, body)
    .then(json => onSuccess(json)())
    .catch(e => onError(e.message || String(e))());
};