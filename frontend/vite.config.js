const fs = require('fs')

const certFile = process.env.TLS_CERT_FILE
const keyFile = process.env.TLS_KEY_FILE

module.exports = {
  server: {
    https: certFile && keyFile ? {
      cert: fs.readFileSync(certFile),
      key: fs.readFileSync(keyFile),
    } : undefined,
  },
}