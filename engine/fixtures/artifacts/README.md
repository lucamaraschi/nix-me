# Synthetic artifacts

Pipeline tests construct their artifacts at runtime from arbitrary header bytes and
structured test data. No real application export, credential, or vendor-owned user
data belongs in this directory. The generated corpus covers header + gzip + JSON;
optional AES tests are enabled when OpenSSL is present.
