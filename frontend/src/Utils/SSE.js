// The streams are on the API origin and authenticate with the HttpOnly
// session cookie. A cross-origin EventSource sends cookies only when it is
// opened with withCredentials.
export const openSSEImpl = function(url) {
  return function(onMessage) {
    return function(onStatus) {
      return function() {
        const source = new EventSource(url, { withCredentials: true });

        source.onopen = function() {
          onStatus("connected")();
        };

        source.onmessage = function(e) {
          onMessage(e.data)();
        };

        source.onerror = function() {
          if (source.readyState === EventSource.CLOSED) {
            onStatus("closed")();
          } else {
            onStatus("reconnecting")();
          }
        };

        return function() {
          source.close();
          onStatus("closed")();
        };
      };
    };
  };
};
