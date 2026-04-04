// Utils/WebSocket.js

export const _openWebSocket = url => onMessage => onOpen => onClose => onError => () => {
  const ws = new WebSocket(url);
  ws.onmessage = (event) => onMessage(event.data)();
  ws.onopen    = () => onOpen();
  ws.onclose   = () => onClose();
  ws.onerror   = () => onError();
  return ws;
};

export const _closeWebSocket = ws => () => ws.close();