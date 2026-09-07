addEventListener("fetch", event => {
  event.respondWith(handleRequest(event.request))
})

async function handleRequest(request) {
  const subConfig = `<!DOCTYPE html>
<html>
  <head>
  <meta charset="utf-8" name="viewport" content="width=device-width, initial-scale=1">
  <title>dy</title>
  <style>
  button {
    all: unset;
    cursor: pointer;
    color: #007aff;
    word-break: break-word;
    display: block;
  }
  button:hover {
    color: #005ec4;
  }
  </style>
  </head>
    <body style="font-family: sans-serif; white-space: pre-line;">
<button onclick="copyText(this)">

vless://41d4f8b3-2a45-4531-a33b-938e2eebb939@l.sbbz.tech:80?encryption=none&security=none&type=ws&host=v9-y.douyinvod.com&path=/videos#80-WS-直连免流-l
vless://41d4f8b3-2a45-4531-a33b-938e2eebb939@l.sbbz.tech:443?encryption=none&security=tls&sni=l.sbbz.tech&type=ws&host=l.sbbz.tech&path=/videos#443-WS-TLS-免流-l
vless://41d4f8b3-2a45-4531-a33b-938e2eebb939@l.sbbz.tech:443?encryption=none&security=tls&sni=v9-y.douyinvod.com&type=xhttp&fp=chrome&path=/api/v1&mode=auto&allowInsecure=1&host=v9-y.douyinvod.com#443-XHTTP-免流-get-v1-l
hysteria2://41d4f8b3-2a45-4531-a33b-938e2eebb939@l.sbbz.tech:443/?obfs=salamander&obfs-password=sbxbz19890604&sni=l.sbbz.tech#歇斯底里l
vless://41d4f8b3-2a45-4531-a33b-938e2eebb939@bestcf.top:443?encryption=none&security=tls&sni=lvx2083.sbbz.tech&type=xhttp&path=/videos&host=lvx2083.sbbz.tech&fp=chrome&allowInsecure=1#XHTTP-CDN-l优选域名
vless://41d4f8b3-2a45-4531-a33b-938e2eebb939@l.sbbz.tech:2053?security=reality&pbk=IRn6xu8uB2Fd5-HtjnxcxNZdpAO142tttM-KH8qVpUM&sid=d5b2242f8d6a7641&fp=firefox&type=xhttp&path=/videos&sni=itunes.apple.com&mode=auto#XHTTP-Reality-l
vless://41d4f8b3-2a45-4531-a33b-938e2eebb939@l.sbbz.tech:8443?security=reality&pbk=IRn6xu8uB2Fd5-HtjnxcxNZdpAO142tttM-KH8qVpUM&sid=d5b2242f8d6a7641&fp=firefox&type=tcp&flow=xtls-rprx-vision&sni=itunes.apple.com#Reality-l

</button>

    <script>
      function copyText(el) {
        navigator.clipboard.writeText(el.textContent).catch(() => {});
      }
    </script>
  </body>
</html>`

return new Response(subConfig, {
  headers: {
    "Content-Type": "text/plain; charset=utf-8",
    "Content-Disposition": "attachment; filename=\"超究极死神订阅.txt\"",
    "Subscription-Userinfo": "upload=102400; download=204800; total=10737418240; expire=1893456000",
    "Profile-Update-Interval": "6",
  }
})
}
