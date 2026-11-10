#!/bin/bash

# 源文件（全部位于当前目录，只读不改）
SRC_RTP="GuangdongIPTV_rtp.m3u8"
SRC_4K="GuangdongIPTV_rtp_4k.m3u"
SRC_ALL="GuangdongIPTV_rtp_all.m3u"
SRC_CHILD="GuangdongIPTV_rtp_chid.m3u"
SRC_HD="GuangdongIPTV_rtp_hd.m3u"
SRC_SD="GuangdongIPTV_rtp_sd.m3u"
SRC_PROBE="GuangdongIPTV_rtp_probe.txt"

EXTM3U_NAME='#EXTM3U name="IPTV"'
EXTM3U_TVG_NAME='#EXTINF:-1 tvg-name="Audio" group-title="IPTV-Audio",'

# 5 组服务器配置：目录/文件标签|地址前缀|地址后缀
SERVERS=(
    "1_252_8888|http://192.168.1.252:8888/udp/|"
    "18_18_8888|http://192.168.18.18:8888/udp/|"
    "18_16_5140|http://192.168.18.16:5140/app/rtp2httpd/udp/|?fcc=183.59.160.61:8027&r2h-token=ip261020Year"
    "18_15_5140|http://192.168.18.15:5140/app/rtp2httpd/udp/|?fcc=183.59.160.61:8027&r2h-token=ip261020Year"
    "18_10_5140|http://192.168.18.10:5140/app/rtp2httpd/udp/|?fcc=183.59.160.61:8027&r2h-token=ip261020Year"
)

#########################################################################
# 1. 从原始 all.m3u 构建 地址 -> 节目名 映射（不改动任何源文件）
#########################################################################
declare -A PROGRAM_MAP
while IFS= read -r line; do
    line="${line%$'\r'}"
    if [[ "$line" == "#EXTINF"* ]]; then
        prog_name="${line#*,}"
        prog_name="${prog_name%$'\r'}"
        read -r url_line
        url_line="${url_line%$'\r'}"
        addr="${url_line##*/}"
        PROGRAM_MAP["$addr"]="$prog_name"
    fi
done < "$SRC_ALL"

#########################################################################
# 2. 为每个服务器生成独立的目录与文件（全部覆盖生成）
#########################################################################
for entry in "${SERVERS[@]}"; do
    IFS='|' read -r dir prefix suffix <<< "$entry"
    mkdir -p "$dir"
    ip_tag="$dir"

    # sed 替换串中的 & 和 \ 需要转义
    esc_prefix=$(printf '%s' "$prefix" | sed 's/[&\\]/\\&/g')
    esc_suffix=$(printf '%s' "$suffix" | sed 's/[&\\]/\\&/g')

    # 2.1 生成各类 m3u / m3u8（> 重定向，自动覆盖旧文件）
    for src in "$SRC_RTP" "$SRC_4K" "$SRC_ALL" "$SRC_CHILD" "$SRC_HD" "$SRC_SD"; do
        [ -f "$src" ] || continue
        base="${src%.*}"
        ext="${src##*.}"
        out="${dir}/${base}_${ip_tag}.${ext}"
        tr -d '\r' < "$src" \
            | sed -E 's!^rtp://(.+)$!'"${esc_prefix}"'\1'"${esc_suffix}"'!' \
            > "$out"
    done

    # 2.2 生成 Audio.m3u（一次性重定向覆盖）
    #     规则：排除标准格式 (V: h264; A: mp2@2ch)，
    #           其余（cavs/avs/avs2、mp2@1ch、(; ) 等异常/特殊格式）全部收录
    out_audio="${dir}/GuangdongIPTV_Audio_${ip_tag}.m3u"
    {
        echo "$EXTM3U_NAME"
        while IFS= read -r line; do
            line="${line%$'\r'}"
            [ -z "$line" ] && continue

            # 标准 h264 + mp2 双声道格式：跳过
            if echo "$line" | grep -qF '(V: h264; A: mp2@2ch)'; then
                continue
            fi

            addr=$(echo "$line" | awk '{print $1}')
            encode_info=$(echo "$line" | grep -o '([^)]*)' | head -n1)
            encode_info_clean=$(echo "$encode_info" | tr -d '[:space:]')
            prog_name="${PROGRAM_MAP[$addr]}"
            full_name="${prog_name}${encode_info_clean}"

            printf '%s%s\n' "$EXTM3U_TVG_NAME" "$full_name"
            printf '%s%s%s\n' "$prefix" "$addr" "$suffix"
        done < "$SRC_PROBE"
    } > "$out_audio"
done

echo "生成完成。目录："
ls -d */ 2>/dev/null