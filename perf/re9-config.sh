#!/bin/sh
# Sets KEY=VALUE pairs in RE9's config.ini (any section), e.g. UpscalingAlgorithm=TAA FullScreenMode=true
set -eu
G="$HOME/GameHub/steamapps/common/Resident Evil Requiem"
for kv in "$@"; do
	k=${kv%%=*}; v=${kv#*=}
	grep -q "^$k=" "$G/config.ini" || { echo "no $k in config.ini" >&2; exit 1; }
	sed -i '' "s|^$k=.*|$k=$v|" "$G/config.ini"
done
tr -d '\r' < "$G/config.ini" | grep -E "^($(printf '%s\n' "$@" | sed 's/=.*//' | paste -sd'|' -))="
