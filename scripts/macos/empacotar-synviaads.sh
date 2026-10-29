#!/usr/bin/env bash
# Monta o SynviaADS.app (o editor de vídeo da Synvia, fork do Concat) e instala em /Applications.
#
# Uso, na raiz do repositório:
#   scripts/macos/empacotar-synviaads.sh            # usa o binário já compilado
#   scripts/macos/empacotar-synviaads.sh --compilar # compila antes (release)
#
# Segue o mesmo caminho do Bundle (macOS) em .github/workflows/build-app.yml:
# binário, ícone, Info.plist e as bibliotecas do FFmpeg copiadas para dentro
# do app, para ele não depender do Homebrew. Assinatura ad hoc, que é o que o
# macOS exige para rodar em Apple silicon.
set -euo pipefail

export PATH="/opt/homebrew/bin:$HOME/.cargo/bin:$PATH"
raiz="$(cd "$(dirname "$0")/../.." && pwd)"
alvo="${CARGO_TARGET_DIR:-$HOME/.cache/concatzinho-target}"
nome="SynviaADS"
exe="synviaads"
versao="$(grep -m1 '^version' "$raiz/src/Cargo.toml" | sed 's/.*"\(.*\)".*/\1/')"
commit="$(git -C "$raiz" rev-parse --short HEAD)"

if [[ "${1:-}" == "--compilar" ]]; then
  (cd "$raiz/src" && CARGO_TARGET_DIR="$alvo" cargo build --release -p concat)
fi

binario="$alvo/release/concat"
[[ -x "$binario" ]] || { echo "Binário não encontrado em $binario. Rode com --compilar." >&2; exit 1; }
command -v dylibbundler >/dev/null || brew install dylibbundler

trabalho="$(mktemp -d)"
app="$trabalho/$nome.app"
mkdir -p "$app/Contents/MacOS" "$app/Contents/Resources" "$app/Contents/Frameworks"
cp "$binario" "$app/Contents/MacOS/$exe"

# Ícone: todos os tamanhos que o macOS pede, a partir do PNG de 1024.
icone="$raiz/assets/synvia/icon_1024.png"
iconset="$trabalho/$nome.iconset"
mkdir "$iconset"
for t in 16 32 128 256 512; do
  sips -z $t $t "$icone" --out "$iconset/icon_${t}x${t}.png" >/dev/null
  sips -z $((t*2)) $((t*2)) "$icone" --out "$iconset/icon_${t}x${t}@2x.png" >/dev/null
done
iconutil -c icns "$iconset" -o "$app/Contents/Resources/$nome.icns"

cat > "$app/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleName</key><string>$nome</string>
  <key>CFBundleDisplayName</key><string>$nome</string>
  <key>CFBundleIdentifier</key><string>com.synvia.ads</string>
  <key>CFBundleVersion</key><string>$versao+$commit</string>
  <key>CFBundleShortVersionString</key><string>$versao</string>
  <key>CFBundleExecutable</key><string>$exe</string>
  <key>CFBundleIconFile</key><string>$nome</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>LSMinimumSystemVersion</key><string>13.0</string>
  <key>NSHighResolutionCapable</key><true/>
  <key>NSSupportsAutomaticGraphicsSwitching</key><true/>
  <key>LSApplicationCategoryType</key><string>public.app-category.video</string>
  <key>NSHumanReadableCopyright</key><string>Synvia. Fork do Concat (github.com/jub0t/Concat), AGPL-3.0-or-later.</string>
  <key>NSMicrophoneUsageDescription</key><string>O SynviaADS grava narração pelo microfone.</string>
</dict>
</plist>
PLIST

# As bibliotecas do FFmpeg vão para dentro do app.
dylibbundler -od -b -x "$app/Contents/MacOS/$exe" -d "$app/Contents/Frameworks" -p @executable_path/../Frameworks >/dev/null
if otool -L "$app/Contents/MacOS/$exe" | grep -E '/opt/homebrew|/usr/local'; then
  echo "O app ainda depende de bibliotecas de fora dele." >&2; exit 1
fi

codesign --force --deep --sign - "$app"

# Fecha a versão aberta, troca em /Applications e registra no Launchpad.
pkill -x "$exe" 2>/dev/null || true
rm -rf "/Applications/$nome.app"
mv "$app" "/Applications/$nome.app"
rm -rf "$trabalho"
/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister -f "/Applications/$nome.app" >/dev/null 2>&1 || true
echo "Pronto: /Applications/$nome.app ($versao+$commit)"

# O app antigo (Concatzinho) vai para o Lixo: o SynviaADS é a mesma ferramenta com o nome novo.
if [[ -d /Applications/Concatzinho.app ]]; then
  pkill -x concatzinho 2>/dev/null || true
  mv /Applications/Concatzinho.app "$HOME/.Trash/Concatzinho $(date +%H%M%S).app"
fi
