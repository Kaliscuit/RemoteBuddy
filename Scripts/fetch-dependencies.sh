#!/bin/zsh
set -euo pipefail
RB_ROOT="${0:A:h:h}"
source "$RB_ROOT/Installer/common.sh"
mkdir -p "$RB_ROOT/Dependencies"
while IFS=$'\t' read -r filename checksum url; do
  [[ -z "$filename" || "$filename" == \#* ]] && continue
  if [[ ! -f "$RB_ROOT/Dependencies/$filename" ]]; then
    /usr/bin/curl -fL --proto '=https' --proto-redir '=https' --retry 2 \
      --output "$RB_ROOT/Dependencies/$filename.partial" "$url"
    rb_verify_file "$RB_ROOT/Dependencies/$filename.partial" "$checksum"
    mv "$RB_ROOT/Dependencies/$filename.partial" "$RB_ROOT/Dependencies/$filename"
  fi
  rb_verify_file "$RB_ROOT/Dependencies/$filename" "$checksum"
done < "$RB_ROOT/Installer/dependencies.tsv"
print 'Dependencies verified. Apple PacketLogger must be supplied separately.'
