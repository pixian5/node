cat << 'EOF' > check_reality_domains.sh
#!/usr/bin/env bash
set -euo pipefail

OUT_FILE="${OUT_FILE:-/root/reality_ok.txt}"
: > "$OUT_FILE"   # 清空输出文件

DOMAINS=$(cat << 'LIST'
a.189.cn
www.189.cn
gd.189.cn
wap.hb.189.cn
mgc.hb.189.cn
lt.hn.189.cn
wapsd.189.cn
wapjx.189.cn
wap.sc.189.cn
webwebfenxi.189.cn
wappay.189.cn
paygo.189.cn
dl.music.189.cn

vod3.nty.tv189.cn
h5.nty.tv189.com
dy3.nty.tv189.cn
ltewap.tv189.com
tp.nty.tv189.com
ltetp.tv189.com

open.4g.play.cn
hb.10000shequ.com

i0.hdslb.com
i1.hdslb.com

i0.hdslb.com
i1.hdslb.com

v26.douyinvod.com
v29.douyinvod.com
v3-z.douyinvod.com
v5-h.douyinvod.com
v9-y.douyinvod.com

p11.douyinpic.com
p26.douyinpic.com
p29.douyinpic.com
p3.douyinpic.com
p5-ipv6.douyinpic.com
p6.douyinpic.com

api5-normal-c-lq.amemv.com
log3-misc-lq.amemv.com

m.iqiyi.com
data.video.qiyi.com

m.youku.com
api.mobile.youku.com
www.youku.com
push.m.youku.com
vali-dns.cp31.ott.cibntv.net

mapdownload.autonavi.com
dualstack-mpsapi.amap.com
optimus-ads.amap.com
webapi.amap.com
mps.amap.com

static.tieba.baidu.com
newclient.map.baidu.com

dldir1.qq.com
grouptalk.c2c.qq.com
mmbiz.qlogo.cn
mp.weixin.qq.com
pingjs.qq.com
qzs.qq.com
wxsnsdythumb.wxs.qq.com
wxsnsdy.wxs.qq.com
mmbiz.qpic.cn
miniapp.gtimg.cn
short.weixin.qq.com
szextshort.weixin.qq.com

wx.tenpay.com
mclient.alipay.com

dl.stream.qqmusic.com

v5-dy-e.ixigua.com
v5-dy-gdhy.ixigua.com

asp.cntv.myalicdn.com

spend1.shuqireader.com
c1.shuqireader.com

tms.dingtalk.com

tobe.vip.weibo.com
new.vip.weibo.cn
simg.s.weibo.com

imhdfs.icbc.com.cn
v.icbc.com.cn
m.icbc.com.cn
m.mall.icbc.com.cn
elife.icbc.com.cn
act.icbc.com.cn
hit.icbc.com.cn
pv.mall.icbc.com.cn
mybank.icbc.com.cn

mi.com
api.ad.xiaomi.com
data.mistat.xiaomi.com
zbupic.zb.mi.com
f100.g.mi.com
LIST
)

need_cmd() { command -v "$1" >/dev/null 2>&1 || { echo "缺少命令：$1" >&2; exit 1; }; }
need_cmd openssl
need_cmd timeout
need_cmd awk
need_cmd grep
need_cmd sed

HAVE_CURL=0
if command -v curl >/dev/null 2>&1; then HAVE_CURL=1; fi

normalize_list() {
  echo "$DOMAINS" \
  | sed 's/\r$//' \
  | sed 's/#.*$//' \
  | sed 's/^[[:space:]]\+//; s/[[:space:]]\+$//' \
  | awk 'NF>0 {print}' \
  | awk '!seen[$0]++'
}

check_one() {
  local host="$1"
  local out
  out="$(timeout 8s openssl s_client -connect "${host}:443" -servername "${host}" -tls1_3 -alpn h2 < /dev/null 2>/dev/null || true)"
  echo "$out" | grep -qE 'Protocol[[:space:]]*:[[:space:]]*TLSv1\.3' || return 1
  echo "$out" | grep -qE 'ALPN protocol:[[:space:]]*h2' || return 1

  # curl 复核可选：如果你担心 curl 不支持 http2，就先别开
  if [ "$HAVE_CURL" -eq 1 ] && curl -V 2>/dev/null | grep -qi 'HTTP2'; then
    local hdr
    hdr="$(curl -sS -I --http2 --max-time 8 "https://${host}/" 2>/dev/null | head -n 1 || true)"
    echo "$hdr" | grep -qE '^HTTP/2' || return 1
  fi

  return 0
}

main() {
  while IFS= read -r d; do
    if check_one "$d"; then
      echo "$d" | tee -a "$OUT_FILE"
    fi
  done < <(normalize_list)

  echo
  echo "已写入：$OUT_FILE"
  echo "行数：$(wc -l < "$OUT_FILE" | tr -d ' ')"
}

main
EOF

chmod +x check_reality_domains.sh
bash check_reality_domains.sh