export const openSSEImpl = function(url) {
  return function(onMessage) {
    return function(onStatus) {
      return function() {
        const source = new EventSource(url);

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