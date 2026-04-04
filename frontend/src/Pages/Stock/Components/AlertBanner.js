// Pages/Stock/Components/AlertBanner.js
// Audio playback is handled in Utils.Audio via purescript-web-html (no FFI needed).
// Only the Notifications API remains here — no PureScript binding exists for it.

export const showPullNotification = itemName => pullId => () => {
  if (!('Notification' in window)) return;

  const show = () => {
    const n = new Notification('New Stock Pull', {
      body: 'Item needed: ' + itemName,
      tag:  'pull-' + pullId,
    });
    n.onclick = () => {
      window.focus();
      const el = document.getElementById('pull-' + pullId);
      if (el) el.scrollIntoView({ behavior: 'smooth', block: 'center' });
      n.close();
    };
  };

  if (Notification.permission === 'granted') {
    show();
  } else if (Notification.permission !== 'denied') {
    Notification.requestPermission().then(p => { if (p === 'granted') show(); });
  }
};

export const requestNotificationPermission = () => {
  if ('Notification' in window && Notification.permission === 'default') {
    Notification.requestPermission();
  }
};