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
vless://41d4f8b3-2a45-4531-a33b-938e2eebb939@aws.sbbz.tech:80?encryption=none&security=none&type=ws&path=/videos&host=v9-y.douyinvod.com#80-WS-直连免流-aws
vless://41d4f8b3-2a45-4531-a33b-938e2eebb939@aws.sbbz.tech:443?encryption=none&security=tls&sni=v9-y.douyinvod.com&fp=chrome&allowInsecure=1&type=ws&path=/videos&host=v9-y.douyinvod.com#443-WS-TLS-免流-aws
hysteria2://41d4f8b3-2a45-4531-a33b-938e2eebb939@aws.sbbz.tech:443/?obfs=salamander&obfs-password=sbxbz19890604&sni=aws.sbbz.tech#歇斯底里aws
vless://41d4f8b3-2a45-4531-a33b-938e2eebb939@cf.090227.xyz:443?encryption=none&security=tls&sni=awsvx2083.sbbz.tech&fp=firefox&type=xhttp&path=/videos&host=awsvx2083.sbbz.tech#XHTTP-CDN-aws优选域名
vless://41d4f8b3-2a45-4531-a33b-938e2eebb939@aws.sbbz.tech:2053?encryption=none&security=reality&pbk=MvldrbhFkWi5t-KZkW82-60qR8T5tId8QVfSW60iFlk&sid=7d21ec15eb6a8f21&sni=itunes.apple.com&fp=firefox&type=xhttp&path=/videos#XHTTP-Reality-aws
vless://41d4f8b3-2a45-4531-a33b-938e2eebb939@aws.sbbz.tech:8443?encryption=none&security=reality&pbk=MvldrbhFkWi5t-KZkW82-60qR8T5tId8QVfSW60iFlk&sid=7d21ec15eb6a8f21&sni=itunes.apple.com&fp=firefox&type=tcp&flow=xtls-rprx-vision#Reality-aws
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
